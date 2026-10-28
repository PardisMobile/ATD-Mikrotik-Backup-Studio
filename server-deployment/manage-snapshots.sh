#!/usr/bin/env bash
set -Eeuo pipefail

STATE=/var/lib/atd-mikrotik-backup-studio
[[ -d "$STATE" && ! -L "$STATE" && "$(stat -c '%U:%G' "$STATE")" == 'atdbackup:atdbackup' ]] || {
  echo 'ATD state directory ownership or type is invalid.' >&2
  exit 2
}
[[ "$(/usr/bin/readlink -f -- "$STATE")" == "$STATE" ]] || {
  echo 'ATD state directory path is not canonical.' >&2
  exit 2
}
exec 9>"$STATE/update.lock"
/usr/bin/flock -n 9 || { echo 'An ATD update is running; retry after it finishes.' >&2; exit 9; }

case "${1:-}" in
  list)
    [[ "$#" -eq 1 ]] || exit 2
    for snapshot in "$STATE"/code-backup-*; do
      [[ -d "$snapshot" && ! -L "$snapshot" ]] || continue
      name=${snapshot##*/}
      [[ "$name" =~ ^code-backup-[0-9]{14}$ ]] || continue
      [[ "$(stat -c '%u:%g' "$snapshot" 2>/dev/null)" == '0:0' ]] || continue
      bytes=$(/usr/bin/du -sb -- "$snapshot" 2>/dev/null | /usr/bin/awk '{print $1}')
      mtime=$(stat -c '%Y' "$snapshot" 2>/dev/null)
      [[ "$bytes" =~ ^[0-9]+$ && "$mtime" =~ ^[0-9]+$ ]] || continue
      state=unverified
      [[ -f "$snapshot/update-success" && ! -L "$snapshot/update-success" ]] \
        && /usr/bin/grep -qx 'status=success' "$snapshot/update-success" && state=success
      printf '%s\t%s\t%s\t%s\n' "$name" "$bytes" "$mtime" "$state"
    done | /usr/bin/sort -t $'\t' -k3,3nr
    ;;
  delete)
    [[ "$#" -eq 2 && "${2:-}" =~ ^code-backup-[0-9]{14}$ ]] || {
      echo 'Invalid ATD snapshot name.' >&2
      exit 2
    }
    target="$STATE/$2"
    [[ -d "$target" && ! -L "$target" && "$(/usr/bin/readlink -f -- "$target")" == "$STATE/$2" ]] || {
      echo 'ATD snapshot not found or path is not safe.' >&2
      exit 3
    }
    [[ "$(stat -c '%u:%g' "$target")" == '0:0' ]] || {
      echo 'ATD snapshot ownership is unexpected.' >&2
      exit 4
    }
    /usr/bin/rm -rf -- "$target"
    [[ ! -e "$target" ]] || { echo 'ATD snapshot could not be removed.' >&2; exit 5; }
    ;;
  *)
    echo 'Allowed commands: list, delete <ATD snapshot name>.' >&2
    exit 2
    ;;
esac

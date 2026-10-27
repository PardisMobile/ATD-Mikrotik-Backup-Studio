#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$#" -eq 0 ]] || { echo "Arguments are not accepted." >&2; exit 2; }
[[ "$(id -u)" -eq 0 ]] || { echo "This helper must run as root." >&2; exit 2; }
STATE=/var/lib/atd-mikrotik-backup-studio
REQUEST="$STATE/requested-system-timezone"
ZONE_ROOT=/usr/share/zoneinfo
[[ -r "$REQUEST" ]] || { echo "No requested system time zone was supplied." >&2; exit 3; }
mapfile -t requested < "$REQUEST"
[[ "${#requested[@]}" -eq 1 ]] || { echo "Invalid time-zone request." >&2; exit 4; }
zone="${requested[0]}"
[[ "$zone" =~ ^(UTC|[A-Za-z_+-]+(/[A-Za-z0-9_+.-]+)+)$ ]] || { echo "Invalid IANA time-zone name." >&2; exit 4; }
zone_path="$(realpath -e -- "$ZONE_ROOT/$zone" 2>/dev/null)" || { echo "Time zone is not installed on this server." >&2; exit 5; }
[[ "$zone_path" == "$ZONE_ROOT/"* && -f "$zone_path" ]] || { echo "Time zone path is outside the zone database." >&2; exit 5; }
command -v timedatectl >/dev/null 2>&1 || { echo "timedatectl is unavailable; system time zone was not changed." >&2; exit 6; }
old_zone="$(timedatectl show --property=Timezone 2>/dev/null | sed -n 's/^Timezone=//p')"
old_path="$(realpath -e -- "$ZONE_ROOT/$old_zone" 2>/dev/null)" || { echo "Could not determine the previous system time zone safely." >&2; exit 7; }
restore_previous_zone() {
  timedatectl set-timezone "$old_zone" >/dev/null 2>&1 || true
}
timedatectl set-timezone "$zone"
actual="$(timedatectl show --property=Timezone 2>/dev/null | sed -n 's/^Timezone=//p')"
actual_path="$(realpath -e -- "$ZONE_ROOT/$actual" 2>/dev/null)" || {
  restore_previous_zone
  echo "Could not verify the applied system time zone; restored the previous zone." >&2
  exit 7
}
if [[ "$actual_path" != "$zone_path" ]]; then
  restore_previous_zone
  echo "Could not verify the applied system time zone; restored the previous zone." >&2
  exit 7
fi
# The Cron helper writes CRON_TZ from the saved panel state. Reapply it now,
# rather than waiting for a later schedule save or leaving the old zone active.
if [[ ! -x /usr/local/sbin/atd-mikrotik-backup-cron ]] || ! /usr/local/sbin/atd-mikrotik-backup-cron --apply; then
  restore_previous_zone
  echo "Could not apply the saved Cron schedule; restored the previous system time zone." >&2
  exit 8
fi
printf 'Linux system and ATD Cron time zones set to %s. The system clock itself was not manually changed.\n' "$zone"

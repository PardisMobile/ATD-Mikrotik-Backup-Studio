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
timedatectl set-timezone "$zone"
actual="$(timedatectl show --property=Timezone 2>/dev/null | sed -n 's/^Timezone=//p')"
[[ "$actual" == "$zone" ]] || { echo "Could not verify the applied system time zone." >&2; exit 7; }
printf 'Linux system time zone set to %s. The system clock itself was not manually changed.\n' "$zone"

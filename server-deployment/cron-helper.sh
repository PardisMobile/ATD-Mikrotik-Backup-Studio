#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG=/etc/atd-mikrotik-backup-studio/config.php
CRON_FILE=/etc/cron.d/atd-mikrotik-backup-telegram
[[ "$#" -eq 1 && "$1" == "--apply" ]] || { echo "Usage: $0 --apply" >&2; exit 2; }
[[ -s "$CONFIG" ]] || { echo "ATD private configuration is missing." >&2; exit 3; }
command -v php >/dev/null 2>&1 || { echo "PHP CLI is required." >&2; exit 4; }

settings="$(php -r '
require "/etc/atd-mikrotik-backup-studio/config.php";
$state = [];
if (is_file(STATE_FILE)) {
    $raw = @file_get_contents(STATE_FILE);
    if (is_string($raw)) {
        $prefix = "<?php http_response_code(404); exit; ?>\n";
        if (strncmp($raw, $prefix, strlen($prefix)) === 0) $raw = substr($raw, strlen($prefix));
        $decoded = json_decode($raw, true);
        if (is_array($decoded)) $state = $decoded;
    }
}
$saved = $state["_delivery_schedule"] ?? [];
$times = is_array($saved) && isset($saved["backup_times"]) && is_array($saved["backup_times"])
    ? $saved["backup_times"]
    : (defined("BACKUP_SCHEDULE_TIMES") && is_array(BACKUP_SCHEDULE_TIMES) ? BACKUP_SCHEDULE_TIMES : []);
$delay = is_array($saved) && isset($saved["delay_minutes"])
    ? (int)$saved["delay_minutes"]
    : (defined("TELEGRAM_DELAY_MINUTES") ? (int)TELEGRAM_DELAY_MINUTES : 2);
echo implode(",", array_map(static fn($t) => substr((string)$t, 0, 5), $times)), "\n", $delay, "\n";
')" || { echo "Could not read saved delivery schedule." >&2; exit 5; }

mapfile -t values <<< "$settings"
times_csv="${values[0]:-}"
delay="${values[1]:-2}"
[[ "$delay" =~ ^[0-9]{1,2}$ ]] && (( delay <= 30 )) || { echo "Invalid Telegram delay in saved settings." >&2; exit 6; }

declare -A scheduled=()
legacy_mode=0
if [[ -z "$times_csv" ]]; then
  # Legacy installs did not persist RouterOS schedule times; retain their safe
  # compatibility behavior until the administrator saves a schedule in the panel.
  legacy_mode=1
else
  IFS=',' read -r -a times <<< "$times_csv"
  ((${#times[@]} >= 1 && ${#times[@]} <= 2)) || { echo "Expected one or two backup times." >&2; exit 6; }
  for value in "${times[@]}"; do
    [[ "$value" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] || { echo "Invalid backup time in saved settings." >&2; exit 6; }
    hour=$((10#${value:0:2}))
    minute=$((10#${value:3:2}))
    start=$((hour * 60 + minute + delay))
    # Retry the scanner once per minute for six minutes, starting after the
    # requested delay, so a slow SFTP upload can finish without changing RouterOS.
    for ((offset=0; offset<=5; offset++)); do
      total=$(((start + offset) % 1440))
      cron_minute=$((total % 60))
      cron_hour=$((total / 60))
      scheduled["$cron_minute $cron_hour"]="$cron_minute $cron_hour"
    done
  done
fi

tmp="$(mktemp /etc/cron.d/atd-mikrotik-backup-telegram.XXXXXX)"
trap 'rm -f -- "$tmp"' EXIT
if (( legacy_mode )); then
  printf '%s\n' '* * * * * atdbackup /usr/bin/php /opt/atd-mikrotik-backup-studio/send-backup.php --scan-backups >/dev/null 2>&1' > "$tmp"
else
  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    read -r cron_minute cron_hour <<< "$item"
    printf '%s %s * * * atdbackup /usr/bin/php /opt/atd-mikrotik-backup-studio/send-backup.php --scan-backups >/dev/null 2>&1\n' "$cron_minute" "$cron_hour" >> "$tmp"
  done < <(printf '%s\n' "${scheduled[@]}" | sort -n -k2,2 -k1,1)
fi
chown root:root "$tmp"
chmod 0644 "$tmp"
mv -f -- "$tmp" "$CRON_FILE"
trap - EXIT
echo "ATD Telegram cron schedule applied."

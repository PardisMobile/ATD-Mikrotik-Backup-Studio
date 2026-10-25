#!/usr/bin/env bash
set -Eeuo pipefail

[[ $(id -u) -eq 0 ]] || { echo 'Run with sudo: sudo atd-mikrotik-backup-update' >&2; exit 2; }
APP=/opt/atd-mikrotik-backup-studio
TLS=/etc/atd-mikrotik-backup-studio
STATE=/var/lib/atd-mikrotik-backup-studio
BASE='https://raw.githubusercontent.com/PardisMobile/ATD-Mikrotik-Backup-Studio/main/server-deployment'
for path in "$APP" "$TLS" "$STATE"; do [[ -d "$path" ]] || { echo "ATD installation not found ($path)." >&2; exit 3; }; done
[[ -s "$TLS/config.php" ]] || { echo 'Private first-run configuration is missing; update aborted.' >&2; exit 3; }
# Remove obsolete ATD-only scanner/worker units from previous releases; the cron job below replaces them.
LEGACY_UNITS=(
  atd-mikrotik-backup-telegram-scan.service atd-mikrotik-backup-telegram-scan.timer
  atd-mikrotik-backup-telegram-worker.service atd-mikrotik-backup-telegram-worker.timer
  atd-mikrotik-backup-worker.service atd-mikrotik-backup-worker.timer
  atd-mikrotik-backup-scanner.service atd-mikrotik-backup-scanner.timer
)
for unit in "${LEGACY_UNITS[@]}"; do systemctl disable --now "$unit" 2>/dev/null || true; rm -f "/etc/systemd/system/$unit"; done
# Preserve delivery baseline and state during updates.
systemctl daemon-reload
command -v curl >/dev/null 2>&1 || { echo 'curl is required; no packages were installed.' >&2; exit 4; }
command -v php >/dev/null 2>&1 || { echo 'PHP CLI is required; no packages were installed.' >&2; exit 4; }

TMP=$(mktemp -d /tmp/atd-update.XXXXXX)
chmod 0700 "$TMP"
STAMP=$(date +%Y%m%d%H%M%S)
BACKUP="$STATE/code-backup-$STAMP"
mkdir -m 0700 "$BACKUP"
cleanup(){ rm -rf -- "$TMP"; }
trap cleanup EXIT

for f in send-backup.php panel.css panel.js cron-helper.sh; do
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --max-time 60 "$BASE/$f" -o "$TMP/$f"
  [[ -s "$TMP/$f" ]] || { echo "Downloaded asset is empty: $f" >&2; exit 5; }
done
php -l "$TMP/send-backup.php" >/dev/null || { echo 'New PHP code failed syntax validation; live files were not changed.' >&2; exit 6; }
bash -n "$TMP/cron-helper.sh" || { echo 'New Cron helper failed shell syntax validation; live files were not changed.' >&2; exit 6; }
php -l "$TLS/config.php" >/dev/null || { echo 'Existing private configuration is invalid; live files were not changed.' >&2; exit 6; }
grep -q "require_once '/etc/atd-mikrotik-backup-studio/config.php';" "$TMP/send-backup.php" || { echo 'Downloaded PHP does not use the separate private configuration schema; update aborted.' >&2; exit 6; }
grep -q 'function telegram_settings()' "$TMP/send-backup.php" || { echo 'Downloaded PHP lacks panel-managed Telegram settings; update aborted.' >&2; exit 6; }
grep -q 'TELEGRAM_NOT_CONFIGURED' "$TMP/send-backup.php" || { echo 'Downloaded PHP lacks Telegram setup checks; update aborted.' >&2; exit 6; }

for f in send-backup.php panel.css panel.js; do
  [[ -f "$APP/$f" ]] && cp -p "$APP/$f" "$BACKUP/$f"
done
rollback(){
  echo 'Update failed; restoring previous ATD application files.' >&2
  for unit in atd-mikrotik-backup-telegram-scan.service atd-mikrotik-backup-telegram-scan.timer atd-mikrotik-backup-telegram-worker.service atd-mikrotik-backup-telegram-worker.timer atd-mikrotik-backup-worker.service atd-mikrotik-backup-worker.timer atd-mikrotik-backup-scanner.service atd-mikrotik-backup-scanner.timer; do
    systemctl disable --now "$unit" 2>/dev/null || true
    rm -f "/etc/systemd/system/$unit"
  done
  systemctl daemon-reload 2>/dev/null || true
  for f in send-backup.php panel.css panel.js; do
    if [[ -f "$BACKUP/$f" ]]; then cp -p "$BACKUP/$f" "$APP/$f"
    else rm -f -- "$APP/$f"; fi
  done
  if [[ -f "$BACKUP/cron-helper.sh" ]]; then cp -p "$BACKUP/cron-helper.sh" /usr/local/sbin/atd-mikrotik-backup-cron
  else rm -f /usr/local/sbin/atd-mikrotik-backup-cron; fi
  if [[ -f "$BACKUP/cron-helper.sudoers" ]]; then cp -p "$BACKUP/cron-helper.sudoers" /etc/sudoers.d/atd-mikrotik-backup-cron
  else rm -f /etc/sudoers.d/atd-mikrotik-backup-cron; fi
  if [[ -f "$BACKUP/cron-helper.service" ]]; then cp -p "$BACKUP/cron-helper.service" /etc/systemd/system/atd-mikrotik-backup-cron.service
  else rm -f /etc/systemd/system/atd-mikrotik-backup-cron.service; fi
  systemctl daemon-reload 2>/dev/null || true
  chown root:atdbackup "$APP/send-backup.php" "$APP/panel.css" "$APP/panel.js" 2>/dev/null || true
  chmod 0640 "$APP/send-backup.php" 2>/dev/null || true
  chmod 0644 "$APP/panel.css" "$APP/panel.js" 2>/dev/null || true
  systemctl restart atd-mikrotik-backup-php.service 2>/dev/null || true
}
# Preserve existing helper, service, and sudoers so rollback can restore them.
[[ ! -e /usr/local/sbin/atd-mikrotik-backup-cron ]] || cp -p /usr/local/sbin/atd-mikrotik-backup-cron "$BACKUP/cron-helper.sh"
[[ ! -e /etc/systemd/system/atd-mikrotik-backup-cron.service ]] || cp -p /etc/systemd/system/atd-mikrotik-backup-cron.service "$BACKUP/cron-helper.service"
[[ ! -e /etc/sudoers.d/atd-mikrotik-backup-cron ]] || cp -p /etc/sudoers.d/atd-mikrotik-backup-cron "$BACKUP/cron-helper.sudoers"
install -o root -g root -m 0750 "$TMP/cron-helper.sh" /usr/local/sbin/atd-mikrotik-backup-cron
cat > /etc/systemd/system/atd-mikrotik-backup-cron.service <<'UNIT'
[Unit]
Description=Apply ATD MikroTik Backup Studio Cron schedule
[Service]
Type=oneshot
User=root
Group=root
ExecStart=systemctl start atd-mikrotik-backup-cron.service
ProtectSystem=strict
ReadWritePaths=/etc/cron.d
PrivateTmp=true
NoNewPrivileges=true
UNIT
command -v visudo >/dev/null 2>&1 || { echo 'visudo is required to validate the ATD sudoers rule.' >&2; exit 4; }
SUDOERS_TMP=$(mktemp)
printf '%s\n' 'atdbackup ALL=(root) NOPASSWD: /usr/bin/systemctl start atd-mikrotik-backup-cron.service' > "$SUDOERS_TMP"
chmod 0440 "$SUDOERS_TMP"
if ! visudo -cf "$SUDOERS_TMP" >/dev/null; then rm -f "$SUDOERS_TMP"; echo 'ATD sudoers rule validation failed.' >&2; exit 4; fi
install -o root -g root -m 0440 "$SUDOERS_TMP" /etc/sudoers.d/atd-mikrotik-backup-cron
rm -f "$SUDOERS_TMP"
systemctl daemon-reload
install -o root -g atdbackup -m 0640 "$TMP/send-backup.php" "$APP/send-backup.php.new"
install -o root -g atdbackup -m 0644 "$TMP/panel.css" "$APP/panel.css.new"
install -o root -g atdbackup -m 0644 "$TMP/panel.js" "$APP/panel.js.new"
mv -f "$APP/send-backup.php.new" "$APP/send-backup.php"
mv -f "$APP/panel.css.new" "$APP/panel.css"
mv -f "$APP/panel.js.new" "$APP/panel.js"
chown root:atdbackup "$APP/send-backup.php"
chmod 0640 "$APP/send-backup.php"
chmod 0644 "$APP/panel.css" "$APP/panel.js"
systemctl daemon-reload
if ! php -l "$APP/send-backup.php" >/dev/null || ! systemctl restart atd-mikrotik-backup-php.service || ! systemctl is-active --quiet atd-mikrotik-backup-php.service; then
  rollback
  exit 7
fi
# Ensure cron is available without editing any existing crontabs.
if ! systemctl is-active --quiet cron.service 2>/dev/null && ! systemctl is-active --quiet crond.service 2>/dev/null; then
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y cron
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y cronie
  elif command -v yum >/dev/null 2>&1; then
    yum install -y cronie
  else
    echo 'A running cron service is required for automatic Telegram delivery.' >&2; exit 4
  fi
fi
if systemctl cat cron.service >/dev/null 2>&1; then
  systemctl enable --now cron.service
elif systemctl cat crond.service >/dev/null 2>&1; then
  systemctl enable --now crond.service
else
  echo 'Could not locate the cron service after installation.' >&2; exit 4
fi
if [[ ! -s "$STATE/telegram-scan-started-at" ]]; then
  date +%s > "$STATE/telegram-scan-started-at"
  chown atdbackup:atdbackup "$STATE/telegram-scan-started-at"
  chmod 0600 "$STATE/telegram-scan-started-at"
fi
/usr/local/sbin/atd-mikrotik-backup-cron --apply

echo "ATD application updated successfully."
echo "Private configuration preserved: $TLS/config.php"
echo "Delivery state and backups preserved: $STATE and configured backup directory."
echo "Pre-update application backup: $BACKUP"
echo "No third-party web-server configuration or firewall rules were changed."
echo "ATD Telegram Cron reapplied from saved delivery settings: /etc/cron.d/atd-mikrotik-backup-telegram."
# The Cron helper writes entries invoking --scan-backups.

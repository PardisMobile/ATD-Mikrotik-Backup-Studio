#!/usr/bin/env bash
set -Eeuo pipefail

[[ $(id -u) -eq 0 ]] || { echo 'Run with sudo: sudo atd-mikrotik-backup-update' >&2; exit 2; }
APP=/opt/atd-mikrotik-backup-studio
TLS=/etc/atd-mikrotik-backup-studio
STATE=/var/lib/atd-mikrotik-backup-studio
BASE='https://raw.githubusercontent.com/PardisMobile/ATD-Mikrotik-Backup-Studio/main/server-deployment'
for path in "$APP" "$TLS" "$STATE"; do [[ -d "$path" ]] || { echo "ATD installation not found ($path)." >&2; exit 3; }; done
[[ -s "$TLS/config.php" ]] || { echo 'Private first-run configuration is missing; update aborted.' >&2; exit 3; }
command -v curl >/dev/null 2>&1 || { echo 'curl is required; no packages were installed.' >&2; exit 4; }
command -v php >/dev/null 2>&1 || { echo 'PHP CLI is required; no packages were installed.' >&2; exit 4; }

TMP=$(mktemp -d /tmp/atd-update.XXXXXX)
chmod 0700 "$TMP"
STAMP=$(date +%Y%m%d%H%M%S)
BACKUP="$STATE/code-backup-$STAMP"
mkdir -m 0700 "$BACKUP"
cleanup(){ rm -rf -- "$TMP"; }
trap cleanup EXIT

for f in send-backup.php panel.css panel.js; do
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --max-time 60 "$BASE/$f" -o "$TMP/$f"
  [[ -s "$TMP/$f" ]] || { echo "Downloaded asset is empty: $f" >&2; exit 5; }
done
php -l "$TMP/send-backup.php" >/dev/null || { echo 'New PHP code failed syntax validation; live files were not changed.' >&2; exit 6; }
php -l "$TLS/config.php" >/dev/null || { echo 'Existing private configuration is invalid; live files were not changed.' >&2; exit 6; }
grep -q "require_once '/etc/atd-mikrotik-backup-studio/config.php';" "$TMP/send-backup.php" || { echo 'Downloaded PHP does not use the separate private configuration schema; update aborted.' >&2; exit 6; }
grep -q 'function telegram_settings()' "$TMP/send-backup.php" || { echo 'Downloaded PHP lacks panel-managed Telegram settings; update aborted.' >&2; exit 6; }
grep -q 'TELEGRAM_NOT_CONFIGURED' "$TMP/send-backup.php" || { echo 'Downloaded PHP lacks Telegram setup checks; update aborted.' >&2; exit 6; }

for f in send-backup.php panel.css panel.js; do
  [[ -f "$APP/$f" ]] && cp -p "$APP/$f" "$BACKUP/$f"
done
rollback(){
  echo 'Update failed; restoring previous ATD application files.' >&2
  for f in send-backup.php panel.css panel.js; do
    if [[ -f "$BACKUP/$f" ]]; then cp -p "$BACKUP/$f" "$APP/$f"
    else rm -f -- "$APP/$f"; fi
  done
  chown root:atdbackup "$APP/send-backup.php" "$APP/panel.css" "$APP/panel.js" 2>/dev/null || true
  chmod 0640 "$APP/send-backup.php" 2>/dev/null || true
  chmod 0644 "$APP/panel.css" "$APP/panel.js" 2>/dev/null || true
  systemctl restart atd-mikrotik-backup-php.service 2>/dev/null || true
}
install -o root -g atdbackup -m 0640 "$TMP/send-backup.php" "$APP/send-backup.php.new"
install -o root -g atdbackup -m 0644 "$TMP/panel.css" "$APP/panel.css.new"
install -o root -g atdbackup -m 0644 "$TMP/panel.js" "$APP/panel.js.new"
mv -f "$APP/send-backup.php.new" "$APP/send-backup.php"
mv -f "$APP/panel.css.new" "$APP/panel.css"
mv -f "$APP/panel.js.new" "$APP/panel.js"
chown root:atdbackup "$APP/send-backup.php"
chmod 0640 "$APP/send-backup.php"
chmod 0644 "$APP/panel.css" "$APP/panel.js"
if ! php -l "$APP/send-backup.php" >/dev/null || ! systemctl restart atd-mikrotik-backup-php.service || ! systemctl is-active --quiet atd-mikrotik-backup-php.service; then
  rollback
  exit 7
fi
echo "ATD application updated successfully."
echo "Private configuration preserved: $TLS/config.php"
echo "Delivery state and backups preserved: $STATE and configured backup directory."
echo "Pre-update application backup: $BACKUP"
echo "No other system services or firewall rules were changed."

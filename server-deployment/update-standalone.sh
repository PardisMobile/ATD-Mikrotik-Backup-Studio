#!/usr/bin/env bash
set -Eeuo pipefail

[[ $(id -u) -eq 0 ]] || { echo 'Run with sudo: sudo atd-mikrotik-backup-update' >&2; exit 2; }
APP=/opt/atd-mikrotik-backup-studio
TLS=/etc/atd-mikrotik-backup-studio
STATE=/var/lib/atd-mikrotik-backup-studio
for path in "$APP" "$TLS" "$STATE"; do [[ -d "$path" ]] || { echo "ATD installation not found ($path)." >&2; exit 3; }; done
[[ -s "$TLS/config.php" ]] || { echo 'Private first-run configuration is missing; update aborted.' >&2; exit 3; }
# Legacy ATD worker cleanup is deferred until the new assets pass validation.
command -v curl >/dev/null 2>&1 || { echo 'curl is required; no packages were installed.' >&2; exit 4; }
command -v php >/dev/null 2>&1 || { echo 'PHP CLI is required; no packages were installed.' >&2; exit 4; }

COMMIT_TMP=$(mktemp)
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --max-time 60 \
  'https://api.github.com/repos/PardisMobile/ATD-Mikrotik-Backup-Studio/commits/main' -o "$COMMIT_TMP"
COMMIT="$(sed -n 's/^[[:space:]]*"sha": "\([0-9a-f]\{40\}\)",$/\1/p' "$COMMIT_TMP" | sed -n '1p')"
rm -f -- "$COMMIT_TMP"
[[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]] || { echo 'Could not resolve immutable GitHub source commit; update aborted.' >&2; exit 5; }
BASE="https://raw.githubusercontent.com/PardisMobile/ATD-Mikrotik-Backup-Studio/$COMMIT/server-deployment"

# Serialize terminal and panel-triggered updater executions.
exec 9>"$STATE/update.lock"
flock -n 9 || { echo 'Another ATD update is already running.' >&2; exit 9; }

TMP=$(mktemp -d /tmp/atd-update.XXXXXX)
chmod 0700 "$TMP"
STAMP=$(date +%Y%m%d%H%M%S)
BACKUP="$STATE/code-backup-$STAMP"
mkdir -m 0700 "$BACKUP"
cleanup(){ rm -rf -- "$TMP"; }
trap cleanup EXIT

# Snapshot whether ATD's own backend/listener were active and enabled before
# touching code. The update must stop them during replacement and restore state.
PHP_WAS_ACTIVE=0; TLS_WAS_ACTIVE=0
PHP_WAS_ENABLED=0; TLS_WAS_ENABLED=0
systemctl is-active --quiet atd-mikrotik-backup-php.service && PHP_WAS_ACTIVE=1 || true
systemctl is-active --quiet atd-mikrotik-backup-tls.service && TLS_WAS_ACTIVE=1 || true
systemctl is-enabled --quiet atd-mikrotik-backup-php.service && PHP_WAS_ENABLED=1 || true
systemctl is-enabled --quiet atd-mikrotik-backup-tls.service && TLS_WAS_ENABLED=1 || true

for f in send-backup.php panel.css panel.js cron-helper.sh set-system-timezone.sh; do
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --max-time 60 "$BASE/$f" -o "$TMP/$f"
  [[ -s "$TMP/$f" ]] || { echo "Downloaded asset is empty: $f" >&2; exit 5; }
done
php -l "$TMP/send-backup.php" >/dev/null || { echo 'New PHP code failed syntax validation; live files were not changed.' >&2; exit 6; }
bash -n "$TMP/cron-helper.sh" || { echo 'New Cron helper failed shell syntax validation; live files were not changed.' >&2; exit 6; }
bash -n "$TMP/set-system-timezone.sh" || { echo 'New system time-zone helper failed shell syntax validation; live files were not changed.' >&2; exit 6; }
php -l "$TLS/config.php" >/dev/null || { echo 'Existing private configuration is invalid; live files were not changed.' >&2; exit 6; }
grep -q "require_once '/etc/atd-mikrotik-backup-studio/config.php';" "$TMP/send-backup.php" || { echo 'Downloaded PHP does not use the separate private configuration schema; update aborted.' >&2; exit 6; }
grep -q 'function telegram_settings()' "$TMP/send-backup.php" || { echo 'Downloaded PHP lacks panel-managed Telegram settings; update aborted.' >&2; exit 6; }
grep -q 'TELEGRAM_NOT_CONFIGURED' "$TMP/send-backup.php" || { echo 'Downloaded PHP lacks Telegram setup checks; update aborted.' >&2; exit 6; }

# Do not remove, disable, or rewrite legacy ATD unit files during an application update.
# Existing service state may be part of the user's working Telegram delivery setup.
# Migration/cleanup must be a separate, explicitly validated operation.

for f in send-backup.php panel.css panel.js; do
  [[ -f "$APP/$f" ]] && cp -p "$APP/$f" "$BACKUP/$f"
done
rollback(){
  echo 'Update failed; restoring previous ATD application files.' >&2
  # Leave existing unit files and their enabled/active state untouched.
  for f in send-backup.php panel.css panel.js; do
    if [[ -f "$BACKUP/$f" ]]; then cp -p "$BACKUP/$f" "$APP/$f"
    else rm -f -- "$APP/$f"; fi
  done
  if [[ -f "$BACKUP/cron-helper.sh" ]]; then cp -p "$BACKUP/cron-helper.sh" /usr/local/sbin/atd-mikrotik-backup-cron
  else rm -f /usr/local/sbin/atd-mikrotik-backup-cron; fi
  if [[ -f "$BACKUP/cron-apply" ]]; then cp -p "$BACKUP/cron-apply" /etc/cron.d/atd-mikrotik-backup-apply
  else rm -f /etc/cron.d/atd-mikrotik-backup-apply; fi
  chown root:atdbackup "$APP/send-backup.php" "$APP/panel.css" "$APP/panel.js" 2>/dev/null || true
  chmod 0640 "$APP/send-backup.php" 2>/dev/null || true
  chmod 0644 "$APP/panel.css" "$APP/panel.js" 2>/dev/null || true
  systemctl restart atd-mikrotik-backup-php.service 2>/dev/null || true
}
# Preserve existing helper and apply-worker Cron file so rollback can restore them.
[[ ! -e /usr/local/sbin/atd-mikrotik-backup-cron ]] || cp -p /usr/local/sbin/atd-mikrotik-backup-cron "$BACKUP/cron-helper.sh"
[[ ! -e /etc/cron.d/atd-mikrotik-backup-apply ]] || cp -p /etc/cron.d/atd-mikrotik-backup-apply "$BACKUP/cron-apply"

# Snapshot every ATD-owned file this script can replace, excluding private config
# and user data. A MISSING marker lets rollback remove only newly created files.
for path in /usr/local/sbin/atd-mikrotik-backup-cron /usr/local/sbin/atd-mikrotik-backup-set-timezone /usr/local/sbin/atd-mikrotik-backup-panel-update-worker /usr/local/sbin/atd-mikrotik-backup-panel-update /etc/cron.d/atd-mikrotik-backup-apply /etc/sudoers.d/atd-mikrotik-backup-panel-update /etc/sudoers.d/atd-panel-timezone "$STATE/installed-source-commit"; do
  if [[ -e "$path" ]]; then
    printf '%s\\n' "$path" >> "$BACKUP/snapshots.list"
    cp -a --parents "$path" "$BACKUP/"
  else
    printf 'MISSING:%s\\n' "$path" >> "$BACKUP/snapshots.list"
  fi
done

UPDATE_TRANSACTION=1
rollback(){
  echo 'Update failed; restoring previous ATD files and service state.' >&2
  for f in send-backup.php panel.css panel.js; do
    if [[ -f "$BACKUP/$f" ]]; then cp -p "$BACKUP/$f" "$APP/$f"; else rm -f -- "$APP/$f"; fi
  done
  if [[ -s "$BACKUP/snapshots.list" ]]; then
    while IFS= read -r path; do
      if [[ "$path" == MISSING:* ]]; then
        rm -f -- "${path#MISSING:}"
      else
        rel="${path#/}"
        if [[ -e "$BACKUP/$rel" ]]; then mkdir -p -- "$(dirname "$path")"; cp -a -- "$BACKUP/$rel" "$path"; fi
      fi
    done < "$BACKUP/snapshots.list"
  fi
  chown root:atdbackup "$APP/send-backup.php" "$APP/panel.css" "$APP/panel.js" 2>/dev/null || true
  chmod 0640 "$APP/send-backup.php" 2>/dev/null || true
  chmod 0644 "$APP/panel.css" "$APP/panel.js" 2>/dev/null || true
  systemctl daemon-reload 2>/dev/null || true
  if (( PHP_WAS_ENABLED )); then systemctl enable atd-mikrotik-backup-php.service 2>/dev/null || true; else systemctl disable atd-mikrotik-backup-php.service 2>/dev/null || true; fi
  if (( TLS_WAS_ENABLED )); then systemctl enable atd-mikrotik-backup-tls.service 2>/dev/null || true; else systemctl disable atd-mikrotik-backup-tls.service 2>/dev/null || true; fi
  if (( PHP_WAS_ACTIVE )); then systemctl restart atd-mikrotik-backup-php.service 2>/dev/null || true; else systemctl stop atd-mikrotik-backup-php.service 2>/dev/null || true; fi
  if (( TLS_WAS_ACTIVE )); then systemctl restart atd-mikrotik-backup-tls.service 2>/dev/null || true; else systemctl stop atd-mikrotik-backup-tls.service 2>/dev/null || true; fi
  UPDATE_TRANSACTION=0
}
trap 'if (( UPDATE_TRANSACTION )); then rollback; fi' ERR

# Stop only ATD's application services while replacing live assets.
if (( PHP_WAS_ACTIVE )); then systemctl stop atd-mikrotik-backup-php.service; fi
if (( TLS_WAS_ACTIVE )); then systemctl stop atd-mikrotik-backup-tls.service; fi
install -o root -g root -m 0750 "$TMP/cron-helper.sh" /usr/local/sbin/atd-mikrotik-backup-cron
cat > /etc/cron.d/atd-mikrotik-backup-apply <<'CRON'
* * * * * root /usr/local/sbin/atd-mikrotik-backup-cron --apply >/dev/null 2>&1
CRON
chown root:root /etc/cron.d/atd-mikrotik-backup-apply
chmod 0644 /etc/cron.d/atd-mikrotik-backup-apply
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
php -l "$APP/send-backup.php" >/dev/null
# Restart/start only services that were active before the update. Preserve an
# intentional stopped/disabled service instead of changing the host's choice.
if (( PHP_WAS_ACTIVE )); then
  systemctl start atd-mikrotik-backup-php.service
  systemctl is-active --quiet atd-mikrotik-backup-php.service
fi
if (( TLS_WAS_ACTIVE )); then
  systemctl start atd-mikrotik-backup-tls.service
  systemctl is-active --quiet atd-mikrotik-backup-tls.service
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


# Install a narrowly-scoped, root-owned launcher for panel-triggered updates.
if command -v sudo >/dev/null 2>&1 && command -v visudo >/dev/null 2>&1 && command -v systemd-run >/dev/null 2>&1 && { [[ ! -x /usr/local/sbin/atd-mikrotik-backup-panel-update-worker ]] || [[ ! -x /usr/local/sbin/atd-mikrotik-backup-panel-update ]]; }; then
  cat > /usr/local/sbin/atd-mikrotik-backup-panel-update-worker <<'ATD_WORKER'
#!/usr/bin/env bash
set +e
STATE=/var/lib/atd-mikrotik-backup-studio
/usr/local/sbin/atd-mikrotik-backup-update > "$STATE/panel-update.log" 2>&1
rc=$?
if [[ "$rc" -eq 0 ]]; then status=success; else status=failed; fi
tmp="$STATE/panel-update.status.tmp"
printf '{"status":"%s","exit_code":%s,"finished_at":"%s"}\n' "$status" "$rc" "$(date -u +%FT%TZ)" > "$tmp"
chown root:atdbackup "$tmp"; chmod 0640 "$tmp"; mv -f "$tmp" "$STATE/panel-update.status"
chown root:atdbackup "$STATE/panel-update.log"; chmod 0640 "$STATE/panel-update.log"
exit "$rc"
ATD_WORKER
  chown root:root /usr/local/sbin/atd-mikrotik-backup-panel-update-worker
  chmod 0750 /usr/local/sbin/atd-mikrotik-backup-panel-update-worker
  cat > /usr/local/sbin/atd-mikrotik-backup-panel-update <<'ATD_LAUNCHER'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$#" -eq 0 ]] || { echo 'Arguments are not accepted.' >&2; exit 2; }
STATE=/var/lib/atd-mikrotik-backup-studio
if systemctl is-active --quiet atd-mikrotik-backup-panel-update.service; then
  echo 'An update is already running.' >&2; exit 9
fi
tmp="$STATE/panel-update.status.tmp"
printf '{"status":"running","started_at":"%s"}\n' "$(date -u +%FT%TZ)" > "$tmp"
chown root:atdbackup "$tmp"; chmod 0640 "$tmp"; mv -f "$tmp" "$STATE/panel-update.status"
if ! /usr/bin/systemd-run --unit=atd-mikrotik-backup-panel-update --collect --no-block /usr/local/sbin/atd-mikrotik-backup-panel-update-worker; then
  tmp="$STATE/panel-update.status.tmp"
  printf '{"status":"failed","exit_code":1,"message":"Could not start updater."}\n' > "$tmp"
  chown root:atdbackup "$tmp"; chmod 0640 "$tmp"; mv -f "$tmp" "$STATE/panel-update.status"
  exit 1
fi
ATD_LAUNCHER
  chown root:root /usr/local/sbin/atd-mikrotik-backup-panel-update
  chmod 0750 /usr/local/sbin/atd-mikrotik-backup-panel-update
  SUDOERS_TMP=$(mktemp /etc/sudoers.d/atd-panel-update.XXXXXX)
  printf '%s\n' 'atdbackup ALL=(root) NOPASSWD: /usr/local/sbin/atd-mikrotik-backup-panel-update' > "$SUDOERS_TMP"
  chmod 0440 "$SUDOERS_TMP"
  if visudo -cf "$SUDOERS_TMP" >/dev/null; then
    install -o root -g root -m 0440 "$SUDOERS_TMP" /etc/sudoers.d/atd-mikrotik-backup-panel-update
    rm -f "$SUDOERS_TMP"
    echo 'Panel-triggered updater installed with a restricted sudo rule.'
  else
    rm -f "$SUDOERS_TMP"
    echo 'Warning: panel updater sudo rule failed validation; terminal updates remain available.' >&2
  fi
else
  echo 'Warning: sudo, visudo, or systemd-run is unavailable; panel-triggered updates are disabled.' >&2
fi

# Install the time-zone helper only after the existing application and Cron update succeeded.
install -o root -g root -m 0750 "$TMP/set-system-timezone.sh" /usr/local/sbin/atd-mikrotik-backup-set-timezone
if command -v sudo >/dev/null 2>&1 && command -v visudo >/dev/null 2>&1; then
  TIMEZONE_SUDOERS_TMP=$(mktemp /etc/sudoers.d/atd-panel-timezone.XXXXXX)
  printf '%s\n' 'atdbackup ALL=(root) NOPASSWD: /usr/local/sbin/atd-mikrotik-backup-set-timezone' > "$TIMEZONE_SUDOERS_TMP"
  chmod 0440 "$TIMEZONE_SUDOERS_TMP"
  if visudo -cf "$TIMEZONE_SUDOERS_TMP" >/dev/null; then
    install -o root -g root -m 0440 "$TIMEZONE_SUDOERS_TMP" /etc/sudoers.d/atd-panel-timezone
    rm -f "$TIMEZONE_SUDOERS_TMP"
  else
    rm -f "$TIMEZONE_SUDOERS_TMP"
    echo 'Warning: system time-zone control is disabled because its sudo rule failed validation.' >&2
  fi
else
  echo 'Warning: sudo/visudo is unavailable; system time-zone changes from the panel are disabled.' >&2
fi

# Updater self-refresh is mandatory for a successful transaction; otherwise the
# application and its installed update mechanism would report different versions.
NEXT_UPDATER=$(mktemp)
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --max-time 60 "$BASE/update-standalone.sh" -o "$NEXT_UPDATER"
bash -n "$NEXT_UPDATER"
install -o root -g root -m 0750 "$NEXT_UPDATER" /usr/local/sbin/atd-mikrotik-backup-update
rm -f -- "$NEXT_UPDATER"

printf '%s\n' "$COMMIT" > "$STATE/installed-source-commit.tmp"
chown root:atdbackup "$STATE/installed-source-commit.tmp"
chmod 0640 "$STATE/installed-source-commit.tmp"
mv -f "$STATE/installed-source-commit.tmp" "$STATE/installed-source-commit"
UPDATE_TRANSACTION=0
trap - ERR
echo "ATD application updated successfully."
echo "Private configuration preserved: $TLS/config.php"
echo "Delivery state and backups preserved: $STATE and configured backup directory."
echo "Pre-update application backup: $BACKUP"
echo "No third-party web-server configuration or firewall rules were changed."
echo "ATD Telegram Cron reapplied from saved delivery settings: /etc/cron.d/atd-mikrotik-backup-telegram."

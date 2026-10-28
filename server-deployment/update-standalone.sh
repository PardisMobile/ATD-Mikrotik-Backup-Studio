#!/usr/bin/env bash
set -Eeuo pipefail

[[ $(id -u) -eq 0 ]] || { echo 'Run with sudo: sudo atd-mikrotik-backup-update' >&2; exit 2; }
APP=/opt/atd-mikrotik-backup-studio
TLS=/etc/atd-mikrotik-backup-studio
STATE=/var/lib/atd-mikrotik-backup-studio
PHP_UNIT=/etc/systemd/system/atd-mikrotik-backup-php.service
LEGACY_PANEL_SUDOERS=/etc/sudoers.d/atd-mikrotik-backup-panel-update
SNAPSHOT_HELPER=/usr/local/sbin/atd-mikrotik-backup-snapshots
SNAPSHOT_SUDOERS=/etc/sudoers.d/atd-panel-snapshots
for path in "$APP" "$TLS" "$STATE"; do [[ -d "$path" ]] || { echo "ATD installation not found ($path)." >&2; exit 3; }; done
[[ -s "$TLS/config.php" ]] || { echo 'Private first-run configuration is missing; update aborted.' >&2; exit 3; }
command -v curl >/dev/null 2>&1 || { echo 'curl is required; no packages were installed.' >&2; exit 4; }
command -v php >/dev/null 2>&1 || { echo 'PHP CLI is required; no packages were installed.' >&2; exit 4; }
extract_commit_sha(){
  grep -oE '"sha"[[:space:]]*:[[:space:]]*"[0-9a-f]{40}"' "$1" 2>/dev/null \
    | head -n 1 | sed -E 's/.*"([0-9a-f]{40})"$/\1/' || true
}

# Bootstrap the latest updater before performing application migrations. Replacing
# the script at the end is too late: the current process would still run old
# logic and require a second invocation for newly added migration steps.
if [[ "${ATD_UPDATER_BOOTSTRAPPED:-0}" != "1" ]]; then
  BOOT_COMMIT_TMP=$(mktemp)
  BOOT_UPDATER_TMP=$(mktemp)
  trap 'rm -f -- "$BOOT_COMMIT_TMP" "$BOOT_UPDATER_TMP"' EXIT
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --max-time 60 \
    'https://api.github.com/repos/PardisMobile/ATD-Mikrotik-Backup-Studio/commits/main' -o "$BOOT_COMMIT_TMP"
  BOOT_COMMIT="$(extract_commit_sha "$BOOT_COMMIT_TMP")"
  [[ "$BOOT_COMMIT" =~ ^[0-9a-f]{40}$ ]] || { echo 'Could not resolve the latest updater source commit.' >&2; exit 5; }
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --max-time 60 \
    "https://raw.githubusercontent.com/PardisMobile/ATD-Mikrotik-Backup-Studio/$BOOT_COMMIT/server-deployment/update-standalone.sh" -o "$BOOT_UPDATER_TMP"
  [[ -s "$BOOT_UPDATER_TMP" ]] || { echo 'Latest updater download is empty; update aborted.' >&2; exit 5; }
  bash -n "$BOOT_UPDATER_TMP" || { echo 'Latest updater failed shell syntax validation.' >&2; exit 5; }
  # Always run the immutable latest updater once after fetching it. Comparing
  # against BASH_SOURCE[0] is unreliable when the command is invoked through a
  # symlink/wrapper or a different path; it can leave an old updater in control.
  # Install atomically so an interrupted copy cannot truncate the executable updater.
  BOOT_INSTALL_TMP="/usr/local/sbin/.atd-mikrotik-backup-update.$$"
  install -o root -g root -m 0750 "$BOOT_UPDATER_TMP" "$BOOT_INSTALL_TMP"
  mv -f -- "$BOOT_INSTALL_TMP" /usr/local/sbin/atd-mikrotik-backup-update
  rm -f -- "$BOOT_COMMIT_TMP" "$BOOT_UPDATER_TMP"
  trap - EXIT
  echo "Updater bootstrapped from GitHub commit $BOOT_COMMIT."
  ATD_UPDATER_BOOTSTRAPPED=1 ATD_SOURCE_COMMIT="$BOOT_COMMIT" exec /usr/local/sbin/atd-mikrotik-backup-update
fi

# Pin every downloaded asset to the exact commit whose updater was bootstrapped.
# This prevents a branch advance between bootstrap and asset download from
# mixing updater logic from one revision with application files from another.
COMMIT="${ATD_SOURCE_COMMIT:-}"
if [[ ! "$COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  COMMIT_TMP=$(mktemp)
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --max-time 60 \
    'https://api.github.com/repos/PardisMobile/ATD-Mikrotik-Backup-Studio/commits/main' -o "$COMMIT_TMP"
  COMMIT="$(extract_commit_sha "$COMMIT_TMP")"
  rm -f -- "$COMMIT_TMP"
fi
[[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]] || { echo 'Could not resolve immutable GitHub source commit; update aborted.' >&2; exit 5; }
BASE="https://raw.githubusercontent.com/PardisMobile/ATD-Mikrotik-Backup-Studio/$COMMIT/server-deployment"

# Serialize terminal updater executions.
exec 9>"$STATE/update.lock"
flock -n 9 || { echo 'Another ATD update is already running.' >&2; exit 9; }

# Cron is a host-shared scheduler. The updater may write ATD-owned Cron files,
# but it must never install, enable, start, stop, or otherwise repair the daemon.
CRON_UNIT=""
CRON_WAS_ACTIVE=0; CRON_WAS_ENABLED=0
if systemctl cat cron.service >/dev/null 2>&1; then
  CRON_UNIT=cron.service
elif systemctl cat crond.service >/dev/null 2>&1; then
  CRON_UNIT=crond.service
fi
if [[ -n "$CRON_UNIT" ]]; then
  systemctl is-active --quiet "$CRON_UNIT" && CRON_WAS_ACTIVE=1 || true
  systemctl is-enabled --quiet "$CRON_UNIT" && CRON_WAS_ENABLED=1 || true
fi
if [[ -z "$CRON_UNIT" || "$CRON_WAS_ACTIVE" -ne 1 || "$CRON_WAS_ENABLED" -ne 1 ]]; then
  echo 'HOST_CRON_NOT_READY: an existing host Cron service must already be active and enabled. ATD will not install or change this shared service.' >&2
  exit 4
fi

TMP=$(mktemp -d /tmp/atd-update.XXXXXX)
chmod 0700 "$TMP"
STAMP=$(date +%Y%m%d%H%M%S)
BACKUP="$STATE/code-backup-$STAMP"
mkdir -m 0700 "$BACKUP"
cleanup(){
  local rc=$?
  trap - EXIT
  # EXIT also runs for explicit exit statements, which do not trigger ERR.
  # Roll back any still-open transaction before removing its temporary assets.
  if (( ${UPDATE_TRANSACTION:-0} )); then rollback; fi
  rm -rf -- "$TMP"
  exit "$rc"
}
trap cleanup EXIT

# Snapshot whether ATD's own backend/listener were active and enabled before
# touching code. The update must stop them during replacement and restore state.
PHP_WAS_ACTIVE=0; TLS_WAS_ACTIVE=0
PHP_WAS_ENABLED=0; TLS_WAS_ENABLED=0
systemctl is-active --quiet atd-mikrotik-backup-php.service && PHP_WAS_ACTIVE=1 || true
systemctl is-active --quiet atd-mikrotik-backup-tls.service && TLS_WAS_ACTIVE=1 || true
systemctl is-enabled --quiet atd-mikrotik-backup-php.service && PHP_WAS_ENABLED=1 || true
systemctl is-enabled --quiet atd-mikrotik-backup-tls.service && TLS_WAS_ENABLED=1 || true

for f in send-backup.php panel.css panel.js cron-helper.sh set-system-timezone.sh manage-snapshots.sh; do
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --max-time 60 "$BASE/$f" -o "$TMP/$f"
  [[ -s "$TMP/$f" ]] || { echo "Downloaded asset is empty: $f" >&2; exit 5; }
done
php -l "$TMP/send-backup.php" >/dev/null || { echo 'New PHP code failed syntax validation; live files were not changed.' >&2; exit 6; }
bash -n "$TMP/cron-helper.sh" || { echo 'New Cron helper failed shell syntax validation; live files were not changed.' >&2; exit 6; }
bash -n "$TMP/set-system-timezone.sh" || { echo 'New system time-zone helper failed shell syntax validation; live files were not changed.' >&2; exit 6; }
bash -n "$TMP/manage-snapshots.sh" || { echo 'New snapshot helper failed shell syntax validation; live files were not changed.' >&2; exit 6; }
php -l "$TLS/config.php" >/dev/null || { echo 'Existing private configuration is invalid; live files were not changed.' >&2; exit 6; }
grep -q "require_once '/etc/atd-mikrotik-backup-studio/config.php';" "$TMP/send-backup.php" || { echo 'Downloaded PHP does not use the separate private configuration schema; update aborted.' >&2; exit 6; }
grep -q 'function telegram_settings()' "$TMP/send-backup.php" || { echo 'Downloaded PHP lacks panel-managed Telegram settings; update aborted.' >&2; exit 6; }
grep -q 'TELEGRAM_NOT_CONFIGURED' "$TMP/send-backup.php" || { echo 'Downloaded PHP lacks Telegram setup checks; update aborted.' >&2; exit 6; }

# Validate the exact ATD-owned privilege boundary before starting a transaction.
[[ -f "$PHP_UNIT" && ! -L "$PHP_UNIT" ]] || { echo 'Expected ATD PHP unit is missing or is not a regular file; update aborted.' >&2; exit 6; }
[[ "$(stat -c '%u:%g:%a' "$PHP_UNIT")" == '0:0:644' ]] || { echo 'ATD PHP unit ownership/mode is unexpected; update aborted.' >&2; exit 6; }
PHP_NNP_COUNT=$(grep -c '^NoNewPrivileges=' "$PHP_UNIT" || true)
PHP_NNP_VALUE=$(sed -n 's/^NoNewPrivileges=//p' "$PHP_UNIT")
[[ "$PHP_NNP_COUNT" -eq 1 && ( "$PHP_NNP_VALUE" == true || "$PHP_NNP_VALUE" == false ) ]] || { echo 'ATD PHP unit has an unexpected NoNewPrivileges setting; update aborted.' >&2; exit 6; }
if [[ -e "$LEGACY_PANEL_SUDOERS" ]]; then
  [[ -f "$LEGACY_PANEL_SUDOERS" && ! -L "$LEGACY_PANEL_SUDOERS" && "$(stat -c '%u:%g:%a' "$LEGACY_PANEL_SUDOERS")" == '0:0:440' ]] || { echo 'Legacy ATD panel sudoers file has unexpected ownership/mode; update aborted.' >&2; exit 6; }
  LEGACY_RULES=$(grep -Ev '^[[:space:]]*(#|$)' "$LEGACY_PANEL_SUDOERS" || true)
  [[ "$LEGACY_RULES" == 'atdbackup ALL=(root) NOPASSWD: /usr/local/sbin/atd-mikrotik-backup-panel-update' ]] || { echo 'Legacy ATD panel sudoers file contains unexpected rules; update aborted without changing it.' >&2; exit 6; }
fi
if [[ -e "$SNAPSHOT_HELPER" || -L "$SNAPSHOT_HELPER" ]]; then
  [[ -f "$SNAPSHOT_HELPER" && ! -L "$SNAPSHOT_HELPER" && "$(stat -c '%u:%g:%a' "$SNAPSHOT_HELPER")" == '0:0:750' ]] || { echo 'ATD snapshot helper ownership/mode is unexpected; update aborted.' >&2; exit 6; }
fi
if [[ -e "$SNAPSHOT_SUDOERS" || -L "$SNAPSHOT_SUDOERS" ]]; then
  [[ -f "$SNAPSHOT_SUDOERS" && ! -L "$SNAPSHOT_SUDOERS" && "$(stat -c '%u:%g:%a' "$SNAPSHOT_SUDOERS")" == '0:0:440' ]] || { echo 'ATD snapshot sudo rule ownership/mode is unexpected; update aborted.' >&2; exit 6; }
  SNAPSHOT_RULES=$(grep -Ev '^[[:space:]]*(#|$)' "$SNAPSHOT_SUDOERS" || true)
  [[ "$SNAPSHOT_RULES" == 'atdbackup ALL=(root) NOPASSWD: /usr/local/sbin/atd-mikrotik-backup-snapshots' ]] || { echo 'ATD snapshot sudo rule contains unexpected content; update aborted without changing it.' >&2; exit 6; }
fi

# No unrelated systemd service or timer is migrated, disabled, removed, or rewritten.

for f in send-backup.php panel.css panel.js; do
  [[ -f "$APP/$f" ]] && cp -p "$APP/$f" "$BACKUP/$f"
done
# Preserve existing helper and apply-worker Cron file so rollback can restore them.
[[ ! -e /usr/local/sbin/atd-mikrotik-backup-cron ]] || cp -p /usr/local/sbin/atd-mikrotik-backup-cron "$BACKUP/cron-helper.sh"
[[ ! -e /etc/cron.d/atd-mikrotik-backup-apply ]] || cp -p /etc/cron.d/atd-mikrotik-backup-apply "$BACKUP/cron-apply"

# Snapshot every ATD-owned file this script can replace, excluding private config
# and user data. A MISSING marker lets rollback remove only newly created files.
for path in /usr/local/sbin/atd-mikrotik-backup-cron /usr/local/sbin/atd-mikrotik-backup-set-timezone /usr/local/sbin/atd-mikrotik-backup-update /etc/cron.d/atd-mikrotik-backup-apply /etc/cron.d/atd-mikrotik-backup-telegram /etc/sudoers.d/atd-panel-timezone /etc/sudoers.d/atd-mikrotik-backup-panel-update "$SNAPSHOT_SUDOERS" "$SNAPSHOT_HELPER" /etc/systemd/system/atd-mikrotik-backup-php.service "$STATE/installed-source-commit" "$STATE/telegram-scan-started-at"; do
  if [[ -e "$path" ]]; then
    printf '%s\n' "$path" >> "$BACKUP/snapshots.list"
    cp -a --parents "$path" "$BACKUP/"
  else
    printf 'MISSING:%s\n' "$path" >> "$BACKUP/snapshots.list"
  fi
done

UPDATE_TRANSACTION=1
PHP_UNIT_CHANGED=0
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
  if (( PHP_UNIT_CHANGED )); then systemctl daemon-reload 2>/dev/null || true; fi
  if (( PHP_WAS_ENABLED )); then systemctl enable atd-mikrotik-backup-php.service 2>/dev/null || true; else systemctl disable atd-mikrotik-backup-php.service 2>/dev/null || true; fi
  if (( TLS_WAS_ENABLED )); then systemctl enable atd-mikrotik-backup-tls.service 2>/dev/null || true; else systemctl disable atd-mikrotik-backup-tls.service 2>/dev/null || true; fi
  if (( PHP_WAS_ACTIVE )); then systemctl restart atd-mikrotik-backup-php.service 2>/dev/null || true; else systemctl stop atd-mikrotik-backup-php.service 2>/dev/null || true; fi
  if (( TLS_WAS_ACTIVE )); then systemctl restart atd-mikrotik-backup-tls.service 2>/dev/null || true; else systemctl stop atd-mikrotik-backup-tls.service 2>/dev/null || true; fi
  # Verify restoration rather than silently treating best-effort commands as success.
  local rollback_failed=0
  for f in send-backup.php panel.css panel.js; do
    if [[ -f "$BACKUP/$f" ]]; then
      cmp -s -- "$BACKUP/$f" "$APP/$f" || { echo "Rollback verification failed: $APP/$f" >&2; rollback_failed=1; }
    elif [[ -e "$APP/$f" ]]; then
      echo "Rollback verification failed: unexpected file $APP/$f" >&2
      rollback_failed=1
    fi
  done
  if [[ -s "$BACKUP/snapshots.list" ]]; then
    while IFS= read -r path; do
      if [[ "$path" == MISSING:* ]]; then
        [[ ! -e "${path#MISSING:}" ]] || { echo "Rollback verification failed: unexpected path ${path#MISSING:}" >&2; rollback_failed=1; }
      else
        rel="${path#/}"
        if [[ ! -e "$BACKUP/$rel" ]] || ! cmp -s -- "$BACKUP/$rel" "$path"; then
          echo "Rollback verification failed: $path" >&2
          rollback_failed=1
        fi
      fi
    done < "$BACKUP/snapshots.list"
  fi
  if [[ -n "$CRON_UNIT" ]]; then
    current_active=0; current_enabled=0
    systemctl is-active --quiet "$CRON_UNIT" && current_active=1 || true
    systemctl is-enabled --quiet "$CRON_UNIT" && current_enabled=1 || true
    (( current_active == CRON_WAS_ACTIVE && current_enabled == CRON_WAS_ENABLED )) || { echo "Rollback verification failed: shared host Cron state changed during the update." >&2; rollback_failed=1; }
  fi
  if (( rollback_failed )); then
    echo "CRITICAL: rollback was incomplete. Review the pre-update snapshot at $BACKUP and systemd state before retrying." >&2
  else
    echo "Rollback verification passed: saved files and captured service states were restored." >&2
  fi
  UPDATE_TRANSACTION=0
}
trap 'if (( UPDATE_TRANSACTION )); then rollback; fi' ERR

# Install the time-zone helper and its restricted sudo policy at the start of the
# transaction. The panel must not temporarily lose this control while an update
# is in progress; the transaction snapshot/rollback already covers both paths.
install -o root -g root -m 0750 "$TMP/set-system-timezone.sh" /usr/local/sbin/atd-mikrotik-backup-set-timezone
[[ -x /usr/local/sbin/atd-mikrotik-backup-set-timezone ]] || { echo 'Time-zone helper installation failed; update aborted.' >&2; exit 7; }
command -v sudo >/dev/null 2>&1 && command -v visudo >/dev/null 2>&1 || { echo 'sudo and visudo are required to install the restricted time-zone control rule; update aborted.' >&2; exit 7; }
TIMEZONE_SUDOERS_TMP=$(mktemp /etc/sudoers.d/atd-panel-timezone.XXXXXX)
printf '%s\n' 'atdbackup ALL=(root) NOPASSWD: /usr/local/sbin/atd-mikrotik-backup-set-timezone' > "$TIMEZONE_SUDOERS_TMP"
chmod 0440 "$TIMEZONE_SUDOERS_TMP"
if visudo -cf "$TIMEZONE_SUDOERS_TMP" >/dev/null; then
  install -o root -g root -m 0440 "$TIMEZONE_SUDOERS_TMP" /etc/sudoers.d/atd-panel-timezone
  rm -f "$TIMEZONE_SUDOERS_TMP"
else
  rm -f "$TIMEZONE_SUDOERS_TMP"
  echo 'Restricted time-zone sudo rule failed validation; update aborted.' >&2
  exit 7
fi
visudo -cf /etc/sudoers.d/atd-panel-timezone >/dev/null || { echo 'Installed time-zone sudo rule failed validation; update aborted.' >&2; exit 7; }
TIMEZONE_SUDOERS_META="$(stat -c '%u:%g:%a' /etc/sudoers.d/atd-panel-timezone 2>/dev/null || true)"
[[ "$TIMEZONE_SUDOERS_META" == '0:0:440' ]] || { echo "Time-zone sudo rule ownership/permissions are invalid (expected root:root 0440; got ${TIMEZONE_SUDOERS_META:-unavailable}); update aborted." >&2; exit 7; }
install -o root -g root -m 0750 "$TMP/manage-snapshots.sh" "$SNAPSHOT_HELPER"
[[ -x "$SNAPSHOT_HELPER" ]] || { echo 'ATD snapshot helper installation failed; update aborted.' >&2; exit 7; }
command -v runuser >/dev/null 2>&1 || { echo 'runuser is required to validate the ATD snapshot sudo rule; update aborted.' >&2; exit 7; }
SNAPSHOT_SUDOERS_TMP=$(mktemp /etc/sudoers.d/atd-panel-snapshots.XXXXXX)
printf '%s\n' 'atdbackup ALL=(root) NOPASSWD: /usr/local/sbin/atd-mikrotik-backup-snapshots' > "$SNAPSHOT_SUDOERS_TMP"
chmod 0440 "$SNAPSHOT_SUDOERS_TMP"
visudo -cf "$SNAPSHOT_SUDOERS_TMP" >/dev/null || { rm -f "$SNAPSHOT_SUDOERS_TMP"; echo 'ATD snapshot sudo rule failed validation; update aborted.' >&2; exit 7; }
install -o root -g root -m 0440 "$SNAPSHOT_SUDOERS_TMP" "$SNAPSHOT_SUDOERS"
rm -f "$SNAPSHOT_SUDOERS_TMP"
visudo -cf "$SNAPSHOT_SUDOERS" >/dev/null || { echo 'Installed ATD snapshot sudo rule is invalid; update aborted.' >&2; exit 7; }
[[ "$(stat -c '%u:%g:%a' "$SNAPSHOT_SUDOERS")" == '0:0:440' ]] || { echo 'ATD snapshot sudo rule permissions are invalid; update aborted.' >&2; exit 7; }
runuser -u atdbackup -- /usr/bin/sudo -n -l "$SNAPSHOT_HELPER" >/dev/null 2>&1 || { echo 'ATD PHP user is not allowed to use the snapshot helper; update aborted.' >&2; exit 7; }

# Retire only the known legacy ATD panel-update sudo rule, preserving its file
# but removing permission to launch the obsolete background updater. The PHP
# service is then allowed to use the single restricted timezone sudo command.
if [[ -e "$LEGACY_PANEL_SUDOERS" ]]; then
  command -v runuser >/dev/null 2>&1 || { echo 'runuser is required to verify the retired panel-update sudo rule; update aborted.' >&2; exit 7; }
  LEGACY_RULE_TMP=$(mktemp /etc/sudoers.d/atd-mikrotik-backup-panel-update.XXXXXX)
  printf '%s\n' 'atdbackup ALL=(root) NOPASSWD: /usr/local/sbin/atd-mikrotik-backup-set-timezone' > "$LEGACY_RULE_TMP"
  chmod 0440 "$LEGACY_RULE_TMP"
  visudo -cf "$LEGACY_RULE_TMP" >/dev/null || { rm -f "$LEGACY_RULE_TMP"; echo 'Replacement legacy ATD sudo rule failed validation; update aborted.' >&2; exit 7; }
  install -o root -g root -m 0440 "$LEGACY_RULE_TMP" "$LEGACY_PANEL_SUDOERS"
  rm -f "$LEGACY_RULE_TMP"
  visudo -cf "$LEGACY_PANEL_SUDOERS" >/dev/null || { echo 'Updated legacy ATD sudoers file failed validation; update aborted.' >&2; exit 7; }
fi

if [[ "$PHP_NNP_VALUE" == true ]]; then
  PHP_UNIT_TMP=$(mktemp /etc/systemd/system/.atd-mikrotik-backup-php.service.XXXXXX)
  sed 's/^NoNewPrivileges=true$/NoNewPrivileges=false/' "$PHP_UNIT" > "$PHP_UNIT_TMP"
  grep -q '^NoNewPrivileges=false$' "$PHP_UNIT_TMP" || { rm -f "$PHP_UNIT_TMP"; echo 'Could not prepare the ATD PHP privilege boundary update.' >&2; exit 7; }
  install -o root -g root -m 0644 "$PHP_UNIT_TMP" "$PHP_UNIT"
  rm -f "$PHP_UNIT_TMP"
  PHP_UNIT_CHANGED=1
  systemctl daemon-reload
fi

# Stop only ATD's web services while replacing ATD-owned app files. Existing
# systemd services and timers outside this update's scope remain untouched.
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
php -l "$APP/send-backup.php" >/dev/null
# Restart/start only services that were active before the update. Preserve an
# intentional stopped/disabled service instead of changing the host's choice.
if (( PHP_WAS_ACTIVE )); then
  systemctl start atd-mikrotik-backup-php.service
  systemctl is-active --quiet atd-mikrotik-backup-php.service
  [[ "$(systemctl show -p NoNewPrivileges --value atd-mikrotik-backup-php.service)" == no ]] || { echo 'ATD PHP service privilege setting was not applied; update aborted.' >&2; exit 7; }
fi
if (( TLS_WAS_ACTIVE )); then
  systemctl start atd-mikrotik-backup-tls.service
  systemctl is-active --quiet atd-mikrotik-backup-tls.service
fi
systemctl is-active --quiet "$CRON_UNIT" && systemctl is-enabled --quiet "$CRON_UNIT" || { echo 'HOST_CRON_NOT_READY: host Cron became inactive or disabled during update; aborting.' >&2; exit 4; }
if [[ ! -s "$STATE/telegram-scan-started-at" ]]; then
  date +%s > "$STATE/telegram-scan-started-at"
  chown atdbackup:atdbackup "$STATE/telegram-scan-started-at"
  chmod 0600 "$STATE/telegram-scan-started-at"
fi
/usr/local/sbin/atd-mikrotik-backup-cron --apply


# Panel updates are terminal-only; do not create background Worker launchers.

# The updater was bootstrapped to the immutable source snapshot before migration.

printf '%s\n' "$COMMIT" > "$STATE/installed-source-commit.tmp"
chown root:atdbackup "$STATE/installed-source-commit.tmp"
chmod 0640 "$STATE/installed-source-commit.tmp"
mv -f "$STATE/installed-source-commit.tmp" "$STATE/installed-source-commit"
# Verify the exact postconditions that the panel's update and timezone checks read.
[[ -s "$STATE/installed-source-commit" ]] || { echo 'Installed source commit marker was not written; update aborted.' >&2; exit 7; }
[[ "$(cat "$STATE/installed-source-commit")" == "$COMMIT" ]] || { echo 'Installed source commit marker does not match this update; update aborted.' >&2; exit 7; }
[[ -x /usr/local/sbin/atd-mikrotik-backup-cron ]] || { echo 'Installed Cron helper is missing; update aborted.' >&2; exit 7; }
[[ -f /etc/cron.d/atd-mikrotik-backup-apply && -f /etc/cron.d/atd-mikrotik-backup-telegram ]] || { echo 'Installed ATD Cron entries are incomplete; update aborted.' >&2; exit 7; }
[[ -x /usr/local/sbin/atd-mikrotik-backup-set-timezone ]] || { echo 'Installed time-zone helper is missing; update aborted.' >&2; exit 7; }
[[ -x "$SNAPSHOT_HELPER" ]] || { echo 'Installed ATD snapshot helper is missing; update aborted.' >&2; exit 7; }
[[ -f "$SNAPSHOT_SUDOERS" && "$(stat -c '%u:%g:%a' "$SNAPSHOT_SUDOERS")" == '0:0:440' ]] || { echo 'Installed ATD snapshot sudo rule is missing or has invalid permissions; update aborted.' >&2; exit 7; }
visudo -cf "$SNAPSHOT_SUDOERS" >/dev/null || { echo 'Installed ATD snapshot sudo rule is invalid; update aborted.' >&2; exit 7; }
runuser -u atdbackup -- /usr/bin/sudo -n -l "$SNAPSHOT_HELPER" >/dev/null 2>&1 || { echo 'ATD PHP user cannot access the installed snapshot helper; update aborted.' >&2; exit 7; }
[[ "$(grep -c '^NoNewPrivileges=false$' "$PHP_UNIT")" -eq 1 ]] || { echo 'ATD PHP service must permit the restricted timezone sudo call; update aborted.' >&2; exit 7; }
if [[ -e "$LEGACY_PANEL_SUDOERS" ]] && runuser -u atdbackup -- /usr/bin/sudo -n -l /usr/local/sbin/atd-mikrotik-backup-panel-update >/dev/null 2>&1; then
  echo 'Obsolete panel-update sudo permission is still active; update aborted.' >&2
  exit 7
fi
[[ -f /etc/sudoers.d/atd-panel-timezone ]] || { echo 'Installed time-zone sudo rule is missing; update aborted.' >&2; exit 7; }
visudo -cf /etc/sudoers.d/atd-panel-timezone >/dev/null || { echo 'Installed time-zone sudo rule is invalid; update aborted.' >&2; exit 7; }
UPDATE_TRANSACTION=0
trap - ERR

# Keep two newest successful rollback points and successful snapshots from the
# last seven days. Legacy or unverified snapshots are always kept for review.
prune_successful_snapshots(){
  local cutoff index=0 modified path
  local -a rows=()
  cutoff=$(($(date +%s) - 7 * 86400))
  while IFS= read -r path; do
    [[ -d "$path" && ! -L "$path" && -f "$path/update-success" && ! -L "$path/update-success" ]] || continue
    [[ "$(stat -c '%u:%g' "$path" 2>/dev/null)" == '0:0' ]] || continue
    grep -qx 'status=success' "$path/update-success" || continue
    rows+=("$(stat -c '%Y' "$path/update-success")"$'\t'"$path")
  done < <(printf '%s\n' "$STATE"/code-backup-*)
  while IFS=$'\t' read -r modified path; do
    [[ -n "$path" ]] || continue
    ((index += 1))
    if (( index > 2 && modified < cutoff )); then
      rm -rf -- "$path" || echo "Could not prune old ATD snapshot: $path" >&2
    fi
  done < <(printf '%s\n' "${rows[@]}" | sort -rn -k1,1)
}
if printf 'status=success\ncommit=%s\ncompleted_at=%s\n' "$COMMIT" "$(date +%s)" > "$BACKUP/update-success" && chmod 0600 "$BACKUP/update-success"; then
  prune_successful_snapshots || echo 'Warning: automatic ATD snapshot retention did not finish.' >&2
else
  echo 'Warning: update succeeded but the snapshot success marker could not be written.' >&2
fi

echo "ATD application updated successfully."
echo "Private configuration preserved: $TLS/config.php"
echo "Delivery state and backups preserved: $STATE and configured backup directory."
echo "Pre-update application backup: $BACKUP"
echo "No third-party web-server configuration or firewall rules were changed."
echo "ATD Telegram Cron reapplied from saved delivery settings: /etc/cron.d/atd-mikrotik-backup-telegram."
# The installed Cron helper writes the dedicated scan job invoking --scan-backups.

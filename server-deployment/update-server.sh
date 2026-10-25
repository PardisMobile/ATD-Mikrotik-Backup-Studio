#!/usr/bin/env bash
set -Eeuo pipefail
# Safe updater for an existing ATD MikroTik Backup Studio installation.
# Usage: sudo bash update-server.sh /absolute/path/to/installed/panel
OWNER_REPO="PardisMobile/ATD-Mikrotik-Backup-Studio"
BRANCH="main"
TARGET="${1:-}"
[[ -n "$TARGET" && "$TARGET" == /* && -d "$TARGET" ]] || { echo "Usage: sudo bash update-server.sh /absolute/path/to/installed/panel" >&2; exit 2; }
[[ -f "$TARGET/send-backup.php" && -f "$TARGET/panel.css" && -f "$TARGET/panel.js" ]] || { echo "Target does not look like an installed ATD panel." >&2; exit 3; }
command -v curl >/dev/null || { echo "curl is required." >&2; exit 4; }
command -v php >/dev/null || { echo "PHP CLI is required to preserve configuration and validate PHP." >&2; exit 5; }
php -r 'exit(PHP_VERSION_ID >= 70400 ? 0 : 1);' || { echo "PHP 7.4+ required." >&2; exit 6; }

BASE="https://raw.githubusercontent.com/$OWNER_REPO/$BRANCH/server-deployment"
STAMP="$(date +%Y%m%d%H%M%S)"
WORK="$(mktemp -d)"
BACKUP="$TARGET/.atd-update-backup-$STAMP"
cleanup(){ rm -rf -- "$WORK"; }
trap cleanup EXIT
mkdir -m 0700 "$BACKUP"
FILES=(send-backup.php panel.css panel.js)
for f in "${FILES[@]}"; do
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --max-time 60 "$BASE/$f" -o "$WORK/$f"
  [[ -s "$WORK/$f" ]] || { echo "Downloaded empty file: $f" >&2; exit 10; }
done
php -l "$WORK/send-backup.php" >/dev/null || { echo "Downloaded PHP failed syntax validation; current version unchanged." >&2; exit 11; }

# Preserve customer-specific constants from the currently installed PHP.
# Only string constants that exist in both versions are carried forward.
php -r '
$old=file_get_contents($argv[1]); $new=file_get_contents($argv[2]);
$names=["ATD_RELAY_TOKEN","ATD_TELEGRAM_BOT_TOKEN","ATD_TELEGRAM_CHAT_ID","ATD_PANEL_PASSWORD_HASH","ATD_BACKUP_DIR","ATD_STATE_FILE"];
foreach($names as $name){
  $pattern="/const\\s+".preg_quote($name,"/")."\\s*=\\s*(\x27(?:\\\\.|[^\x27])*\x27|\x22(?:\\\\.|[^\x22])*\x22)\\s*;/s";
  if(preg_match($pattern,$old,$m) && preg_match($pattern,$new)){
    $new=preg_replace($pattern,"const ".$name." = ".$m[1].";",$new,1);
  }
}
file_put_contents($argv[2],$new);
' "$TARGET/send-backup.php" "$WORK/send-backup.php"
php -l "$WORK/send-backup.php" >/dev/null || { echo "Preserved configuration failed syntax validation; current version unchanged." >&2; exit 12; }

# Save exact prior files before replacing any live file.
for f in "${FILES[@]}"; do cp -p -- "$TARGET/$f" "$BACKUP/$f"; done
rollback(){ for f in "${FILES[@]}"; do cp -p -- "$BACKUP/$f" "$TARGET/$f" || true; done; echo "Update failed; previous files restored from $BACKUP" >&2; }
for f in "${FILES[@]}"; do
  install -m "$(stat -c '%a' "$TARGET/$f")" "$WORK/$f" "$TARGET/.$f.atd-new"
done
for f in "${FILES[@]}"; do mv -f -- "$TARGET/.$f.atd-new" "$TARGET/$f" || { rollback; exit 13; }; done
php -l "$TARGET/send-backup.php" >/dev/null || { rollback; exit 14; }
echo "Update completed. Customer configuration constants were carried forward where names matched."
echo "Backup of previous files: $BACKUP"
echo "Review panel behavior and run Telegram/SFTP smoke tests before production use."

#!/usr/bin/env bash
set -Eeuo pipefail
# Installs into an existing website subdirectory. It never edits global vhost config or opens ports.
# Usage: sudo bash install-server.sh /absolute/existing-webroot/atd-backup
TARGET="${1:-}"
[[ -n "$TARGET" && "$TARGET" == /* ]] || { echo "Usage: sudo bash install-server.sh /absolute/existing-webroot/atd-backup" >&2; exit 2; }
PARENT="$(dirname "$TARGET")"
[[ -d "$PARENT" ]] || { echo "Parent path must already exist and be inside your existing HTTPS document root." >&2; exit 3; }
[[ ! -e "$TARGET" || -d "$TARGET" ]] || { echo "Target exists and is not a directory." >&2; exit 4; }
SRC="$(cd "$(dirname "$0")" && pwd)"
for f in send-backup.php panel.css panel.js; do [[ -f "$SRC/$f" ]] || { echo "Missing $SRC/$f. Download the complete repository first." >&2; exit 5; }; done
command -v php >/dev/null || { echo "PHP CLI is required." >&2; exit 6; }
php -r 'exit(extension_loaded("curl")?0:1);' || { echo "Enable PHP cURL first." >&2; exit 7; }
# Do not overwrite without backup.
mkdir -p -- "$TARGET"
for f in send-backup.php panel.css panel.js; do
  if [[ -e "$TARGET/$f" ]]; then cp -p -- "$TARGET/$f" "$TARGET/$f.backup.$(date +%Y%m%d%H%M%S)"; fi
  install -m 0644 "$SRC/$f" "$TARGET/$f"
done
WEBUSER=""
for u in www-data nginx apache; do if id "$u" >/dev/null 2>&1; then WEBUSER="$u"; break; fi; done
if [[ -z "$WEBUSER" ]]; then echo "Cannot detect web worker. Files copied, but do not use until PHP-FPM user and permissions are configured." >&2; exit 8; fi
install -d -o "$WEBUSER" -g "$WEBUSER" -m 0700 /var/lib/atd-mikrotik-backup-studio
chown root:"$WEBUSER" "$TARGET/send-backup.php"
chmod 0640 "$TARGET/send-backup.php"
chmod 0644 "$TARGET/panel.css" "$TARGET/panel.js"
echo "Panel files installed at $TARGET."
echo "IMPORTANT: edit send-backup.php configuration placeholders before use; store real secrets only on the server."
echo "State path is /var/lib/atd-mikrotik-backup-studio/state.json; ensure the web worker can write there."
echo "No ports or global Nginx/Apache configuration were changed."

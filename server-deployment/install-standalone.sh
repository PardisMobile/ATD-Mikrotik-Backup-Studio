#!/usr/bin/env bash
set -Eeuo pipefail
# Standalone ATD panel runtime. Run as root with the generated package directory as argument.
[[ $(id -u) -eq 0 ]] || { echo 'Run with sudo.' >&2; exit 2; }
SRC=${1:-$(pwd)}
for f in send-backup.php panel.css panel.js; do [[ -f "$SRC/$f" ]] || { echo "Missing $f in $SRC" >&2; exit 3; }; done
BACKUP_DIR=$(sed -n "s/^const BACKUP_DIR = '\\(.*\\)';$/\\1/p" "$SRC/send-backup.php" | head -n1)
[[ "$BACKUP_DIR" == /* && "$BACKUP_DIR" != / && "$BACKUP_DIR" != /root && "$BACKUP_DIR" != /home && "$BACKUP_DIR" != /etc && "$BACKUP_DIR" != /var && "$BACKUP_DIR" != /usr && "$BACKUP_DIR" != /opt && "$BACKUP_DIR" != /tmp ]] || { echo 'Missing or unsafe BACKUP_DIR in generated PHP.' >&2; exit 4; }
case "$BACKUP_DIR" in *"/../"*|*/..) echo 'Unsafe backup path.' >&2; exit 4;; esac

# Define an explicit baseline for Ubuntu deployments instead of silently implying every release is supported.
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  if [[ "${ID:-}" == ubuntu ]]; then
    ver="${VERSION_ID:-0}"
    if [[ ! "$ver" =~ ^[0-9]+\.[0-9]+$ ]] || [[ "$(printf '%s\\n' 22.04 "$ver" | sort -V | head -n1)" != "22.04" ]]; then
      echo "Ubuntu $ver is not supported by this installer. Use Ubuntu 22.04 LTS or newer." >&2; exit 5
    fi
  fi
fi

# Detect the current server before installing anything. Existing web services are left untouched.
if systemctl is-active --quiet nginx 2>/dev/null; then echo 'Detected Nginx; ATD will use its own port and will not edit Nginx.'; fi
if systemctl is-active --quiet apache2 2>/dev/null || systemctl is-active --quiet httpd 2>/dev/null; then echo 'Detected Apache; ATD will use its own port and will not edit Apache.'; fi
if systemctl is-active --quiet x-ui 2>/dev/null || systemctl is-active --quiet 3x-ui 2>/dev/null; then echo 'Detected an XUI service; its configuration will not be changed.'; fi
if systemctl is-active --quiet atd-mikrotik-backup-php.service 2>/dev/null; then echo 'Existing ATD installation detected; keeping its panel configuration and assigned ports.'; fi

# Install only when required tools/extensions are missing.
NEED_PACKAGES=0
command -v php >/dev/null 2>&1 || NEED_PACKAGES=1
php -r 'exit(extension_loaded("curl") ? 0 : 1);' 2>/dev/null || NEED_PACKAGES=1
for cmd in openssl socat setfacl python3; do command -v "$cmd" >/dev/null 2>&1 || NEED_PACKAGES=1; done
if [[ "$NEED_PACKAGES" -eq 1 ]]; then
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y php-cli php-curl openssl socat acl python3
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y php-cli php-common php-curl openssl socat acl python3
  elif command -v yum >/dev/null 2>&1; then
    yum install -y php php-cli php-common php-curl openssl socat acl python3
  else echo 'Supported package managers: apt, dnf, yum.' >&2; exit 5; fi
else
  echo 'All required packages are already installed; skipping package installation.'
fi
command -v php >/dev/null 2>&1 || { echo 'PHP CLI installation failed.' >&2; exit 6; }
php -r 'exit(extension_loaded("curl") ? 0 : 1);' || { echo 'PHP cURL is required.' >&2; exit 6; }

id atdbackup >/dev/null 2>&1 || useradd --system --home-dir /opt/atd-mikrotik-backup-studio --shell /usr/sbin/nologin atdbackup
APP=/opt/atd-mikrotik-backup-studio; STATE=/var/lib/atd-mikrotik-backup-studio; TLS=/etc/atd-mikrotik-backup-studio
mkdir -p "$APP" "$STATE" "$TLS" "$BACKUP_DIR"; chmod 0750 "$APP"; chmod 0700 "$STATE" "$TLS"; chown atdbackup:atdbackup "$STATE"
for f in send-backup.php panel.css panel.js; do
  if [[ -e "$APP/$f" ]]; then cp -p "$APP/$f" "$APP/$f.backup.$(date +%Y%m%d%H%M%S)"; fi
  # Keep customer-specific PHP credentials/state on re-runs; update static assets normally.
  if [[ "$f" != send-backup.php || ! -e "$APP/send-backup.php" ]]; then install -m 0640 "$SRC/$f" "$APP/$f"; fi
done
chown -R root:atdbackup "$APP"; chmod 0640 "$APP/send-backup.php"; chmod 0644 "$APP/panel.css" "$APP/panel.js"
php -l "$APP/send-backup.php" || { echo 'PHP syntax check failed; services were not restarted.' >&2; exit 8; }

setfacl -m u:atdbackup:rwx "$BACKUP_DIR"; setfacl -d -m u:atdbackup:rw- "$BACKUP_DIR"
find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.backup' -exec setfacl -m u:atdbackup:rw- {} +
if [[ "$BACKUP_DIR" == /root/* ]]; then setfacl -m u:atdbackup:--x /root; fi

freeport(){ python3 - "$1" "$2" <<'PY'
import socket,sys,random
lo,hi=map(int,sys.argv[1:]); p=list(range(lo,hi+1)); random.SystemRandom().shuffle(p)
for n in p:
 s=socket.socket()
 try: s.bind(('0.0.0.0' if lo>19999 else '127.0.0.1',n))
 except OSError: s.close(); continue
 s.close(); print(n); break
PY
}
# Preserve allocated ports on repeat runs. Avoid breaking a running deployment with a new URL.
if [[ -s "$TLS/ports.env" ]] && grep -Eq '^PUBLIC_PORT=[0-9]+$' "$TLS/ports.env" && grep -Eq '^BACKEND_PORT=[0-9]+$' "$TLS/ports.env"; then
  # shellcheck disable=SC1090
  source "$TLS/ports.env"
else
  PUBLIC_PORT=$(freeport 20000 60000); BACKEND_PORT=$(freeport 2000 19999)
  [[ -n "$PUBLIC_PORT" && -n "$BACKEND_PORT" ]] || { echo 'No free port found.' >&2; exit 7; }
  printf 'PUBLIC_PORT=%s\nBACKEND_PORT=%s\n' "$PUBLIC_PORT" "$BACKEND_PORT" > "$TLS/ports.env"
  chmod 0600 "$TLS/ports.env"
fi
[[ "$PUBLIC_PORT" =~ ^[0-9]+$ && "$PUBLIC_PORT" -ge 20000 && "$PUBLIC_PORT" -le 60000 && "$BACKEND_PORT" =~ ^[0-9]+$ && "$BACKEND_PORT" -ge 2000 && "$BACKEND_PORT" -le 19999 ]] || { echo 'Invalid stored port configuration.' >&2; exit 7; }
IP=$(hostname -I 2>/dev/null | awk '{print $1}'); [[ -n "$IP" ]] || IP=127.0.0.1
if [[ ! -s "$TLS/server.crt" || ! -s "$TLS/server.key" ]]; then
  openssl req -x509 -nodes -newkey rsa:2048 -sha256 -days 825 -keyout "$TLS/server.key" -out "$TLS/server.crt" -subj "/CN=$IP" -addext "subjectAltName=IP:$IP" >/dev/null 2>&1
  chmod 0600 "$TLS/server.key"; chmod 0644 "$TLS/server.crt"
fi
cat > /etc/systemd/system/atd-mikrotik-backup-php.service <<EOF
[Unit]
Description=ATD MikroTik Backup Studio PHP backend
After=network.target
[Service]
User=atdbackup
Group=atdbackup
WorkingDirectory=/opt/atd-mikrotik-backup-studio
ExecStart=/usr/bin/php -d session.cookie_secure=1 -d expose_php=0 -S 127.0.0.1:$BACKEND_PORT -t /opt/atd-mikrotik-backup-studio
Restart=on-failure
RestartSec=3
ProtectSystem=strict
PrivateTmp=true
NoNewPrivileges=true
ReadWritePaths=/var/lib/atd-mikrotik-backup-studio $BACKUP_DIR
[Install]
WantedBy=multi-user.target
EOF
cat > /etc/systemd/system/atd-mikrotik-backup-tls.service <<EOF
[Unit]
Description=ATD MikroTik Backup Studio TLS endpoint
After=network.target atd-mikrotik-backup-php.service
Requires=atd-mikrotik-backup-php.service
[Service]
EnvironmentFile=$TLS/ports.env
ExecStart=/usr/bin/socat OPENSSL-LISTEN:$PUBLIC_PORT,bind=0.0.0.0,reuseaddr,fork,cert=$TLS/server.crt,key=$TLS/server.key,verify=0 TCP:127.0.0.1:$BACKEND_PORT
Restart=on-failure
RestartSec=3
ProtectSystem=strict
PrivateTmp=true
NoNewPrivileges=true
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now atd-mikrotik-backup-php.service atd-mikrotik-backup-tls.service
systemctl is-active --quiet atd-mikrotik-backup-php.service
systemctl is-active --quiet atd-mikrotik-backup-tls.service

FW='No common active firewall manager detected; no firewall rule changed.'
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi 'Status: active'; then
  ufw allow "$PUBLIC_PORT/tcp" comment 'ATD MikroTik Backup Studio' >/dev/null; FW="UFW opened TCP $PUBLIC_PORT."
elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port="$PUBLIC_PORT/tcp" >/dev/null; firewall-cmd --reload >/dev/null; FW="firewalld opened TCP $PUBLIC_PORT."
elif command -v iptables >/dev/null 2>&1 && iptables -S INPUT >/dev/null 2>&1; then
  iptables -C INPUT -p tcp --dport "$PUBLIC_PORT" -m comment --comment ATD-MikroTik-Backup-Studio -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport "$PUBLIC_PORT" -m comment --comment ATD-MikroTik-Backup-Studio -j ACCEPT
  command -v netfilter-persistent >/dev/null 2>&1 && netfilter-persistent save >/dev/null 2>&1 || true
  FW="iptables added TCP $PUBLIC_PORT rule at end of INPUT chain; earlier rules may still block it."
fi

echo; echo 'ATD MikroTik Backup Studio installed.'
echo "URL: https://$IP:$PUBLIC_PORT/"
echo 'Certificate: self-signed; browser warning expected, TLS traffic is encrypted.'
echo "Firewall: $FW"
echo "Backup directory: $BACKUP_DIR"
echo 'Existing web-server configurations and ports were not changed.'

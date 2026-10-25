#!/usr/bin/env bash
set -Eeuo pipefail

# Remove only ATD MikroTik Backup Studio components. Never remove the user's
# RouterOS backup directory or alter third-party web servers/firewall rules.
[[ $(id -u) -eq 0 ]] || { echo 'Run as root: sudo bash uninstall-standalone.sh' >&2; exit 2; }

APP=/opt/atd-mikrotik-backup-studio
TLS=/etc/atd-mikrotik-backup-studio
STATE=/var/lib/atd-mikrotik-backup-studio
UNITS=(
  atd-mikrotik-backup-php.service
  atd-mikrotik-backup-tls.service
  atd-mikrotik-backup-telegram-scan.service
  atd-mikrotik-backup-telegram-scan.timer
  atd-mikrotik-backup-telegram-worker.service
  atd-mikrotik-backup-telegram-worker.timer
  atd-mikrotik-backup-worker.service
  atd-mikrotik-backup-worker.timer
  atd-mikrotik-backup-scanner.service
  atd-mikrotik-backup-scanner.timer
)

echo 'This will uninstall ATD MikroTik Backup Studio services and application files.'
echo 'RouterOS backup files and the configured backup directory will NOT be deleted.'
echo 'Private panel configuration and delivery state will be preserved at first.'
read -r -p 'Continue? Type YES: ' answer
[[ "$answer" == YES ]] || { echo 'Cancelled; no changes made.'; exit 0; }

for unit in "${UNITS[@]}"; do
  systemctl disable --now "$unit" 2>/dev/null || true
  rm -f -- "/etc/systemd/system/$unit"
done

# Remove only ATD-owned Cron entries and helper.
rm -f -- /etc/cron.d/atd-mikrotik-backup-apply
rm -f -- /etc/cron.d/atd-mikrotik-backup-telegram
rm -f -- /usr/local/sbin/atd-mikrotik-backup-cron
rm -f -- /usr/local/sbin/atd-mikrotik-backup-update
systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true

# Application files contain no user backup data. Keep private config/state for
# a possible reinstall unless the operator explicitly requests their removal.
rm -rf -- "$APP"
echo
echo 'ATD services and application files have been removed.'
echo "Private configuration preserved: $TLS"
echo "Delivery state preserved: $STATE"
echo 'The configured RouterOS backup directory and its contents were not deleted.'
echo 'No third-party web-server configuration, host firewall rules, or system-wide packages were removed.'
echo 'To permanently remove the preserved ATD configuration/state after verifying your backups, delete those two ATD-specific directories manually.'

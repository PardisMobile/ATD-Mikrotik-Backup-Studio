# ATD MikroTik Backup Studio

ATD MikroTik Backup Studio creates scheduled MikroTik RouterOS 7 backups, uploads them over SFTP, and optionally sends them to Telegram through a password-protected panel.

## Panel
- Lists uploaded `.backup` files and shows Telegram delivery status.
- Supports manual send/retry, confirmed deletion, and panel-password changes.
- Persian/English interface, light/dark theme, and responsive layout.
- Keeps first-run settings and delivery state separate from updateable application code.

## Install
1. Run the Windows generator/EXE and enter the required settings once.
2. Transfer the generated `install.sh` securely to the Linux server. It contains private customer configuration; do not publish or share it.
3. Run `sudo bash install.sh`. The script downloads the matching panel code from GitHub, verifies SHA-256 checksums, writes private configuration on the server, and installs the ATD services.
4. Paste `paste-into-routeros-terminal.txt` into the MikroTik RouterOS terminal.
5. Open the HTTPS URL printed by the installer and sign in with the initial panel password.

## Update
Run `sudo atd-mikrotik-backup-update` on the Linux server. The updater stages and syntax-checks new application code, backs up the previous code, and preserves private configuration, delivery state, and uploaded backups. It restarts only the ATD PHP service. If validation or activation fails, it attempts to restore the previous application files.

## Safety and limitations
- ATD uses dedicated paths, service names, and ports. It does not edit Nginx/Apache configuration or automatically change host-wide firewall rules.
- The installer installs missing prerequisites only. If external access is blocked, review the host/provider firewall and allow the selected ATD public TCP port deliberately.
- The generated HTTPS certificate is self-signed by default, so browsers may show a certificate warning.
- CI/static checks do not replace a live end-to-end test with a real MikroTik, SFTP transfer, and Telegram bot. See `docs/TEST-REPORT.md` for verified and unverified items.

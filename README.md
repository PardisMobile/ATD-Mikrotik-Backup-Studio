# ATD MikroTik Backup Studio

ATD MikroTik Backup Studio creates scheduled MikroTik RouterOS 7 backups, uploads them over SFTP, and optionally sends them to Telegram through a password-protected panel.

## Panel
- Lists uploaded `.backup` files and shows Telegram delivery status.
- Supports manual send/retry, confirmed deletion, and panel-password changes.
- Persian/English interface, light/dark theme, and responsive layout.
- Keeps first-run settings and delivery state separate from updateable application code.

## Install
1. Run the Windows generator/EXE and enter the required settings. The SFTP host must be the same Linux server as the panel, and the backup path must be the real absolute filesystem path (not a chroot-relative SFTP path).
2. In Telegram/Panel mode, choose a public HTTPS port (default `24443`). Use the same port for this installation; allow it in the provider firewall if required.
3. Transfer the generated `install.sh` securely to the Linux server. It contains private customer configuration; do not publish or share it.
4. Run `sudo bash install.sh`. The script downloads matching panel code from GitHub, verifies SHA-256 checksums, writes private configuration on the server, and installs the ATD services.
5. Paste `paste-into-routeros-terminal.txt` into the MikroTik RouterOS terminal.
6. Open the exact HTTPS URL printed by the installer and sign in with the initial panel password.

The panel endpoint is `https://HOST:PORT/send-backup.php`; it is not served inside the SFTP backup directory. If using a custom domain or reverse proxy, enter a matching HTTPS URL in the generator and configure the proxy to reach the ATD endpoint.

## Update
Run `sudo atd-mikrotik-backup-update` on the Linux server. The updater stages and syntax-checks new application code, backs up the previous code, and preserves private configuration, delivery state, and uploaded backups. It restarts only the ATD PHP service. If validation or activation fails, it attempts to restore the previous application files.

## Safety and limitations
- ATD uses dedicated paths, service names, and ports. It does not edit Nginx/Apache configuration or automatically change host-wide firewall rules.
- The installer installs missing prerequisites only. If external access is blocked, review the host/provider firewall and allow the selected ATD public TCP port deliberately.
- The generated HTTPS certificate is self-signed by default, so browsers may show a certificate warning. For a public deployment, use a trusted certificate/domain where possible.
- The generated `install.sh` contains a base64-encoded configuration payload. Base64 is not encryption; keep the file private and transfer it securely.
- CI/static checks do not replace a live end-to-end test with a real MikroTik, SFTP transfer, and Telegram bot. See `docs/TEST-REPORT.md` for verified and unverified items.

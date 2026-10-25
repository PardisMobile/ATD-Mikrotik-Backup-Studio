# ATD MikroTik Backup Studio

ATD MikroTik Backup Studio creates scheduled MikroTik RouterOS 7 backups, uploads them to a server over SFTP, and can optionally deliver them to Telegram through a password-protected web panel.

## Panel features

- Lists uploaded backup files and allows manual Telegram send/retry.
- Prevents repeat delivery of the same file version.
- Supports confirmed backup deletion and panel password changes.
- Includes Persian/English, light/dark themes, and responsive layout.

## Install and run

1. Run `windows-client/Generate-MikroTik-Backup.ps1` on Windows and complete the setup.
2. Copy the generated package to your Linux server.
3. Paste `paste-into-routeros-terminal.txt` into the MikroTik RouterOS terminal.
4. On the server, run:

   ```bash
   sudo bash install.sh
   ```

5. Open the HTTPS URL printed by the installer and sign in with the panel password configured in the generator.

The generated package contains `install.sh`, `send-backup.php`, `panel.css`, `panel.js`, and `paste-into-routeros-terminal.txt`. The installer detects existing services, installs missing requirements only, and runs ATD on its own ports without editing existing Nginx/Apache configuration. A self-signed certificate warning is expected.

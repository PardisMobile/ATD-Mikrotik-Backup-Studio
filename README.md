# ATD MikroTik Backup Studio

ATD MikroTik Backup Studio creates scheduled MikroTik RouterOS 7 backups, uploads them over SFTP, and optionally sends them to Telegram using an isolated server-side scanner and a password-protected panel. New RouterOS scripts use SFTP only; Telegram failures cannot affect backup creation, SFTP, or the Keep/Delete local-file choice.

## Panel features
- Lists uploaded `.backup` files from the configured Linux backup directory.
- Shows Telegram delivery status and supports manual send/retry.
- Supports selecting old backup files for confirmed deletion.
- Allows changing the panel password.
- Lets you configure or replace the Telegram Bot Token and destination Chat ID inside the panel, with direct setup guides for `@BotFather` and `@userinfobot` and an optional test message.
- Persian/English interface, light/dark theme, and responsive layout.
- Keeps first-run settings and delivery state separate from updateable application code.

## First test: one MikroTik router + one Linux server

Use a test router and a Linux server you control. The SFTP host and panel must be the **same Linux server**, because the panel reads the uploaded files directly from that server's filesystem.

### 1. Generate the package on Windows
1. Run the Windows generator/EXE.
2. Choose **3) SFTP + Telegram** to test the complete flow (SFTP upload, panel, and Telegram). Mode **1** tests SFTP only and does not install a panel.
3. Enter the Linux server's hostname/IP and the existing SFTP username/password that already work for you. SFTP uses port **22**.
4. Set the backup directory to a dedicated absolute Linux path. For example, use `/root/Uploads` if that is the real directory your existing SFTP workflow uses. Do not enter a chroot-relative path.
5. Set the public HTTPS port (default `24443`) and a panel password of at least 12 characters. Telegram credentials are configured after installation from the panel; the generator no longer asks for a Bot Token or Chat ID.
6. Choose the backup schedule and whether to retain local router backups.

### 2. Install the panel on the same Linux server
1. Copy the generated `install.sh` securely to the Linux server. Do not post it publicly; it contains private configuration.
2. Run `sudo bash install.sh`.
3. In panel mode, the installer creates the configured backup directory if it does not exist and grants the dedicated ATD panel service access to it. It does not require you to create a new SFTP account and does not change the existing SFTP credentials.
4. Note the exact HTTPS URL printed by the installer. If remote access is needed, allow the selected TCP port in the server/provider firewall after checking existing firewall policy. The installer does not change firewall rules.
5. Open that URL and sign in with the initial panel password. The default TLS certificate is self-signed, so a browser warning is expected.
6. In **Telegram delivery settings**, follow the `@BotFather` guide for the token and `@userinfobot` guide for your numeric Chat ID. Start your own bot in Telegram, save the settings, then use **Send test message** to verify delivery.

### 3. Configure the MikroTik
1. Open the generated `paste-into-routeros-terminal.txt` and paste its full contents into the RouterOS 7 terminal on the test router.
2. The generated script and daily scheduler are created by that command. The first scheduled run occurs at the configured time; for an immediate test, manually run the script using the name you entered in the generator:
   `/system script run name-of-your-script`
   Replace `name-of-your-script` with the exact script name you chose.
3. Check RouterOS **Log** for `BACKUP:` messages and confirm the upload completed.

### 4. Verify the complete flow
- Confirm a new `.backup` file appears in the configured server directory.
- Sign in to the panel and confirm that the same file is listed.
- Confirm the server-side scanner timer sends a newly uploaded backup to Telegram and the panel's delivery status updates. This may take up to about a minute after SFTP completes.
- In the panel, test manual send/retry on a test file.
- Test deletion only with a disposable test backup and confirm the selected file disappears.
- If a file does not appear, check the RouterOS log, SFTP path/permissions, and the ATD services on Linux before changing any existing SFTP configuration.

### 5. If the directory must be created separately
The generator also creates `create-sftp-directory.txt`, containing a command for the selected directory. On the Linux server, an administrator can run that command (prefix it with `sudo` if required by the current shell user). In panel mode, the installer already creates the directory automatically, so this file is mainly a convenience for SFTP-only use or manual setup.

## Output files
- `paste-into-routeros-terminal.txt`: complete RouterOS script and scheduler setup.
- `install.sh`: private server bootstrap, generated only in Telegram/Panel mode.
- `create-sftp-directory.txt`: command to create the configured SFTP directory.

## Update
Run `sudo atd-mikrotik-backup-update` on the Linux server. The updater stages and syntax-checks new application code, backs up the previous code, and preserves private configuration, delivery state, and uploaded backups. It restarts only the ATD PHP service.

## Safety and limitations
- ATD uses dedicated paths, service names, and ports. It does not edit Nginx/Apache configuration or automatically change host-wide firewall rules.
- The installer installs missing prerequisites only. If external access is blocked, review the host/provider firewall and allow the selected ATD public TCP port deliberately.
- The panel runs under a dedicated service account. The installer grants it access to the configured backup directory; this is separate from the existing SFTP account used by the router to upload files.
- The generated `install.sh` contains a base64-encoded configuration payload. Base64 is not encryption; keep the file private and transfer it securely.
- GitHub Actions/static checks do not replace a live end-to-end test with a real MikroTik, SFTP transfer, and Telegram bot. The project must not be considered production-ready until that flow has been tested on a disposable Linux server. See `docs/TEST-REPORT.md` for verification status.

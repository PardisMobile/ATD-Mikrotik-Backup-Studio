# ATD MikroTik Backup Studio

ATD MikroTik Backup Studio creates scheduled MikroTik RouterOS 7 backups, uploads them over the existing SFTP workflow, and automatically sends newly arrived, stable backup files to Telegram using a dedicated Linux-side cron job. RouterOS scripts remain SFTP-only; Telegram delivery failures cannot affect backup creation, SFTP, or the Keep/Delete local-file choice.

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
6. Enter your Telegram bot token and destination Chat ID in the Windows generator. The Linux installer saves them in private configuration, so scheduled delivery works without a separate setup step. The panel still lets an administrator change settings and send a test message.

### 3. Configure the MikroTik
1. Open the generated `paste-into-routeros-terminal.txt` and paste its full contents into the RouterOS 7 terminal on the test router.
2. The generated script and daily scheduler are created by that command. The first scheduled run occurs at the configured time; for an immediate test, manually run the script using the name you entered in the generator:
   `/system script run name-of-your-script`
   Replace `name-of-your-script` with the exact script name you chose.
3. Check RouterOS **Log** for `BACKUP:` messages and confirm the upload completed.

### 4. Verify the complete flow
- Confirm a new `.backup` file appears in the configured server directory.
- Sign in to the panel and confirm that the same file is listed.
- Confirm that a new SFTP upload appears in the panel and is sent automatically by the dedicated Linux cron job. The scanner runs every minute, ignores files already present at installation, checks file-size stability, and avoids duplicate sends by filename and SHA-256.
- In the panel, test manual send/retry on a test file.
- Test deletion only with a disposable test backup and confirm the selected file disappears.
- If a file does not appear, check the RouterOS log, SFTP path/permissions, the ATD PHP/TLS services, and the panel callback response before changing any existing SFTP configuration.

### 5. If the directory must be created separately
The generator also creates `create-sftp-directory.txt`, containing a command for the selected directory. On the Linux server, an administrator can run that command (prefix it with `sudo` if required by the current shell user). In panel mode, the installer already creates the directory automatically, so this file is mainly a convenience for SFTP-only use or manual setup.

## Output files
- `paste-into-routeros-terminal.txt`: complete RouterOS script and scheduler setup.
- `install.sh`: private server bootstrap, generated only in Telegram/Panel mode.
- `create-sftp-directory.txt`: command to create the configured SFTP directory.

## Update
To update an existing installation, run `sudo atd-mikrotik-backup-update`. The updater stages and syntax-checks the application, backs up the previous code, preserves private configuration, delivery state, and uploaded backups, removes obsolete ATD-only worker/timer units, and installs the dedicated cron entry. It does not edit RouterOS scripts, third-party web-server configuration, or firewall rules.

## Safety and limitations
- ATD uses dedicated paths, service names, and ports. It does not edit Nginx/Apache configuration or automatically change host-wide firewall rules.
- The installer installs missing prerequisites only. If external access is blocked, review the host/provider firewall and allow the selected ATD public TCP port deliberately.
- The panel runs under a dedicated service account. The installer grants it access to the configured backup directory; this is separate from the existing SFTP account used by the router to upload files.
- The generated `install.sh` contains a base64-encoded configuration payload. Base64 is not encryption; keep the file private and transfer it securely.
- GitHub Actions/static checks do not replace a live end-to-end test with a real MikroTik, SFTP transfer, and Telegram bot. The project must not be considered production-ready until that flow has been tested on a disposable Linux server. See `docs/TEST-REPORT.md` for verification status.

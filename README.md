# ATD MikroTik Backup Studio

ATD MikroTik Backup Studio creates scheduled MikroTik RouterOS 7 backups, uploads them over the existing SFTP workflow, and automatically sends newly arrived, stable backup files to Telegram using a Linux-side Cron schedule derived from the selected RouterOS backup times. RouterOS scripts remain SFTP-only; Telegram delivery failures cannot affect backup creation, SFTP, or the Keep/Delete local-file choice.

## Panel features
- Lists uploaded `.backup` files from the configured Linux backup directory, with server-side sorting by filename, file size, or modification date while retaining search and pagination.
- The Settings page can check GitHub for a newer commit and compare it with the recorded installed source commit; update checks do not install anything automatically.
- Shows Telegram delivery status; one connection test sends the newest existing backup file to Telegram.
- Supports selecting old backup files for confirmed deletion.
- Allows changing the panel password.
- Lets you configure or replace the Telegram Bot Token and destination Chat ID inside the panel, with direct setup guides for `@BotFather` and `@userinfobot`.
- Persian/English interface, light/dark theme, responsive layout, and section-based navigation (Dashboard, Backups, Telegram, Settings).
- Live Linux server date/time shown at the top of the panel.
- Configurable Linux system time zone and matching Cron schedule zone through a restricted root-owned helper; this changes the time zone, not the system clock itself. RouterOS has a separate clock/time-zone setting, so changing zones after installation also requires aligning RouterOS.
- Stores the backup time(s) selected in the Windows generator and schedules Linux-side Telegram scans after a configurable delay (default: 2 minutes), with a six-minute retry window.
- Provides one **Test Telegram connection** action that sends the newest existing `.backup` file; there is no separate text-only test or per-file send button.
- Keeps first-run settings and delivery state separate from updateable application code.

## First test: one MikroTik router + one Linux server

Use a test router and a Linux server you control. The SFTP host and panel must be the **same Linux server**, because the panel reads the uploaded files directly from that server's filesystem.

### 1. Generate the package on Windows
1. Run the Windows generator/EXE.
2. Choose **2) SFTP + Telegram panel** to enable the complete flow (SFTP upload, panel, and Telegram). Mode **1** is SFTP-only and does not install a panel.
3. Enter the Linux server's hostname/IP and the existing SFTP username/password that already work for you. SFTP uses port **22**.
4. Set the backup directory to a dedicated absolute Linux path. For example, use `/root/Uploads` if that is the real directory your existing SFTP workflow uses. Do not enter a chroot-relative path.
5. Set the public HTTPS port (default `24443`) and a panel password of at least 8 characters. Telegram credentials are configured after installation from the panel; the generator no longer asks for a Bot Token or Chat ID.
6. Choose the backup schedule and whether to retain local router backups.

### 2. Install the panel on the same Linux server
1. Copy the generated `install.sh` securely to the Linux server. Do not post it publicly; it contains private configuration.
2. Run `sudo bash install.sh`.
3. In panel mode, the installer creates the configured backup directory if it does not exist and grants the dedicated ATD panel service access to it. It does not require you to create a new SFTP account and does not change the existing SFTP credentials.
4. Note the exact HTTPS URL printed by the installer. If remote access is needed, allow the selected TCP port in the server/provider firewall after checking existing firewall policy. The installer does not change firewall rules.
5. Open that URL and sign in with the initial panel password. The default TLS certificate is self-signed, so a browser warning is expected.

### 3. Configure Telegram delivery
1. **Create or select your bot and get its token:** in Telegram, open [@BotFather](https://t.me/BotFather). Send `/newbot` to create a bot and follow BotFather's prompts; if you already have a bot, select it and open its API-token details. Copy the Bot Token and keep it secret.
2. **Start your own bot:** open the bot's private chat in Telegram and press **Start** or send `/start`. This is required before the bot can send backup files to your private chat. Telegram bots cannot initiate a private conversation with a user who has not started them.
3. **Get your destination Chat ID:** open [@userinfobot](https://t.me/userinfobot), press **Start**, and copy the numeric ID it shows. For a group destination, add your bot to that group and use the group's Chat ID instead (group IDs are often negative).
4. Sign in to the ATD panel and enter the Bot Token and destination Chat ID in **Telegram delivery settings**, then save.
5. Use **Test Telegram connection** to verify delivery. The test checks the configured backup folder and sends its newest `.backup` file; it does not send a separate text-only test message.

### 3. Configure the MikroTik
1. Open the generated `paste-into-routeros-terminal.txt` and paste its full contents into the RouterOS 7 terminal on the test router.
2. The generated script and daily scheduler are created by that command. The first scheduled run occurs at the configured time; for an immediate test, manually run the script using the name you entered in the generator:
   `/system script run name-of-your-script`
   Replace `name-of-your-script` with the exact script name you chose.
3. Check RouterOS **Log** for `BACKUP:` messages and confirm the upload completed.

### 4. Verify the complete flow
- Confirm a new `.backup` file appears in the configured server directory.
- Sign in to the panel and confirm that the same file is listed.
- Confirm that a new SFTP upload appears in the panel and is sent automatically according to the backup times saved by the Windows generator. Cron retries scanning for six minutes after the configured delay, ignores files already present at first install, checks file-size stability, and avoids duplicate sends by filename and SHA-256.
- In the panel, use the single **Test Telegram connection** action to send the newest existing backup file.
- Test deletion only with a disposable test backup and confirm the selected file disappears.
- If a file does not appear, check the RouterOS log, SFTP path/permissions, the ATD PHP/TLS services, and the cron scanner logs before changing any existing SFTP configuration.

### 5. If the directory must be created separately
The generator also creates `create-sftp-directory.txt`, containing a command for the selected directory. On the Linux server, an administrator can run that command (prefix it with `sudo` if required by the current shell user). In panel mode, the installer already creates the directory automatically, so this file is mainly a convenience for SFTP-only use or manual setup.

## Output files
- `paste-into-routeros-terminal.txt`: complete RouterOS script and scheduler setup.
- `install.sh`: private server bootstrap, generated only in Telegram/Panel mode.
- `create-sftp-directory.txt`: command to create the configured SFTP directory.

## Time zone and clock
The panel displays the Linux server's live date/time and detected system time zone. In Settings, selecting a supported IANA time zone applies it to the Linux host with timedatectl set-timezone and saves the same zone for the Linux Cron schedule. This changes the host's system-wide time-zone setting but does not manually change the clock or disable NTP. RouterOS Scheduler uses the router's own clock/time-zone configuration; if the zone is changed after initial setup, align the router's time-zone-name as well. See the official MikroTik Clock documentation (https://help.mikrotik.com/docs/spaces/ROS/pages/40992866/Clock) and Ubuntu timedatectl manual (https://manpages.ubuntu.com/manpages/jammy/man1/timedatectl.1.html).

## Update
To update an existing installation, run `sudo atd-mikrotik-backup-update`. The updater stages and syntax-checks the application, backs up the previous code, preserves private configuration, delivery state, and uploaded backups, removes obsolete ATD-only worker/timer units, and reapplies the dedicated Cron entry from saved delivery settings. It does not edit RouterOS scripts, third-party web-server configuration, or firewall rules.

**Updater self-refresh:** the updater checks and installs its current GitHub version before running migrations, then re-executes that refreshed copy. A single `sudo atd-mikrotik-backup-update` run should therefore apply the latest updater and its application/helper changes together. If the installed updater is from an older release and cannot bootstrap itself, run this one-time bootstrap command instead:

```bash
curl -fsSL https://raw.githubusercontent.com/PardisMobile/ATD-Mikrotik-Backup-Studio/main/server-deployment/update-standalone.sh | sudo bash
```

After that, use `sudo atd-mikrotik-backup-update` normally.

## Safety and limitations
- ATD uses dedicated paths, service names, and ports. It does not edit Nginx/Apache configuration or automatically change host-wide firewall rules.
- The installer installs missing prerequisites only. If external access is blocked, review the host/provider firewall and allow the selected ATD public TCP port deliberately.
- The panel runs under a dedicated service account. The installer grants it access to the configured backup directory; this is separate from the existing SFTP account used by the router to upload files.
- The generated `install.sh` contains a base64-encoded configuration payload. Base64 is not encryption; keep the file private and transfer it securely.
- GitHub Actions/static checks do not replace a live end-to-end test with a real MikroTik, SFTP transfer, and Telegram bot. The project must not be considered production-ready until that flow has been tested on a disposable Linux server. See `docs/TEST-REPORT.md` for verification status.

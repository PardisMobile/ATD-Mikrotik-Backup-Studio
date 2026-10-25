# ATD MikroTik Backup Studio

ATD MikroTik Backup Studio creates scheduled MikroTik RouterOS 7 backups, uploads them over the existing SFTP workflow, and automatically sends newly arrived, stable backup files to Telegram using a Linux-side Cron schedule derived from the selected RouterOS backup times. RouterOS scripts remain SFTP-only; Telegram delivery failures cannot affect backup creation, SFTP, or the Keep/Delete local-file choice.

## Panel features
- Lists uploaded `.backup` files from the configured Linux backup directory.
- Shows Telegram delivery status; one connection test sends the newest existing backup file to Telegram.
- Supports selecting old backup files for confirmed deletion.
- Allows changing the panel password.
- Lets you configure or replace the Telegram Bot Token and destination Chat ID inside the panel, with direct setup guides for `@BotFather` and `@userinfobot`.
- Persian/English interface, light/dark theme, and responsive layout.
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
6. Sign in to the panel, enter the Telegram bot token and destination Chat ID in **Telegram delivery settings**, then use **Test Telegram connection**. It checks the configured backup folder and sends its newest `.backup` file (not a separate text message).

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

## Update
To update an existing installation, run `sudo atd-mikrotik-backup-update`. The updater stages and syntax-checks the application, backs up the previous code, preserves private configuration, delivery state, and uploaded backups, removes obsolete ATD-only worker/timer units, and reapplies the dedicated Cron entry from saved delivery settings. It does not edit RouterOS scripts, third-party web-server configuration, or firewall rules.

## Safety and limitations
- ATD uses dedicated paths, service names, and ports. It does not edit Nginx/Apache configuration or automatically change host-wide firewall rules.
- The installer installs missing prerequisites only. If external access is blocked, review the host/provider firewall and allow the selected ATD public TCP port deliberately.
- The panel runs under a dedicated service account. The installer grants it access to the configured backup directory; this is separate from the existing SFTP account used by the router to upload files.
- The generated `install.sh` contains a base64-encoded configuration payload. Base64 is not encryption; keep the file private and transfer it securely.
- GitHub Actions/static checks do not replace a live end-to-end test with a real MikroTik, SFTP transfer, and Telegram bot. The project must not be considered production-ready until that flow has been tested on a disposable Linux server. See `docs/TEST-REPORT.md` for verification status.


## Project Context for Continued Development

**Source of truth:** work directly on `main`. Do not create branches or pull requests unless the owner explicitly asks. Do not force-push or delete branches as a substitute for reviewing their changes.

### Current implementation snapshot (2026-10-25)
- Current reviewed `main` head before this context update: `c7724376a5a2e4fde77268acb9250ce1755e9de4`.
- Windows PowerShell generator: `windows-client/Generate-MikroTik-Backup.ps1`.
- Canonical server panel: `server-deployment/send-backup.php`, `panel.css`, `panel.js`, and `cron-helper.sh`. The generator embeds these assets; CI checks byte-for-byte synchronization (ignoring trailing line endings).
- Telegram credentials are configured through the authenticated web panel, not prompted for by the Windows generator. The single Telegram connection test sends the newest existing backup file; it is not a text-only test.
- RouterOS continues to create and upload backups through SFTP; RouterOS does not call Telegram or the PHP panel.
- Router backup schedule is selected in the generator and saved in private config. The panel manages Linux-side Telegram delivery schedule and delay through a root-owned Cron apply worker.
- New panel passwords require at least 8 characters; the Windows generator asks for confirmation and retries after mismatch/too-short input.
- Installer, updater, and safe uninstaller are `server-deployment/install-standalone.sh`, `server-deployment/update-standalone.sh`, and `server-deployment/uninstall-standalone.sh`. The uninstaller removes only ATD services/app files and preserves the configured backup directory, private configuration, and delivery state.

### Branch reconciliation
- `fix/telegram-schedule-and-connection-test` contains 25 commits after common base `15022946ec458758eff516968ee1cfcce7f673e3`; `main` contains its own 8 commits after that same base. The histories are divergent, so do not merge blindly or delete the branch until every unique change has been reviewed.
- The current `main` has the core files and implementation invariants from that branch, plus the newer 8-character password policy and generator retry/confirmation changes. Recent comparison showed matching workflow, installer, updater, and test report; expected differences include password text/policy and generator guidance.
- `fix/panel-password-confirmation-and-generator-help` was created without the owner's permission. Do not create additional branches. Review and clean up both extra branches only after reconciliation; use `main` as the sole working branch.

### Verification status — do not overstate
- The source-check workflow defines PHP lint (canonical and embedded PHP), JavaScript/CSS syntax checks, canonical asset consistency, generated bootstrap shell syntax, implementation invariants, Bash syntax/ShellCheck, and Windows PowerShell parser validation.
- As of the review above, the GitHub connector returned no combined status checks for main commit `c7724376a5a2e4fde77268acb9250ce1755e9de4`; this is **not evidence of a pass**. Its workflow-run wrapper only returns pull-request-triggered runs and returned none for that main commit, so inspect GitHub Actions directly or trigger a workflow run before release.
- Real-server end-to-end tests remain outstanding: clean install, rerun/preservation, updater and rollback, RouterOS 7 scheduled SFTP upload, Telegram delivery/deduplication/retries, panel schedule changes, password change, and TLS/firewall behavior.
- Do not claim production readiness until the latest CI is green and end-to-end tests are documented in `docs/TEST-REPORT.md`.

### Instructions for the next ChatGPT session
1. Read this section and `docs/TEST-REPORT.md` first.
2. Fetch the live `main` head before editing; do not rely on old SHAs if main moved.
3. Work directly on `main`; commit changes directly to `main`, one coherent fix at a time.
4. Check embedded PHP/CSS/JS/Cron helper against canonical files after any relevant change.
5. Run or inspect actual CI and report exact evidence; never infer a pass from missing status checks.
6. Inspect unique commits and file diffs on both extra branches, reconcile useful work to `main`, and only then remove obsolete branches if repository permissions allow.

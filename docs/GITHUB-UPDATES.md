# GitHub-based installation and updates

## First-run configuration and bootstrap

The Windows generator collects the SFTP destination, first-run panel credentials, backup directory and schedule, public panel port, maximum accepted file size, and default Linux time zone. Cron defaults independently to UTC and can be configured separately in the panel. Telegram credentials are configured later in the authenticated panel. The generated `install.sh` contains a base64-encoded private configuration payload; base64 is encoding, not encryption, so keep the package private.

The bootstrap resolves the current `main` commit once, then downloads the versioned server assets from that immutable commit. It downloads `send-backup.php`, `panel.css`, `panel.js`, `cron-helper.sh`, and `install-standalone.sh` before invoking the runtime installer with the same pinned commit. It does not embed the application assets in the customer package. The installer stores private configuration at `/etc/atd-mikrotik-backup-studio/config.php`, serves versioned app code from `/opt/atd-mikrotik-backup-studio`, and keeps mutable state and sessions under `/var/lib/atd-mikrotik-backup-studio`.

## Terminal update

For an existing installation, run:

```bash
sudo atd-mikrotik-backup-update
```

The installed updater first fetches and syntax-checks the latest updater, atomically replaces its own executable, and re-executes it while passing the exact source commit SHA. This pins the updater and all subsequently downloaded assets to one immutable snapshot. It then locks against concurrent runs, downloads the PHP, CSS, JavaScript, Cron helper, and Linux timezone helper to a temporary staging directory, and validates syntax and expected PHP interfaces before touching live application files.

Before activation, the updater stores a timestamped snapshot under `/var/lib/atd-mikrotik-backup-studio`. The transaction covers the versioned app assets, ATD-owned Cron/timezone helpers and Cron entries, updater executable, timezone sudo policy, the ATD PHP service unit, the known legacy ATD panel-update sudoers file, and installed-source marker. It changes only `NoNewPrivileges` in the ATD PHP unit so the fixed timezone command can use its restricted sudo rule, and replaces the known obsolete panel-update sudo rule with the same timezone-only rule. It refuses unexpected unit metadata or custom sudoers content. It does not create a panel Worker or alter unrelated systemd units/timers. The shared host Cron service is only checked as a precondition and is never modified. It writes the new installed-source marker and prints success only after required postconditions pass. On a transaction error, its rollback restores the captured files and ATD service states and verifies that host Cron stayed active and enabled.

The update may touch these ATD-owned paths:

- `/opt/atd-mikrotik-backup-studio/{send-backup.php,panel.css,panel.js}`
- `/usr/local/sbin/atd-mikrotik-backup-{update,cron,set-timezone}`
- `/etc/cron.d/atd-mikrotik-backup-{apply,telegram}`
- `/etc/sudoers.d/atd-panel-timezone`
- `/var/lib/atd-mikrotik-backup-studio/installed-source-commit` and the updater's timestamped snapshot
- `/etc/systemd/system/atd-mikrotik-backup-php.service` (only the `NoNewPrivileges` directive)
- `/etc/sudoers.d/atd-mikrotik-backup-panel-update` (only the known legacy rule is replaced with the fixed timezone-helper rule; file remains present)
- All other systemd unit and timer files are outside the update write set.

It does not replace the private configuration, Telegram delivery state, uploaded backup files, TLS certificate/key, or assigned ports. It does not modify RouterOS scripts, third-party web-server configuration, firewall rules, or any unrelated systemd unit/timer. It requires an existing host Cron daemon to be active and enabled; otherwise it aborts with `HOST_CRON_NOT_READY`. It manages only the project's own `/etc/cron.d` entries and does not install, enable, start, stop, or repair the shared daemon.

Panel updates are terminal-only. The UI reports the installed commit and directs administrators to run `sudo atd-mikrotik-backup-update`; it does not invoke systemd-run or create a background Worker.

## Verification boundaries

The updater checks HTTPS downloads, PHP and shell syntax, the separate private configuration, expected PHP features, timezone helper installation, sudo-rule syntax/permissions, and the final source marker. A successful run does not prove a Telegram message was delivered, a RouterOS backup arrived, or rollback recovery works under injected failure. Those require separate live tests. Telegram Test sends the newest existing `.backup` file with Telegram `sendDocument`; obtain explicit approval before running it if a real file delivery is not intended.

The source is pinned by immutable commit SHA but is not independently authenticated by a signed release or separately pinned asset manifest. GitHub transport and source integrity remain trust dependencies.

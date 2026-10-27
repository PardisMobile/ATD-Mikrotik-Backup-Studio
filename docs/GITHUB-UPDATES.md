# GitHub-based installation and updates

## First-run configuration and bootstrap

The Windows generator collects the SFTP destination, first-run panel credentials, backup directory and schedule, public panel port, maximum accepted file size, and default Linux/Cron time zone. Telegram credentials are configured later in the authenticated panel. The generated `install.sh` contains a base64-encoded private configuration payload; base64 is encoding, not encryption, so keep the package private.

The bootstrap resolves the current `main` commit once, then downloads the versioned server assets from that immutable commit. It downloads `send-backup.php`, `panel.css`, `panel.js`, `cron-helper.sh`, and `install-standalone.sh` before invoking the runtime installer with the same pinned commit. It does not embed the application assets in the customer package. The installer stores private configuration at `/etc/atd-mikrotik-backup-studio/config.php`, serves versioned app code from `/opt/atd-mikrotik-backup-studio`, and keeps mutable state and sessions under `/var/lib/atd-mikrotik-backup-studio`.

## Terminal update

For an existing installation, run:

```bash
sudo atd-mikrotik-backup-update
```

The installed updater first fetches and syntax-checks the latest updater, atomically replaces its own executable, and re-executes it while passing the exact source commit SHA. This pins the updater and all subsequently downloaded assets to one immutable snapshot. It then locks against concurrent runs, downloads the PHP, CSS, JavaScript, Cron helper, and Linux timezone helper to a temporary staging directory, and validates syntax and expected PHP interfaces before touching live application files.

Before activation, the updater stores a timestamped snapshot under `/var/lib/atd-mikrotik-backup-studio`. The transaction covers the versioned app assets, ATD-owned helpers, Cron entries, updater entry points, sudo policy files, installed-source marker, legacy ATD scanner unit definitions/states, and the active/enabled states of the ATD PHP/TLS services and the host Cron daemon. It replaces these ATD-owned paths, reapplies the ATD schedule from saved settings, and restarts only the ATD PHP and TLS services that were active before the update. It writes the new installed-source marker and prints success only after required postconditions pass. On a transaction error, its rollback restores the captured files and service states and reports whether verification passed.

The update may touch these ATD-owned paths:

- `/opt/atd-mikrotik-backup-studio/{send-backup.php,panel.css,panel.js}`
- `/usr/local/sbin/atd-mikrotik-backup-{update,cron,set-timezone,panel-update,panel-update-worker}`
- `/etc/cron.d/atd-mikrotik-backup-{apply,telegram}`
- `/etc/sudoers.d/atd-mikrotik-backup-panel-update` and `/etc/sudoers.d/atd-panel-timezone`
- `/var/lib/atd-mikrotik-backup-studio/installed-source-commit` and the updater's timestamped snapshot
- Only the explicitly named legacy ATD scanner/worker unit files, when present

It does not replace the private configuration, Telegram delivery state, uploaded backup files, TLS certificate/key, or assigned ports. It does not modify RouterOS scripts, third-party web-server configuration, firewall rules, or unrelated service definitions. It requires the host Cron daemon for the ATD schedule; if no Cron unit exists, the current scripts can install/enable the generic daemon. Review host compatibility before using this flow on a server without an existing Cron service. The current production host's Cron daemon was observed active and enabled on 2026-10-28.

The panel-triggered updater is a separate path: it calls a narrowly scoped root launcher which starts a transient ATD systemd update unit. Do not use that path when a policy or test explicitly prohibits background updater workers; the terminal command does not invoke the panel launcher.

## Verification boundaries

The updater checks HTTPS downloads, PHP and shell syntax, the separate private configuration, expected PHP features, timezone helper installation, sudo-rule syntax/permissions, and the final source marker. A successful run does not prove a Telegram message was delivered, a RouterOS backup arrived, or rollback recovery works under injected failure. Those require separate live tests. Telegram Test sends the newest existing `.backup` file with Telegram `sendDocument`; obtain explicit approval before running it if a real file delivery is not intended.

The source is pinned by immutable commit SHA but is not independently authenticated by a signed release or separately pinned asset manifest. GitHub transport and source integrity remain trust dependencies.

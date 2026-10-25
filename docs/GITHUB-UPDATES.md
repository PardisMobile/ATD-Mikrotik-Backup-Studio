# GitHub-based server updates and configuration preservation

## First-run configuration

The Windows generator collects the SFTP destination, initial panel password hash/salt, backup directory, selected backup schedule, public panel port, and maximum accepted file size. Telegram bot token and chat ID are configured later from the authenticated web panel. The generated `install.sh` carries this customer-specific configuration in a base64 payload; base64 is encoding, not encryption, so keep the generated installer private and transfer it securely.

At installation, the bootstrap resolves the current `main` commit once and downloads all server assets—including `send-backup.php`, `panel.css`, `panel.js`, `cron-helper.sh`, and `install-standalone.sh`—using that immutable commit SHA. This prevents separate requests from mixing files from different commits. The generated package embeds only customer-specific private configuration; it does not embed the panel implementation. The installer writes configuration to `/etc/atd-mikrotik-backup-studio/config.php` with restrictive permissions. The PHP application code contains no customer secrets.

## Update command

After installation, run:

```bash
sudo atd-mikrotik-backup-update
```

The updater:
- Resolves one immutable Git commit, then downloads the application files into a temporary staging directory over HTTPS from that exact commit.
- Checks PHP syntax and confirms the PHP application loads the separate private config before touching live code.
- Creates a timestamped backup of the current application files.
- Replaces only `send-backup.php`, `panel.css`, and `panel.js`.
- Restarts only `atd-mikrotik-backup-php.service` and installs/enables the ATD-owned Telegram worker timer.
- Attempts to roll back application files if validation or activation fails.

It does not replace `/etc/atd-mikrotik-backup-studio/config.php`, the delivery state or worker baseline under `/var/lib/atd-mikrotik-backup-studio`, the configured backup directory, TLS keys, assigned ports, or unrelated service configuration.

## Security notes

- The bootstrap's embedded config is not encrypted. Do not upload generated packages to public issue trackers, repositories, or shared folders.
- Updates resolve the current `main` commit and fetch all staged files by that immutable commit SHA. This ensures snapshot consistency, but does not authenticate the commit with a signed release or independently pinned checksums; signed releases and a trusted manifest remain future hardening.
- Updates must be tested on a disposable Linux VM before production use. Do not claim real-server safety from CI checks alone.

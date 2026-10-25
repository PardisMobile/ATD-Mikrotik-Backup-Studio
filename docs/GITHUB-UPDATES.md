# GitHub-based server updates and configuration preservation

## First-run configuration

The Windows generator collects the SFTP destination and, when enabled, Telegram bot token, chat ID, legacy relay compatibility token, initial panel password hash/salt, backup directory, and maximum accepted file size. The generated `install.sh` carries this customer-specific configuration in a base64 payload; base64 is encoding, not encryption, so keep the generated installer private and transfer it securely.

At installation, the bootstrap downloads `send-backup.php`, `panel.css`, and `panel.js` from the public GitHub repository and verifies their SHA-256 hashes against the values embedded by the generator. A mismatch aborts installation rather than mixing incompatible versions. The installer writes configuration to `/etc/atd-mikrotik-backup-studio/config.php` with restrictive permissions. The PHP application code contains no customer secrets.

## Update command

After installation, run:

```bash
sudo atd-mikrotik-backup-update
```

The updater:
- Downloads the versioned application files into a temporary staging directory over HTTPS.
- Checks PHP syntax and confirms the PHP application loads the separate private config before touching live code.
- Creates a timestamped backup of the current application files.
- Replaces only `send-backup.php`, `panel.css`, and `panel.js`.
- Restarts only `atd-mikrotik-backup-php.service` and installs/enables the ATD-owned Telegram worker timer.
- Attempts to roll back application files if validation or activation fails.

It does not replace `/etc/atd-mikrotik-backup-studio/config.php`, the delivery state or worker baseline under `/var/lib/atd-mikrotik-backup-studio`, the configured backup directory, TLS keys, assigned ports, or unrelated service configuration.

## Security notes

- The bootstrap's embedded config is not encrypted. Do not upload generated packages to public issue trackers, repositories, or shared folders.
- Updates fetch the current `main` branch over HTTPS and syntax-check the staged PHP. For high-assurance production rollout, pinning signed releases and checksums for updater downloads is still recommended.
- Updates must be tested on a disposable Linux VM before production use. Do not claim real-server safety from CI checks alone.

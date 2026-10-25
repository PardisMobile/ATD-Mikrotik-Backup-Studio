# GitHub-based server updates

The server updater is an optional operation on an already-installed panel. It does not reinstall the server, edit web-server configuration, open ports, or touch MikroTik/SFTP scheduling.

## Usage

Run as a user with write permission to the installed panel directory (usually root via sudo):

```bash
sudo bash update-server.sh /absolute/path/to/installed/panel
```

The updater downloads only `send-backup.php`, `panel.css`, and `panel.js` from the repository's `main` branch over HTTPS. It stages downloads first, rejects empty files, checks PHP syntax, creates a timestamped backup, and restores previous files if the final PHP syntax check fails.

Before replacing PHP, it carries forward matching customer-specific string constants from the currently installed `send-backup.php`: relay token, Telegram bot token, numeric Chat ID, panel password hash, backup directory, and state-file path. Other runtime constants retain the values from the repository template. Never commit customer-specific values to GitHub.

## Important limitations

- This is a first safe updater implementation, not a claim that Telegram delivery has passed end-to-end tests.
- It uses the moving `main` branch for development/testing. For production deployments, pin to a reviewed release/tag and validate a published SHA-256 manifest before rollout.
- The Windows generator must include this updater in its generated server package and expose a menu/command for it; the repository currently does not yet contain the original PowerShell generator source, so that integration cannot be claimed complete until the exact source is restored and reviewed.
- Keep the known-good SFTP-only path unchanged and test it after each release.

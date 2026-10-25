# Test report and current verification status

Last reviewed: 2026-10-25.

## Repository-level implementation review
- The Windows PowerShell generator is present at `windows-client/Generate-MikroTik-Backup.ps1`.
- The generator creates a customer-specific `install.sh` containing the first-run configuration payload and the expected SHA-256 hashes for the matching server PHP/CSS/JS files.
- The generated installer downloads panel application assets from GitHub and validates checksums before installation. The generated output no longer requires the user to transfer separate `send-backup.php`, `panel.css`, or `panel.js` files.
- The PHP application loads private constants from `/etc/atd-mikrotik-backup-studio/config.php`; that config is not part of the updateable application assets.
- The runtime installer preserves an existing private config and allocated ports on re-run, and no longer changes host-wide firewall rules automatically.
- A dedicated updater is available as `sudo atd-mikrotik-backup-update`; it stages and syntax-checks app code, backs up prior app files, and targets only the ATD PHP service.

## Automated checks
- GitHub Actions workflows run Bash syntax checks, ShellCheck, PHP syntax checks, and source/invariant checks. Their status must be checked against the latest commit before release.
- Static validation does not establish that a real server install or update succeeds end to end.

## Not yet verified on a real server
- A clean Linux VM install using the exact generated `install.sh` and generated private configuration.
- Re-running the installer with an existing installation and verifying every config value, allocated port, state entry, and backup file remains unchanged.
- Updating PHP/CSS/JS from GitHub and validating rollback after a deliberately invalid staged file.
- A real MikroTik RouterOS 7 scheduled backup and SFTP transfer.
- Actual Telegram bot delivery, duplicate-send behavior, and the panel password-change flow.
- Compatibility with all Linux distributions and existing host firewall/provider policies.

## Release gate
Do not describe the project as production-ready until the latest CI checks pass and the full install/update/SFTP/Telegram flow has been exercised on a disposable Linux server. Record the exact commit and the actual test environment in any final release report.

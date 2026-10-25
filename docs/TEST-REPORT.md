# Test report and current verification status

Last reviewed: 2026-10-25.

## Repository-level implementation review
- The Windows generator creates a customer-specific `install.sh` in Telegram/Panel mode. It embeds the first-run config payload and SHA-256 hashes for matching PHP/CSS/JS application assets.
- The generated installer downloads panel assets from GitHub and verifies hashes before installation; separate panel asset transfers are not required.
- Newly generated RouterOS scripts call the authenticated panel endpoint only after a successful SFTP upload; they never call Telegram directly. PHP checks file-size stability across two intervals, sends the file to Telegram, records its SHA-256 to avoid duplicate delivery, and accepts legacy `RELAY_TOKEN` configurations. Installer/updater cleanup removes legacy worker/scanner units and timers.
- The runtime installer reads the selected public port from the generated configuration, checks for conflicts on a clean install, preserves the installed port on re-runs, and aborts if a new package expects a different port.
- PHP sessions use an ATD-owned writable directory, and panel session cookies are explicitly marked Secure because TLS terminates at the local socat proxy.
- The original RouterOS identity-based backup filename behavior is preserved; the scanner skips unsupported filenames rather than modifying the SFTP core.
- Private configuration lives at `/etc/atd-mikrotik-backup-studio/config.php`; delivery state and session data live under `/var/lib/atd-mikrotik-backup-studio`.
- A dedicated updater is available as `sudo atd-mikrotik-backup-update`; it stages and syntax-checks app code, backs up prior app files, and targets only the ATD PHP service.

## Automated checks
- GitHub Actions run Bash syntax checks, ShellCheck, PHP syntax checks, source/template consistency tests, bootstrap syntax checks, key URL/port/session invariants, and PowerShell parser validation.
- The latest CI status must be checked against the final commit before release.
- Static validation does not establish that a real server install or update succeeds end to end.

## Not yet verified on a real server
- A clean Linux VM install using the exact generated `install.sh` and private configuration.
- Re-running the installer and verifying every config value, assigned port, state entry, and backup file remains unchanged.
- Updating PHP/CSS/JS from GitHub and validating rollback after a deliberately invalid staged file.
- A real MikroTik RouterOS 7 scheduled backup and SFTP transfer.
- Actual Telegram bot delivery, duplicate-send behavior, the Linux cron scanner, actual Telegram delivery, duplicate-send behavior, and panel password-change flow.
- Certificate trust behavior for RouterOS and browser access on a public server with the intended domain/certificate.
- Compatibility with all Linux distributions and existing host firewall/provider policies.

## Release gate
Do not describe the project as production-ready until the latest CI checks pass and the full install/update/SFTP/Telegram flow has been exercised on a disposable Linux server. Record the exact commit and the actual test environment in any final release report.

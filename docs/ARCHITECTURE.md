# Architecture and source-of-truth rules

## Goal

Preserve the existing RouterOS 7 scheduled-backup-to-SFTP workflow and add an optional Telegram relay and password-protected panel around it. The first-run values collected by the Windows generator are persistent configuration, not part of updateable UI/application code.

## Components

1. **Windows client** — `windows-client/Generate-MikroTik-Backup.ps1`, launcher, icon, and build/launch BAT files. Preserve existing RouterOS/SFTP behavior unless a regression-tested change requires otherwise.
2. **Generated output** — `paste-into-routeros-terminal.txt` and RouterOS source; when Telegram/panel mode is selected, a private `install.sh` containing the initial config payload and expected SHA-256 hashes for the matching application assets. The generated installer is sensitive and must not be shared publicly.
3. **Canonical server assets** — `server-deployment/send-backup.php`, `panel.css`, and `panel.js`. They contain application code only, not customer-specific secrets. The Windows generator embeds matching templates and computes hashes; the generated bootstrap downloads the GitHub copies and aborts if any hash differs.
4. **Private server config and state** — `/etc/atd-mikrotik-backup-studio/config.php` stores first-run constants with restrictive permissions; `/var/lib/atd-mikrotik-backup-studio/state.php` stores delivery history and panel-password changes. Neither is overwritten by routine code updates.
5. **Server runtime** — application under `/opt/atd-mikrotik-backup-studio`, private config/TLS material under `/etc/atd-mikrotik-backup-studio`, state under `/var/lib/atd-mikrotik-backup-studio`, and dedicated services `atd-mikrotik-backup-php.service` and `atd-mikrotik-backup-tls.service`. The runtime uses an ATD-specific public port and does not edit existing Nginx/Apache configuration.
6. **Updater** — `sudo atd-mikrotik-backup-update` downloads and stages application code, validates PHP syntax, backs up previous code, replaces only versioned assets, and restarts only the ATD PHP service. It does not replace private config, state, uploaded backups, TLS keys, or assigned ports.

## Secret handling

- Never commit bot tokens, relay tokens, panel-password hashes/salts tied to a customer, customer hostnames/IPs, SFTP paths, or generated customer configuration to public GitHub.
- The generated `install.sh` carries a base64-encoded config payload. Base64 is not encryption; keep the file private and transfer it securely.
- Store server-side secrets in `/etc/atd-mikrotik-backup-studio/config.php`, readable by the ATD service group but not by other users.
- Escape values for their target language and validate paths. Never use `chmod 777` or broad permission changes to bypass errors.

## Host safety

- Use ATD-owned paths, services, and ports. Do not stop/restart unrelated services or modify Nginx/Apache configuration.
- Do not change host-wide firewall rules automatically. Print the selected public port and explain that the operator/provider may need to allow it.
- Install only missing prerequisites. Preserve assigned ports and private configuration on re-runs.
- If a conflict or ambiguous resource ownership is detected, stop and explain rather than making destructive changes.

## Release and compatibility rules

- The generator's embedded PHP/CSS/JS templates must match the canonical files in `server-deployment/`; CI checks this invariant.
- Generated bootstraps verify SHA-256 hashes for the panel assets and abort if the package and GitHub assets do not match.
- Do not change the tested SFTP code merely to reorganize files. Regression-test SFTP-only mode after changes.
- A feature is not complete until a generated installer has been exercised on a clean Linux test server and RouterOS/SFTP/Telegram flows are verified.

## Current status

This document describes the intended architecture, not a claim of production readiness. See `docs/TEST-REPORT.md` for the distinction between CI/static checks and real-server tests.

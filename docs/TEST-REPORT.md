# Test report and current verification status

Last reviewed: 2026-10-25.

## Verified from repository inspection
- The repository contains the PHP relay/panel endpoint, CSS, JavaScript, server install helper, Windows launcher/build BAT files, documentation, and a source-check workflow.
- The optional server update entry point is available as:
  `sudo bash install-server.sh --update /absolute/path/to/installed/panel`
- The updater downloads the allowlisted PHP/CSS/JS files over HTTPS, stages them before touching live files, creates a timestamped backup, carries matching customer-specific constants forward, and checks PHP syntax before/after replacement.
- SFTP remains a separate workflow and is not modified by the updater.

## Not yet verified
- No end-to-end execution of the updater on a real Linux web server has been recorded in this report.
- Telegram delivery, bot token/Chat ID correctness, backup-file stability detection, and the panel login flow still require a real test.
- The original `windows-client/Generate-MikroTik-Backup.ps1` and `windows-client/AmirTaheri-Backup.ico` are not currently present in the GitHub tree. As a result, the repository cannot yet be claimed as a complete reproducible Windows EXE source package.
- The GitHub update option has not yet been wired into the original EXE-generated server script because that original PowerShell generator source is missing from the repository. The standalone server update helper is committed, but it is not proof of complete EXE integration.

## Required release gate
Do not label this release production-ready until the exact PowerShell generator/icon are restored, the generated installer invokes the update option, and tests pass on a clean test server for both SFTP-only and Telegram/panel modes. Verify that updates preserve all customer-specific values and that rollback works after a deliberately invalid staged PHP file.


## Additional checks performed (2026-10-25)
- Registered the full integrated PowerShell generator source at `windows-client/Generate-MikroTik-Backup.ps1`; source includes the server PHP/CSS/JS generation and the post-install GitHub update command.
- Fixed the generated server installer so it detects the web worker account before applying file ownership, and prints an example HTTPS panel URL after installation.
- Added a `runuser`-first permission check with a `sudo` fallback, avoiding a hard dependency on `sudo` when `runuser` is available.
- Extracted the embedded generated PHP with test-only placeholder values: `php -l` passed.
- Extracted the generated server installer: `bash -n` passed.
- Ran the generated PHP endpoint on PHP's local development server; the panel login page returned HTTP 200 and rendered the Persian login heading.
- Not tested: a real RouterOS device, live SFTP transfer, real Telegram bot delivery, real HTTPS virtual host, production PHP-FPM user/ACL setup, or a complete live GitHub update against an installed server.
- Compatibility safeguard: the current GitHub updater intentionally skips replacing the generated PHP when it detects the generator's legacy constants/state schema. It updates CSS/JS only in that case, protecting customer-specific constants and state. A schema-compatible PHP migration is still required before PHP code can be safely updated for those installations.

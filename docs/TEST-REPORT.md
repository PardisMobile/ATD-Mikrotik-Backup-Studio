# Test report and current verification status

Last reviewed: 2026-10-25.

## Repository-level implementation review
- The Windows generator creates a customer-specific `install.sh` in Telegram/Panel mode. It embeds only the first-run private config payload; panel assets are downloaded from GitHub at install time.
- The generated installer resolves one immutable `main` commit SHA and downloads all server assets from that exact commit, avoiding mixed snapshots from separate mutable `main` requests. Independent SHA-256 manifest/signature verification is not yet implemented.
- Newly generated RouterOS scripts use the original SFTP-only flow and never call the panel or Telegram. The generator persists the chosen backup times in the private config. The Cron helper schedules server-side scans after those times, with a configurable delay and a six-minute retry window. The single Telegram connection test sends the newest existing backup file using sendDocument; per-file send buttons and text-only test messages are not used. Installer/updater cleanup removes legacy worker/scanner units and timers.
- The runtime installer reads the selected public port from the generated configuration, checks for conflicts on a clean install, preserves the installed port on re-runs, and aborts if a new package expects a different port.
- PHP sessions use an ATD-owned writable directory, and panel session cookies are explicitly marked Secure because TLS terminates at the local socat proxy.
- The original RouterOS identity-based backup filename behavior is preserved; the scanner skips unsupported filenames rather than modifying the SFTP core.
- Private configuration lives at `/etc/atd-mikrotik-backup-studio/config.php`; delivery state and session data live under `/var/lib/atd-mikrotik-backup-studio`.
- A dedicated updater is available as `sudo atd-mikrotik-backup-update`; it stages and syntax-checks app code, backs up prior app files, and targets only the ATD PHP service.

## Automated checks
- GitHub Actions run Bash syntax checks, ShellCheck, PHP syntax checks, source/template consistency tests, bootstrap syntax checks, key URL/port/session invariants, and PowerShell parser validation.
- The latest CI status must be checked against the final commit before release. The source workflow now asserts immutable-commit snapshot behavior and updater staging order.
- Static validation does not establish that a real server install or update succeeds end to end.

## Not yet verified on a real server
- A clean Linux VM install using the exact generated `install.sh` and private configuration.
- Re-running the installer and verifying every config value, assigned port, state entry, and backup file remains unchanged.
- Updating PHP/CSS/JS from GitHub and validating rollback after a deliberately invalid staged file.
- A real MikroTik RouterOS 7 scheduled backup and SFTP transfer.
- Actual Telegram bot file delivery, duplicate-send behavior, schedule-triggered Linux Cron retries, schedule-setting changes from the panel, and panel password-change flow.
- Certificate trust behavior for RouterOS and browser access on a public server with the intended domain/certificate.
- Compatibility with all Linux distributions and existing host firewall/provider policies.

## Release gate
Do not describe the project as production-ready until the latest CI checks pass and the full install/update/SFTP/Telegram flow has been exercised on a disposable Linux server. Record the exact commit and the actual test environment in any final release report.

## Review of main after password-policy synchronization (2026-10-25)

- Reviewed the Windows generator and canonical PHP panel on `main`: the generator enforces a minimum of 8 characters, retries after too-short input or confirmation mismatch, and the embedded PHP UI/validation uses the same 8-character policy.
- Reviewed the latest main workflow definition: it covers PHP lint for both canonical and embedded PHP, JavaScript/CSS parsing, canonical asset parity, generated bootstrap Bash syntax, key behavior invariants, installer/updater Bash checks, ShellCheck, and Windows PowerShell parsing.
- The GitHub connector returned no combined status checks and no PR-triggered workflow runs for the latest direct-to-main commit. This is **unknown/not verified**, not a passing CI result. Check the Actions page for the push-triggered workflow run before release.
- Project handoff context was added to the README under “Project Context for Continued Development” so future sessions can recover the current branch policy, implementation architecture, and verification limits.
- Branch comparison still reports `fix/telegram-schedule-and-connection-test` as 25 commits ahead and 9 behind current `main`, with the common base at `15022946ec458758eff516968ee1cfcce7f673e3`. Tree-level file comparison shows the main implementation already contains the reviewed Cron/Telegram/install/update/workflow behavior plus the newer password policy and generator guidance. Do not delete the extra branch until its unique commits are individually reconciled and cleanup is possible.


## Follow-up review (2026-10-25)

- Fixed the generated bootstrap to resolve one GitHub commit SHA before downloading assets and pass that same SHA to the runtime installer.
- Fixed runtime installer updater download to use the same pinned commit when invoked from the generated bootstrap; manual invocation resolves a commit before downloading the updater.
- Fixed updater asset downloads to use a single immutable commit and deferred legacy service cleanup until downloaded assets pass validation.
- Updated CI invariants and GitHub update documentation to reflect this architecture.
- Still required: inspect the push-triggered workflow result for the newest commit, execute the generated PowerShell on Windows, and run clean-install/reinstall/update/rollback tests on a disposable Linux VM. No real-server end-to-end test has been performed in this review.

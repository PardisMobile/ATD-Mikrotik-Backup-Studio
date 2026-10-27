# Test report and verification status

Reviewed: 2026-10-28. This report separates repository/source checks from live-host checks. Update it after any release or server deployment.

## Architecture reviewed

- Windows PowerShell generator: collects user settings, writes a RouterOS SFTP backup/scheduler script and a private-config `install.sh`; Linux server assets are fetched from one immutable Git commit.
- Linux runtime: PHP panel code under `/opt/atd-mikrotik-backup-studio`; private configuration under `/etc/atd-mikrotik-backup-studio`; delivery state and sessions under `/var/lib/atd-mikrotik-backup-studio`; root-owned project helpers under `/usr/local/sbin`; project schedules under `/etc/cron.d`.
- Panel actions: PHP authenticates and handles CSRF-protected POSTs. `panel.js` sends same-origin `fetch` requests. The Telegram Test AJAX contract is JSON `{ok,message}` without page reload; the test sends the newest `.backup` file through Telegram `sendDocument`.
- Delivery: Linux Cron invokes the PHP scanner. The server checks file size stability, tracks sent-file SHA-256 state, and retains the existing delivery/deduplication behavior.
- Historical note (superseded): prior implementation shared one zone selection between Linux display and Cron `CRON_TZ`. Current code stores these independently; the Linux helper validates the IANA zone and calls `timedatectl`, while Cron reads `_cron_timezone`. A live timezone change is not part of the no-side-effect validation.
- Updater: pins the updater and assets to one resolved commit, stages/syntax-checks before activation, snapshots ATD-owned files and relevant service states, applies within a lock/rollback boundary, and writes the installed-source marker only after required checks.
- A post-deployment rollback audit found that an earlier updater snapshot listed `/etc/sudoers.d/atd-panel-update`, while the installer/updater actually writes `/etc/sudoers.d/atd-mikrotik-backup-panel-update`. The source now snapshots the exact file, CI asserts that the installer and rollback paths agree, and the corrected live snapshot was verified. Rollback failure injection remains reserved for a disposable host.
- The earlier updater also ran `systemctl enable --now cron.service`, although the host Cron service was already active and enabled. Its effective state stayed unchanged, but the command could mutate shared SysV/systemd state. The current installer/updater instead require pre-existing active+enabled host Cron, abort with `HOST_CRON_NOT_READY` otherwise, and only write ATD-owned `/etc/cron.d` entries. CI guards against the old package-install and enable/start commands.
- The user's follow-up screenshot and live PHP service journal established the 404 root cause: `panel.js` used `form.action`, but every POST form contains a hidden `name="action"` input, so the browser resolved the URL as `/[object%20HTMLInputElement]`. This broke Telegram Test, Linux timezone, and other AJAX POSTs. The journal showed repeated exact 404s for that route.
- The same audit found the update checker tested `is_executable()` on root-owned mode-0750 helpers and `is_readable()` on root-only sudoers files while PHP runs as `atdbackup`; these checks always fail by design, even though `sudo -n -l` confirms the restricted commands are allowed. This caused the panel to show “Update available” on the installed current commit.
- The current correction uses the form's `action` attribute safely, checks restricted privileges through `sudo -n -l`, separates Linux timezone from Cron timezone, makes the UI terminal-only for updates, and stops installers/updaters from creating panel Workers or deleting/disabling existing units. The terminal updater preserves existing systemd unit files.
- The final change was committed directly to `main` as `48654156fe908136aec96df5f0f1b851fb65f8dc`. Both GitHub Actions workflows passed. The official terminal updater bootstrapped and installed that exact commit, with a pre-update snapshot at `code-backup-20261027223907`.
- Post-update, the installed-source marker matched `48654156fe908136aec96df5f0f1b851fb65f8dc`; PHP lint, helper shell syntax, both sudoers syntax checks, and both local panel HTTP endpoints passed (200). Installed PHP/JS/CSS SHA-256 values matched the source. ATD PHP/TLS and host Cron remained active/enabled. System timezone stayed `Etc/UTC` and the project Cron entry stayed `CRON_TZ=UTC`. The updater output contained no generic Cron enable/start operation.
- The panel updater helper file was already present in the pre-update snapshot and was refreshed by the official updater. No panel-triggered updater was invoked: its systemd unit reports `LoadState=not-found` and `ActiveState=inactive`. No worker process was started. This is a file-level project helper, not a running worker.

## Repository/source checks

- The local checkout is on `main`; the first docs/deployment commit was `dbbf64ffa832fbe2c8725df82b062b834e9bdc36`, followed by report-only commit `8482b742c8c08aa46a789ef2f80a33f4cafbb45e`.
- `node --check server-deployment/panel.js`: passed using the bundled Node runtime.
- `bash -n` for installer, updater, Cron helper, and timezone helper: passed.
- `git diff --check`: passed for the documentation changes.
- The two GitHub Actions runs associated with `dbbf64f` completed successfully.
- Both GitHub Actions workflows for report-only commit `8482b74` also completed successfully.
- Both GitHub Actions workflows for updater-fix commit `bd21406` completed successfully.
- Local PHP CLI, ShellCheck, PowerShell, and `tinycss2` were unavailable in this Mac runtime. PHP syntax was instead checked with the installed server PHP CLI after deployment. Local CSS parsing, ShellCheck, and PowerShell parsing are not claimed as direct local passes.
- A syntax check or source review does not prove browser behavior, server update rollback, RouterOS SFTP, or Telegram delivery.

## Live-host checks before update

Read-only SSH to `vip4.nahagebad.net` succeeded. On 2026-10-28 the host reported Ubuntu 22.04, 2.4 GB free on `/`, and `/opt/atd-mikrotik-backup-studio` as the PHP document root. PHP backend `127.0.0.1:6669` and ATD TLS endpoint `:24443` both returned HTTP 200. ATD PHP/TLS and generic Cron services were active; Cron was enabled.

The installation has no local Git checkout. Before update its recorded source commit was `61b3858b9c4b3a03e02bc48465e9220af50df0d7`. The PHP, JS, and CSS app assets matched that source, but `panel.js`, the PHP AJAX response condition, and terminal updater were behind GitHub `main`. The deployed Cron and timezone helpers already matched `main`.

The terminal updater completed successfully for `dbbf64ffa832fbe2c8725df82b062b834e9bdc36`, then was rerun for report-only commit `8482b742c8c08aa46a789ef2f80a33f4cafbb45e`. Both runs succeeded and preserved application assets, exercising repeat-update behavior. Root-only snapshots were stored under `/var/lib/atd-mikrotik-backup-studio` (first `code-backup-20261027221944`; second `code-backup-20261027222326`). After the first run, app/helper SHA-256 digests matched source, PHP lint passed, and both backend/TLS endpoints returned HTTP 200. ATD PHP/TLS and generic Cron remained active and enabled; no legacy ATD worker/scanner unit was present. No panel-triggered transient updater unit was started.

A later audit found the updater's rollback snapshot used the wrong name for the existing panel updater sudoers file. Commit `bd21406f5efa35461afa2bb2068d93ebb32a865f` corrected it and added a CI invariant. The final deployment snapshot at `/var/lib/atd-mikrotik-backup-studio/code-backup-20261027223029/snapshots.list` contains `/etc/sudoers.d/atd-mikrotik-backup-panel-update`; its saved copy compared byte-for-byte with the pre-update file and retained root:root 0440. The updater completed, installed-source marker matched `bd21406`, PHP lint passed, both HTTP endpoints returned 200, and the prior config/state/four-backup manifest remained unchanged. No rollback failure was injected on production.

Before/after digests for private config and delivery state were identical. The backup directory still contained four `.backup` files and its aggregate manifest was unchanged. The Cron timezone remained UTC and the system zone remained `Etc/UTC`. The updater invoked `systemctl enable --now cron.service`; Cron was already active/enabled before this operation and remained so afterward. No unrelated panel or service definition was intentionally modified.

The observed Linux zone was `Etc/UTC`; Cron used `CRON_TZ=UTC`. No configured or saved panel zone override was present, so the code's `UTC` default agrees with both. No timezone change was made.

## Tests requiring a later controlled run

- GitHub Actions for this report update (the two workflows for `4865415` passed; this edit will run the same workflows again).
- Failure-injection rollback test on a disposable host. Do not test rollback by injecting failure on production.
- Authenticated browser testing of panel navigation, successful timezone action, update status, and search/pagination.
- Applying a different timezone would change host-wide timezone and Cron behavior; only do so with an explicit operational requirement and suitable window.
- Telegram Test delivers the newest backup file to the configured chat. It has not been run; obtain explicit approval before real delivery.
- RouterOS backup upload/SFTP and full end-to-end delivery were not tested in this review.

## Release gate

Do not call the complete production flow verified until the final commit's CI passes and the server update, authenticated panel interactions, timezone path, RouterOS SFTP upload, and authorized Telegram delivery have been exercised with their real results recorded here. A successful updater run alone is not proof of Telegram delivery or rollback under injected failure.

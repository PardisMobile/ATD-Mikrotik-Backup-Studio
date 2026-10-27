# Test report and verification status

Reviewed: 2026-10-28. This report separates repository/source checks from live-host checks. Update it after any release or server deployment.

## Architecture reviewed

- Windows PowerShell generator: collects user settings, writes a RouterOS SFTP backup/scheduler script and a private-config `install.sh`; Linux server assets are fetched from one immutable Git commit.
- Linux runtime: PHP panel code under `/opt/atd-mikrotik-backup-studio`; private configuration under `/etc/atd-mikrotik-backup-studio`; delivery state and sessions under `/var/lib/atd-mikrotik-backup-studio`; root-owned project helpers under `/usr/local/sbin`; project schedules under `/etc/cron.d`.
- Panel actions: PHP authenticates and handles CSRF-protected POSTs. `panel.js` sends same-origin `fetch` requests. The Telegram Test AJAX contract is JSON `{ok,message}` without page reload; the test sends the newest `.backup` file through Telegram `sendDocument`.
- Delivery: Linux Cron invokes the PHP scanner. The server checks file size stability, tracks sent-file SHA-256 state, and retains the existing delivery/deduplication behavior.
- Timezone: panel state/config selects the Linux display and Cron `CRON_TZ`; the root-owned helper validates the IANA zone and calls `timedatectl`. A real timezone application changes host timezone and was not part of the read-only audit.
- Updater: pins the updater and assets to one resolved commit, stages/syntax-checks before activation, snapshots ATD-owned files and relevant service states, applies within a lock/rollback boundary, and writes the installed-source marker only after required checks.

## Repository/source checks

- The local checkout was `main` at `2a0d2f458020174c9605df210c78c76c0667d006` during review.
- `node --check server-deployment/panel.js`: passed using the bundled Node runtime.
- `bash -n` for installer, updater, Cron helper, and timezone helper: passed.
- `git diff --check`: run after the documentation edits.
- Local PHP CLI, ShellCheck, PowerShell, and `tinycss2` were unavailable in this Mac runtime. Those checks are not claimed as local passes. The latest GitHub Actions result must be checked on the pushed commit.
- A syntax check or source review does not prove browser behavior, server update rollback, RouterOS SFTP, or Telegram delivery.

## Live-host checks before update

Read-only SSH to `vip4.nahagebad.net` succeeded. On 2026-10-28 the host reported Ubuntu 22.04, 2.4 GB free on `/`, and `/opt/atd-mikrotik-backup-studio` as the PHP document root. PHP backend `127.0.0.1:6669` and ATD TLS endpoint `:24443` both returned HTTP 200. ATD PHP/TLS and generic Cron services were active; Cron was enabled.

The installation has no local Git checkout. Its recorded source commit was `61b3858b9c4b3a03e02bc48465e9220af50df0d7`. The PHP, JS, and CSS app assets matched that source; `main` had advanced to `2a0d2f458020174c9605df210c78c76c0667d006`. The panel JS, PHP AJAX response condition, and terminal updater were therefore behind `main`. The deployed Cron and timezone helpers matched current `main`.

The observed Linux zone was `Etc/UTC`; Cron used `CRON_TZ=UTC`. No configured or saved panel zone override was present, so the code's `UTC` default agrees with both. No timezone change was made.

## Tests requiring a later controlled run

- GitHub Actions for the final pushed commit, including PHP lint, JS/CSS checks, generated-bootstrap invariants, ShellCheck, and Windows PowerShell parser.
- Real terminal updater run and post-update SHA/commit-marker/HTTP checks. Do not test rollback by injecting failure on production; use a disposable host.
- Authenticated browser testing of panel navigation, AJAX, timezone form, update status, and search/pagination.
- Applying a different timezone would change host-wide timezone and Cron behavior; only do so with an explicit operational requirement and suitable window.
- Telegram Test delivers the newest backup file to the configured chat. It has not been run; do not run without explicit user approval for the real delivery.
- RouterOS backup upload/SFTP and full end-to-end delivery were not tested in this review.

## Release gate

Do not call the complete production flow verified until the final commit's CI passes and the server update, authenticated panel interactions, timezone path, RouterOS SFTP upload, and authorized Telegram delivery have been exercised with their real results recorded here. A successful updater run alone is not proof of Telegram delivery or rollback under injected failure.

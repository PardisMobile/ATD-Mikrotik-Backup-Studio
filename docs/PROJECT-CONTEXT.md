# Project Context — ATD MikroTik Backup Studio

## Non-negotiable architecture and operating rules

These rules are the project's source of truth. Future implementation, refactoring, installer, updater, UI, and documentation changes must preserve them.

### 1. Existing working core
- The baseline is MikroTik Backup Studio v3 with working RouterOS 7 scheduled backups over SFTP.
- Preserve the working backup core. Add the server panel and optional server-side Telegram delivery around it; new RouterOS scripts must not depend on Telegram HTTP/relay calls.
- Do not regress already verified/frozen functionality or repeat completed work without a demonstrated reason.

### 2. Initial Excel/EXE configuration is authoritative
- The Windows EXE/generator collects the configuration variables the user needs to provide for this project.
- Variables that govern server setup and Telegram delivery are initialized from those user-provided values and must remain stable after first setup.
- Treat the first-run configuration as persistent configuration/state, not as disposable generated code.
- UI, CSS/JS, PHP implementation, and other application-code updates must not silently reset, overwrite, or require re-entering the original values.
- Keep secrets out of the public GitHub repository. Handle and store them on the user's server with restrictive permissions.

### 3. One-command server bootstrap from the generated output
- The EXE must produce a server-specific output/package that carries the initial configuration needed to bootstrap that installation, as well as the RouterOS-side output.
- The user transfers the server bootstrap output to the Linux server, copies/pastes the single provided command, and presses Enter.
- That command must automatically configure the server using the initial values collected by the EXE: create required directories/files, install only missing prerequisites, configure the ATD panel, the server-side Telegram scanner Cron entries, and fetch shared/versioned application components from GitHub when needed.
- The user must not be asked to manually transfer or construct individual PHP, CSS, JavaScript, or other internal panel files.
- The install command and its prerequisites must be clearly identified in the generated output and in the README. Keep the workflow simple for non-technical users.

### 4. Safe, configuration-preserving updater
- Provide a separate update mechanism for application/UI/code changes.
- Updates must preserve the original first-run configuration and secrets, panel credentials, existing uploaded backups, delivery state/history, and other persistent data.
- Separate application code from persistent configuration and runtime data. Updates may replace versioned code/assets but must not overwrite user configuration or delete data.
- Updates should be versioned, validate downloads and syntax before activation where feasible, and fail safely with a useful message. Do not claim an update succeeded unless its result confirms success.

### 5. Never damage unrelated services on the Linux host
- Installer, updater, and uninstaller (if present) must be isolated and conservative.
- Do not stop, restart, overwrite, reconfigure, or remove unrelated services, reverse-proxy configurations, ports, firewall rules, users, directories, certificates, or applications.
- Detect conflicts before making changes. Use ATD-specific paths, service names, ports, and configuration files. Do not edit existing Nginx/Apache configuration as a shortcut.
- Install only missing dependencies; do not blindly reinstall packages or modify a working host setup.
- Any change outside ATD-owned resources must be strictly necessary, narrowly scoped, and explicitly documented. On conflicts or uncertain ownership, stop and explain instead of making destructive changes.

### 6. Verification and reporting
- Test the full path, not just isolated shell syntax: generated EXE/package configuration -> one-command server install -> RouterOS SFTP upload -> panel login/listing -> optional Telegram delivery -> code/UI update preserving configuration and backups.
- Test re-running the installer and updater for idempotence and preservation.
- Clearly distinguish static/CI checks from installation tests performed on a real Linux server. Never report unperformed tests as passed.

## Required end-user experience

1. User enters the initial values once in the Windows EXE.
2. EXE creates the RouterOS configuration/output and a server bootstrap package/command.
3. User runs the one provided command on Linux.
4. Server files and services are created automatically; shared code can be downloaded from the project's GitHub repository.
5. Later code/UI updates can be applied without changing initial values, secrets, uploaded backups, or unrelated host services.

Any proposed implementation that contradicts these rules is incorrect, even if its individual script appears to work.


---

## Historical optimization request and handoff notes — 2026-10-26

This section preserves requirements and review notes from the 2026-10-26 handoff. The verified status below and later dated entries supersede stale statements in this historical checklist.

### User's priorities / hard constraints
- The currently deployed backup/SFTP/Telegram flow is working. Treat this as optimization, not a rewrite.
- **Do not change the core Telegram sending logic** or disrupt bot-token/Chat-ID handling, retries, sent-file deduplication, backup discovery, SFTP upload, RouterOS scheduling, saved settings, or existing installations.
- Before modifying commands for RouterOS or Ubuntu/Linux, verify them against the relevant official MikroTik RouterOS and Ubuntu/Linux documentation. Do not assume a command or time-zone name is supported by every RouterOS version.
- Inspect the actual current `main` source and CI before proposing or editing. Never claim real-server tests were performed unless they were.
- Prefer a simple, reversible implementation. Avoid adding a complicated updater or risking HTTP 500 errors.
- The user requested an audit before implementation in that earlier handoff. That sequencing instruction has since been superseded by the current request to complete the audit, fixes, and deployment.

### Windows generator requirements
- Review and improve question wording, order, colors, contrast, validation, and brief help text so non-technical users understand each prompt.
- The time-zone question must have exactly five choices:
  1. Iran — `Asia/Tehran`
  2. India — `Asia/Kolkata`
  3. Germany — `Europe/Berlin`
  4. USA — `America/New_York`
  5. Manual — user enters an IANA time-zone name, e.g. `Asia/Dubai` or `America/Los_Angeles`
- Label option 4 simply “USA”; do not add “Washington DC”.
- The Windows generator stores the selected zone in the private server configuration for panel/Cron defaults. Installation does not silently change the host-wide time zone. In panel Settings, an administrator can explicitly apply a zone to Linux and Cron with the restricted root-owned `timedatectl set-timezone` helper; this does not set the system clock or alter NTP. RouterOS scheduling remains independent and is outside the panel timezone change.
- Keep existing backup frequency, custom times, SFTP settings, public port, panel password, and local-file-retention prompts/behavior intact.
- The Windows generator's responsibility is to collect customer-specific values and produce the RouterOS output plus `install.sh` containing only the private installation configuration. Do not embed duplicate PHP/CSS/JS/Cron application assets in the PowerShell generator. The generated `install.sh` must fetch the versioned server assets from GitHub using one immutable commit snapshot; the server installer/updater owns installing and updating those assets.

### Panel/UI requirements
- Display the Linux server's current date/time and detected system time zone.
- Clearly explain that Linux Cron does not change the RouterOS scheduler; configured schedule times must be aligned by the administrator.
- Provide the five-option time-zone selector directly below the warning, including Manual with an example.
- A selected time zone affects Linux host presentation and the ATD Cron schedule through `CRON_TZ`. The current project configuration is one global schedule, not per-router timezone conversion.
- Improve lightweight CSS animation and visual consistency.
- Avoid full-page refresh for normal panel actions where safely feasible; preserve POST/CSRF/redirect/session behavior and ensure failures are visible. Do not use a fragile generic AJAX replacement that silently breaks forms or navigation.
- Show at most 20 backup files per page; retain accurate total counts/status and implement server-side search and pagination. Sorting was requested for review but must not be claimed as implemented unless it exists and works.
- Footer must read “Code by Amir Taheri”, linked to `https://wa.me/pardis.mobile.kish` (user confirms this link works).

### In-panel updater
- The existing standalone update method should remain supported; user wants a simple in-panel way to run it if safely possible, without opening a terminal.
- Root privileges are needed for some server updates. Do not expose arbitrary root command execution. If an in-panel updater is implemented, use a narrowly scoped, root-owned helper, strict permissions, authentication/CSRF, single-run locking, clear status/logs, validated downloads/syntax, configuration/data preservation, and a safe failure/rollback strategy.
- Ensure the updater can update itself safely and that the generated install package actually installs the same helper. Do not call it safe or complete until these paths have been tested.
- Do not overwrite secrets, Telegram state, uploaded backups, or unrelated Linux services/configuration.

### Latest known attempted changes and audit warnings
The following changes were attempted directly on `main`; re-fetch them before acting:
- `windows-client/Generate-MikroTik-Backup.ps1`: added the five time-zone choices and improved prompts/colors. Latest known generator commit: `5a66cec7042ef44714575eb137edf3d84d85ba23` (SHA may no longer be current if later commits were added).
- `server-deployment/send-backup.php`: attempted server clock/time-zone UI, Manual input, pagination/search, footer link, AJAX-friendly refresh, and an update control/status endpoint.
- `server-deployment/cron-helper.sh`: attempted to read a saved zone and write `CRON_TZ` into the generated cron file.
- `server-deployment/panel.js`: attempted generic AJAX form submission/navigation, live clock, search, and update status polling.
- `server-deployment/panel.css`: added styles for the warning, selector, pagination, animations, and responsive layout.
- `server-deployment/install-standalone.sh` and `server-deployment/update-standalone.sh`: attempted to install a restricted root-owned helper for in-panel updates.

**Do not assume these attempted changes are production-ready. Audit them carefully.** Important potential issues to investigate:
1. The Linux panel's time-zone choice may only change Cron's interpretation of saved times; that does not automatically synchronize those times with the RouterOS scheduler.
2. The panel's time-zone action may require a correctly installed worker/helper to apply Cron changes; verify save/rollback behavior and permissions.
3. The generic AJAX code may replace the whole app shell and may not preserve all event handlers, form semantics, pagination/search state, or login/redirect behavior.
4. Verify the live clock actually advances and represents the server clock accurately.
5. Confirm the 20-file pagination is server-side and search totals, empty states, stats, and navigation remain correct.
6. Audit the in-panel updater's sudoers rule, systemd-run invocation, helper ownership/modes, self-update behavior, status JSON, error handling, and whether a real installation actually has all prerequisites.
7. The updater helper was added to installer/updater scripts in separate edits; verify the current code and generated package do not diverge.
8. The generator embeds canonical server files. A previous attempt to synchronize large embedded templates caused duplicated/malformed trailing content in the PowerShell file. A later commit truncated the malformed tail, but this must be checked against the original generator's expected end and all CI invariants before trusting it. Do not blindly replace embedded templates again.
9. Verify the generated PHP config carries the chosen time zone correctly; confirm constant names and default-state logic match across generator, PHP, cron helper, installer, and updater.
10. The panel's scheduled Telegram logic is frozen: preserve its existing baseline/dedup/retry behavior.


### Applied follow-up fix — 2026-10-27
- `server-deployment/panel.js`: the in-panel `update_start` form now uses the existing AJAX submission path. This allows the UI to detect the `UPDATE_STARTED` flash response and begin polling `?ajax=update_status`; previously the submit handler deliberately let this form use a native navigation, so the status poll never started. Time-zone submission remains native as intended.


### Applied follow-up — Telegram test diagnostics (2026-10-27)
- `server-deployment/send-backup.php`: failed Telegram document uploads now retain the API's HTTP status and `description` (or the cURL transport error) in the delivery state and test result, instead of returning only a generic `TELEGRAM_SEND_FAILED`. This makes the actual cause of an HTTP 404 or other Telegram API response visible for diagnosis; it does not represent a live Telegram send test.

### Last known CI state
After the latest known generator fix, the GitHub checks reported success for:
- `powershell-parse`
- `php-lint`
- `shell-check`
- `shell-validation`

These are static/CI checks only. They do not prove a live Ubuntu upgrade, RouterOS command compatibility, Telegram delivery, SFTP upload, AJAX usability, or in-panel update/rollback works on the user's server.

### Safe next-chat procedure
1. Fetch current `main`, current commit SHA, all changed files, and latest CI results.
2. Compare the generator against the last known-good version; verify it only collects user configuration, generates RouterOS output, and writes a private `install.sh`.
3. Verify `install.sh` downloads the canonical server assets from one immutable GitHub commit and that no duplicate panel/Cron templates remain embedded in the generator.
4. Review relevant official MikroTik and Ubuntu documentation for every RouterOS/system command used.
5. Report in Persian, concisely: what is already correct, what is incomplete or risky, what CI proves, what remains untested, and a prioritized safe recovery plan.
6. Do not commit further changes until the audit identifies a safe plan and the user authorizes implementation.


### Implemented panel enhancements — 2026-10-26
- Panel sections: Dashboard, Backups, Telegram, and Settings. The UI continues to render server-side; navigation hides/shows grouped sections without changing action endpoints or CSRF handling.
- A live Linux date/time clock appears in the top bar. The settings card also shows the detected system zone.
- The timezone selector applies the selected zone to the Linux host only after explicit user submission, using a root-owned helper that accepts no command-line arguments and validates a zone against `/usr/share/zoneinfo`. The same selected zone remains the `CRON_TZ` zone. This does not change the actual system clock, NTP configuration, or RouterOS settings.
- The panel footer already contains “Code by Amir Taheri” linked to the approved WhatsApp URL; do not duplicate or rewrite it unnecessarily.

- Backup listing supports server-side sort by filename (ascending), file size (descending), and modification time (newest first). Sort selection is preserved across pagination and search.

- Settings includes an explicit read-only GitHub update check. It compares the latest main commit SHA with the locally recorded installed source commit, and never installs updates without user action. Older installs with no recorded SHA are reported as unknown and require a one-time updater run to establish the baseline.
- Time-zone and panel-update forms use native POST/redirect rather than the AJAX fragment loader, and redirects use SCRIPT_NAME to avoid PHP_SELF path ambiguity.

- Successful install output shows the detected server IP URL and, when the Windows generator's SFTP host is a DNS name, a second hostname URL using the same public port. The SFTP host is used only as a hostname candidate because the generator instructs users to point SFTP at the same Linux server. DNS resolution and provider firewall reachability remain the operator's responsibility.

- The terminal updater installs the independent system-time-zone helper and validates its sudoers rule immediately after PHP health validation, before Cron recovery. Failed Cron repair rolls back panel assets; installed-source-commit is written only after the full successful path as a plain SHA line.


### User-confirmed known-good deployment baseline — 2026-10-27
- **Commit `13cf0dd5fefcede571b7d6af66b1c9c2910093fc`** is explicitly identified by the user as the commit from the initial server installation where Telegram was working correctly.
- Treat this commit as the known-good server-installation/Telegram behavior reference when auditing later changes. Do not rewrite, “improve,” or regress the Telegram test/send behavior without first comparing against this baseline and getting clear user approval for a behavior change.
- The later commit `3615c0e0924c09b9844a55f48f818916bbcd8166` (“Handle Telegram test JSON without page refresh”) is also relevant to the panel's AJAX response path, but it does **not** replace the user-confirmed initial-install baseline above.
- Preserve Telegram delivery settings, server-side sending, file discovery/stability checks, deduplication/retry behavior, and the AJAX test button behavior. Record any future Telegram-related code or test changes here, with the commit and explicit test status. Never describe unperformed live Telegram delivery as tested.


### Preserve Telegram test AJAX contract — 2026-10-27
- User explicitly requests that the Telegram Test button remain AJAX-based without a page reload, while preserving the behavior of the known-good initial server install commit `13cf0dd5fefcede571b7d6af66b1c9c2910093fc`.
- Verified in current `main`: `panel.js` submits `telegram_test` through `fetch()` with `X-Requested-With: XMLHttpRequest`, parses JSON, displays the returned message, and exits without replacing/reloading the page. `send-backup.php` detects that AJAX header, emits JSON `{ok,message}`, and exits before the normal redirect. This request/response pair is the required contract; keep it intact during updater/timezone work.
- Do not rewrite Telegram sending, settings, file-selection, stability, deduplication, or retry logic as part of the AJAX work. A test button click currently sends the latest backup to Telegram (it is not merely a getMe connectivity probe); retain that established behavior unless the user expressly asks to change it.
- This is source inspection, not a live browser or Telegram-delivery test. Record test results honestly.


### Updater safety audit — 2026-10-27 (historical; follow-up below)
- The initial review found incomplete transaction snapshots, weak failure rollback, and legacy-unit cleanup before adequate state capture. Those findings describe the earlier updater revision only; subsequent commits updated staging, snapshot, rollback, and success-marker handling.
- Preserve the AJAX Telegram Test contract and known-good send behavior documented above. The updater changes do not alter Telegram file selection, sending, stability checks, deduplication, or retries.
- Source-level rollback coverage is not equivalent to a failure-injection test on a disposable Ubuntu host. Do not claim rollback has been exercised unless that test is actually run.


### Updater and generated-asset remediation — 2026-10-27
- Reviewed the updater, installer, Cron helper, timezone helper, PHP panel, JavaScript, and generated Windows bootstrap as a connected update path.
- The old systemd scanner/worker/timer units are obsolete because Telegram scanning moved to the ATD-owned Cron schedule. The updater now performs that migration **after all replacement assets are downloaded and validated**: records each legacy unit's active/enabled state, snapshots the unit definitions, then disables/stops and removes only the known ATD legacy units. If a later update step fails, rollback restores their files and prior active/enabled state. This is intentional migration cleanup, not ordinary stopping of the current app services.
- The updater now serializes runs with a lock; snapshots the versioned app assets, Cron/helper files, timezone and panel updater helpers, sudoers entries, updater executable, installed-source marker, and legacy unit definitions; stops the ATD PHP backend/TLS listener during live asset replacement; and restores prior app service active/enabled state after successful activation or rollback.
- The updater's rollback trap covers later Cron/helper/sudoers/update steps; installed-source marker and success output are committed only after updater self-refresh validates and installs. The panel updater helper is refreshed on update rather than only created when missing.
- Installer and updater now install the cron package only when the relevant service unit is absent, rather than reinstalling it just because the daemon is inactive.
- Corrected the generated PowerShell bootstrap's embedded PHP and JavaScript templates to match canonical server assets. This restores the AJAX Telegram Test contract (panel.js / send-backup.php): no page reload, JSON response handling. Telegram send behavior and RouterOS/SFTP code were not changed.
- CI at the last verification point: Installer checks succeeded; PowerShell parse and shell syntax checks succeeded. Source checks were still running. The GitHub source-check workflow had earlier exposed the generated PHP/JS mismatch; the canonical templates were synchronized afterward.
- These are repository/CI validations, not a live Ubuntu installation or Telegram send test. Do not claim production update/rollback behavior or live Telegram delivery has been verified until tested on the user's server.


### Verified architecture and deployment state — 2026-10-28
- The Windows PowerShell generator collects setup values, creates the RouterOS SFTP backup script/scheduler output, and in panel mode emits a private-config bootstrap. The bootstrap resolves one immutable `main` SHA and fetches versioned Linux assets from that snapshot. RouterOS does not call Telegram or the PHP panel.
- Linux app code is served by PHP's built-in server from `/opt/atd-mikrotik-backup-studio` on a loopback port. A project-owned `socat` TLS endpoint forwards the ATD public port to that backend. Private config is under `/etc/atd-mikrotik-backup-studio`; runtime state/session files are under `/var/lib/atd-mikrotik-backup-studio`; project helpers are under `/usr/local/sbin`; schedules are in ATD-owned `/etc/cron.d` files.
- `send-backup.php` renders the authenticated panel and handles POST actions. `panel.js` uses same-origin `fetch`, CSRF form data, and `X-Requested-With: XMLHttpRequest`; Telegram Test expects JSON `{ok,message}` and does not reload. The Test action sends the newest `.backup` file with Telegram `sendDocument`; it is not a non-delivery connectivity probe.
- Automatic Telegram delivery remains server-side: the Cron scanner finds eligible, stable backup files, uses the existing SHA-256 delivery state to deduplicate, and preserves the known-good send behavior at `13cf0dd5fefcede571b7d6af66b1c9c2910093fc`.
- The updater resolves and pins one immutable commit, stages and validates PHP/Cron/timezone assets, snapshots ATD-owned files/state, serializes updates with a lock, and has a rollback trap. It can restart only the ATD PHP/TLS units and updates the project's own Cron/helper/sudo policy paths. This source review does not establish that rollback has been failure-tested or Telegram delivery succeeded.
- On 2026-10-28, the production app was observed at recorded source commit `61b3858b9c4b3a03e02bc48465e9220af50df0d7`; GitHub `main` was `2a0d2f458020174c9605df210c78c76c0667d006`. The installed app matched its recorded commit; `panel.js`, `send-backup.php`, and the standalone updater were behind `main`. The installed timezone and Cron helper code matched current `main`.
- Live checks on that date confirmed Ubuntu 22.04, PHP backend and TLS endpoint returning HTTP 200, and Linux/Cron zones both UTC (`Etc/UTC`/`UTC`). No live Telegram Test was run because it sends the newest backup file. These observations are point-in-time; update them after deployment and retesting.
- The official terminal updater was subsequently run from immutable commit `dbbf64ffa832fbe2c8725df82b062b834e9bdc36`; the installed marker and application/helper SHA-256 values matched that source afterward. PHP lint and the backend/TLS HTTP 200 checks passed; before/after digests confirmed the private config, delivery state, and four existing backup files were preserved. Cron and ATD services remained active/enabled. The real Telegram send, successful timezone mutation, authenticated browser flow, and failure-injected rollback remain untested; see `docs/TEST-REPORT.md`.


### User clarification — panel/Linux timezone and scope (2026-10-27)
- Do not keep reopening the MikroTik timezone topic. The RouterOS backup script is independent; its timezone behavior is out of scope for this panel issue.
- The panel's Linux timezone must align with the Linux host timezone. Cron has its own timezone setting; when the panel and Cron are both set to Asia/Tehran, there is no timezone offset mismatch to explain or repeatedly warn about.
- The Windows generator already collects the default timezone from the user and places it in the PHP configuration. Do not treat this as an unresolved design question or ask the user to repeat it.
- The user has repeatedly asked for a thorough inspection of the updater before edits, and actual code work—not recurring status-only reports or repeated explanations that the timezone helper is installed late in the updater. Investigate the real execution and rollback paths, identify a reproducible fault, and implement/test a substantive correction.
- Be precise about work: source review is not a fix; do not report completed implementation or live-server validation unless actually performed. The current task is to continue from the actual repo state and deliver code changes after full impact review.


### Generator responsibility clarification — 2026-10-27
- The generator collects the user's setup values and creates the RouterOS script/scheduler output and (panel mode) the customer-specific `install.sh`.
- All versioned server application files (PHP, CSS, JavaScript, Cron helper, and installer components) are sourced from GitHub at installation time, pinned to one immutable commit. Do not duplicate these application files inside the Windows generator.
- The generated `install.sh` contains private customer configuration only; protect it from publication and retain its existing file-permission hardening.
- This refactor removes redundant embedded copies only. Preserve the intentional timezone selector and its generated configuration value.
- Active issue scope remains: panel timezone fix, panel updater fix, and correction of the terminal install/update command so it obtains and installs all required files. Do not expand scope to unrelated generator/UI or Telegram behavior.


### Explicit scope correction — 2026-10-27 (authoritative)
The active work scope is limited to these three defects:
1. Fix the panel/Linux timezone behavior.
2. Fix the panel updater.
3. Fix the terminal installation/update command that was not downloading or installing all required files.

The Windows generator's timezone selection was an intentionally added feature. The user confirms that timezone selection was added to the generator; do not treat it as an accidental regression or remove it as part of this scope. Preserve that feature and its existing choices/configuration behavior.

Do not expand this task into unrelated generator redesign, prompt/color polishing, RouterOS timezone changes, Telegram/RADIUS changes, or other feature work. Preserve existing working behavior. Any changes beyond the three listed defects require a clear technical necessity and should be explained before implementation. Source/CI checks must be distinguished from live server validation.


### Branch policy — owner-confirmed, mandatory (2026-10-27; reaffirmed)
- **`main` is the only working branch. All project work and fixes must be committed directly to `main`.**
- Never create or work on feature/fix branches and do not use pull requests for this project.
- Before editing, verify the repository is `PardisMobile/ATD-Mikrotik-Backup-Studio` and the target is `main`. Keep commits scoped to the requested project work.
- Existing branches are legacy leftovers, not an approved workflow. Do not merge, recreate, or delete a branch blindly; first verify whether any unique work is needed and already present on `main`. The owner may remove unneeded legacy branches.
- Branch names last observed during the 2026-10-27 review: `fix/cron-template-sync`, `fix/reviewed-generator-panel-issues`, and `fix/timezone-cron-updater-robustness`, besides `main`. This is a point-in-time observation, not a claim that those branches have since been deleted.


### Updater postcondition fix — 2026-10-27
- Updated `server-deployment/update-standalone.sh` on `main` to make timezone helper and sudo policy installation required, validate the installed sudoers rule, and verify the installed-source commit marker plus timezone helper/rule before printing the success message.
- This prevents a successful status from being emitted if the marker/helper/policy that the panel itself checks are absent or invalid. The transaction's existing rollback trap remains active on failure.
- Commit: `ba1ed72b3b8513545fa1247fc2ef5371bcaa11a5`.
- Static syntax and full live Ubuntu rerun are still outstanding in this session. Do not claim the user's server is fixed until the updater is run and its output plus the read-only path checks confirm the marker, helper, and sudoers file.


### Updater bootstrap diagnosis/fix — 2026-10-27
- Followed the terminal command's bootstrap path in `server-deployment/update-standalone.sh`: it fetched the latest script but used `cmp` against `${BASH_SOURCE[0]}` to decide whether to replace/re-exec. That comparison depends on the invocation path and can leave an older updater process in control when the installed command is invoked through a wrapper/symlink/different path.
- Changed bootstrap to always install the freshly downloaded updater and exec it once with `ATD_UPDATER_BOOTSTRAPPED=1`; it now prints the resolved GitHub commit so the actual updater generation is visible in terminal output.
- Combined with the earlier postcondition gates, the current updater cannot print its success summary unless the installed source marker, timezone helper, and valid sudoers policy are present.
- Commit: `ce874a701cd54c6c1df301a1e375de36702baa83`.
- This is a source-level diagnosis and fix; live server confirmation and a shell syntax/CI run remain pending. User should only retry once after this commit has propagated; the output should show the bootstrap commit line. If that line is absent, the server is still invoking a stale command/bootstrap.

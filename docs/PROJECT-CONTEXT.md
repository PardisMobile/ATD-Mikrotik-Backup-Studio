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
- That command must automatically configure the server using the initial values collected by the EXE: create required directories/files, install only missing prerequisites, configure the ATD panel, the server-side Telegram scanner timer, and fetch shared/versioned application components from GitHub when needed.
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

## Current optimization request and handoff notes — 2026-10-26

This section records the user's current requirements and the latest attempted changes. It is a handoff checklist, not a statement that all features are complete or production-tested.

### User's priorities / hard constraints
- The currently deployed backup/SFTP/Telegram flow is working. Treat this as optimization, not a rewrite.
- **Do not change the core Telegram sending logic** or disrupt bot-token/Chat-ID handling, retries, sent-file deduplication, backup discovery, SFTP upload, RouterOS scheduling, saved settings, or existing installations.
- Before modifying commands for RouterOS or Ubuntu/Linux, verify them against the relevant official MikroTik RouterOS and Ubuntu/Linux documentation. Do not assume a command or time-zone name is supported by every RouterOS version.
- Inspect the actual current `main` source and CI before proposing or editing. Never claim real-server tests were performed unless they were.
- Prefer a simple, reversible implementation. Avoid adding a complicated updater or risking HTTP 500 errors.
- The user wants to review the actual current state in a new chat before deciding what to do next. **Do not immediately continue making code changes in that new chat. First audit the changed files, explain what is sound/unsafe/incomplete, and recommend a safe next step.**

### Windows generator requirements
- Review and improve question wording, order, colors, contrast, validation, and brief help text so non-technical users understand each prompt.
- The time-zone question must have exactly five choices:
  1. Iran — `Asia/Tehran`
  2. India — `Asia/Kolkata`
  3. Germany — `Europe/Berlin`
  4. USA — `America/New_York`
  5. Manual — user enters an IANA time-zone name, e.g. `Asia/Dubai` or `America/Los_Angeles`
- Label option 4 simply “USA”; do not add “Washington DC”.
- The Windows generator's selected zone is stored for the RouterOS script and Linux-side Cron schedule; installation must not silently change the host-wide system time zone. In panel Settings, the administrator may explicitly apply a zone to the Linux host and Cron using the restricted root-owned `timedatectl set-timezone` helper. This changes timezone presentation, not the system clock or NTP state. RouterOS uses its own clock/time-zone setting, so if the zone is changed after installation, show a clear warning to align RouterOS `time-zone-name` as well.
- Keep existing backup frequency, custom times, SFTP settings, public port, panel password, and local-file-retention prompts/behavior intact.
- Keep the generated output/package synchronized with canonical server files. Embedded PHP/CSS/JS/cron assets inside the PowerShell generator must match their canonical files under `server-deployment/`, unless the project intentionally documents a different versioning mechanism.

### Panel/UI requirements
- Display the Linux server's current date/time and detected system time zone.
- Show a clearly red warning explaining that RouterOS Scheduler and Linux Cron may use different time zones.
- Provide the five-option time-zone selector directly below the warning, including Manual with an example.
- A selected time zone must actually affect the intended Linux-side scheduling behavior. Merely saving a value or writing `CRON_TZ` is not proof that the router and Linux schedules are aligned. Determine the intended model (global vs per-router) and correctly convert or map schedules; account for multiple routers if supported.
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

### Last known CI state
After the latest known generator fix, the GitHub checks reported success for:
- `powershell-parse`
- `php-lint`
- `shell-check`
- `shell-validation`

These are static/CI checks only. They do not prove a live Ubuntu upgrade, RouterOS command compatibility, Telegram delivery, SFTP upload, AJAX usability, or in-panel update/rollback works on the user's server.

### Safe next-chat procedure
1. Fetch current `main`, current commit SHA, all changed files, and latest CI results.
2. Compare the generator against the last known-good version and inspect the diff, especially its final lines and all embedded here-strings.
3. Compare embedded PHP/CSS/JS/cron with canonical `server-deployment/` files.
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

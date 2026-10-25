# Project Context — ATD MikroTik Backup Studio

## Non-negotiable architecture and operating rules

These rules are the project's source of truth. Future implementation, refactoring, installer, updater, UI, and documentation changes must preserve them.

### 1. Existing working core
- The baseline is MikroTik Backup Studio v3 with working RouterOS 7 scheduled backups over SFTP.
- Preserve the working backup core. Add the server panel and optional Telegram delivery around it; do not replace it with a separate incompatible implementation.
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
- That command must automatically configure the server using the initial values collected by the EXE: create required directories/files, install only missing prerequisites, configure the ATD panel and Telegram integration, and fetch shared/versioned application components from GitHub when needed.
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

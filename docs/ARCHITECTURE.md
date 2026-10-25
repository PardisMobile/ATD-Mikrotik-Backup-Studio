# Architecture and source-of-truth rules

## Goal

Keep the already-tested v3 Windows SFTP workflow intact. GitHub is the canonical source repository for application source and static server-panel assets; it is not a store for customer configuration or secrets.

## Components

1. **Windows client** — the existing PowerShell generator, C# launcher, icon, and BAT build/launch scripts. Preserve SFTP behavior and existing path normalization unless a regression-tested change requires otherwise.
2. **Per-customer generated output** — produced by the client from the user's inputs. It contains RouterOS commands and, when Telegram mode is enabled, a server installer/configuration payload appropriate for that customer.
3. **GitHub-hosted static server package** — PHP endpoint/panel code, CSS, JavaScript, and other non-secret assets. The installer downloads a pinned release or commit so an EXE does not silently install an incompatible panel revision.
4. **Server installation** — user runs the generated installer on the target server. It downloads the pinned public assets, writes private configuration separately with restrictive permissions, validates prerequisites and paths, and installs under an explicitly confirmed existing HTTPS document-root subdirectory. It must not change global web-server configuration or open a new listening port.
5. **Panel and Telegram relay** — operate using the installed panel code and private server configuration.

## Secret-handling rules

- Never commit bot tokens, relay tokens, panel passwords/password hashes tied to a customer, customer hostnames/IPs, private SFTP paths, or generated customer configuration to a public repository.
- Generate a random relay token automatically where required.
- Store secrets in a server-side configuration file outside the public document root with restrictive permissions; do not put secrets in HTML, CSS, JavaScript, URLs, or command-line arguments that may be logged.
- Escape shell values safely and validate all user-controlled paths. Never solve permission issues with `chmod 777` or broad changes to `/root` permissions.

## Release and compatibility rules

- The Windows client source and panel assets must be committed to GitHub before claiming the repository is complete.
- Pin the panel release/commit used by each generated installer. Do not download arbitrary latest `main` assets during a production install.
- Run static checks and regression tests before building a new EXE. A release must identify the source commit it was built from.
- Do not change the tested SFTP code merely to reorganize files. Review diffs and test SFTP-only mode after changes.
- A feature is not marked complete until the generated installer has been exercised on a clean test server and Telegram/panel flows are verified end to end.

## Current status

This document defines the intended architecture; it does not certify that the repository is currently complete or production-ready. Check `docs/TEST-REPORT.md` and the repository file list before deployment.

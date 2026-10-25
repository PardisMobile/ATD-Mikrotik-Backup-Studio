# ATD MikroTik Backup Studio v3

**Windows-based MikroTik RouterOS 7 backup generator with SFTP delivery and optional Telegram relay/panel.**

> Project status: active development. Do not treat Telegram/server deployment as production-verified until the end-to-end test checklist passes on a real Windows client, RouterOS device, and target server.

## Goals

- Preserve the existing RouterOS 7 backup generation and SFTP workflow.
- Optionally deliver completed `.backup` files through a Telegram bot.
- Wait for remote file size and modification time to stabilize before Telegram delivery.
- Track successful deliveries by content hash to avoid re-sending the same file version.
- Provide a small password-protected web panel for backup status and management.
- Keep deployment within an existing web server; do not open an extra network port or change global web-server configuration unnecessarily.

## Repository layout

- `windows-client/` — PowerShell backup generator and Windows launcher/build scripts.
- `server-deployment/` — server deployment helper and setup notes.
- `docs/` — installation notes and test report.

## Requirements

### Windows client
- Windows PowerShell / .NET compatible with the client build scripts.
- Network reachability to the MikroTik RouterOS device and the configured SFTP destination.
- For Telegram mode: a Telegram bot token, destination chat ID, and HTTPS-accessible relay endpoint.

### Server
- Existing Linux server with PHP CLI and an existing HTTPS web server (Nginx or Apache).
- SFTP destination directory accessible to the SFTP account and, with narrowly scoped permissions, to the PHP relay.
- Outbound HTTPS access to Telegram Bot API.
- The deployment script must be reviewed against the actual server layout before use.

## Quick start

1. Download or clone this repository.
2. Read [Installation (Persian)](docs/INSTALLATION_FA.md) and the notes in `server-deployment/README.txt`.
3. On Windows, run `windows-client/Generate-MikroTik-Backup.bat` to generate a configuration/run the client.
4. Build the EXE using `windows-client/Build-EXE.bat` if needed.
5. For SFTP-only mode, verify a backup arrives in the configured remote directory.
6. For Telegram mode, configure the bot and HTTPS relay, then test with a non-critical backup and verify the complete file arrives.

## Security notes

- Never commit Telegram bot tokens, relay secrets, passwords, private keys, or real server configuration.
- Use a strong unique panel password and HTTPS.
- Do not make the web server run as root and do not use `chmod 777`.
- Avoid exposing directories containing backups directly as public web content.
- Backups may contain sensitive router configuration. Restrict access and retention appropriately.

## Test status

See [docs/TEST-REPORT.md](docs/TEST-REPORT.md). Syntax checks are not the same as end-to-end verification. Windows EXE generation, RouterOS upload, Telegram delivery, and installation on the target host must be tested before a stable release is announced.

## License

No license has been selected yet. Until a license is added, standard copyright restrictions apply; do not assume this project is open source for reuse.

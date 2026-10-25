# ATD MikroTik Backup Studio

**ATD · MikroTik RouterOS 7 backup automation, SFTP delivery, and optional Telegram management panel.**

> **Repository status: incomplete development snapshot.** The server panel assets and setup documentation are present. The full Windows client source/build files have not yet been synchronized into this repository, and the server template still requires secure configuration. Do not use this repository snapshot as a production-ready release.

## Planned product

- Generate RouterOS 7 backups from a Windows client.
- Preserve the existing SFTP workflow.
- Optionally send fully uploaded backup files to Telegram.
- Check remote file stability before delivery and track successful sends by content hash.
- Provide a responsive Persian/English web panel with light/dark themes and selectable accent colors.
- Install under an existing HTTPS website without adding a listening port or changing global web-server configuration.

## Repository contents

- `server-deployment/send-backup.php` — configurable example relay and web panel.
- `server-deployment/panel.css` — responsive ATD interface styling.
- `server-deployment/panel.js` — theme, accent-color, language, search, and confirmation interactions.
- `server-deployment/install-server.sh` — conservative copy helper for an existing web-root subdirectory.
- `docs/INSTALLATION_FA.md` — Persian setup notes.
- `docs/TEST-REPORT.md` — current test limitations and release gate.
- `.gitignore` — excludes local secrets and generated backups.

Partial Windows-client synchronization has started: the launcher C# source and BAT launch/build scripts are present. The core `Generate-MikroTik-Backup.ps1` and custom `.ico` are still missing, so the client cannot yet be built/run from this repository. The GitHub-downloaded panel installer flow is also not complete.

## Server setup (current scaffold only)

Clone the repository:

```bash
git clone https://github.com/PardisMobile/ATD-Mikrotik-Backup-Studio.git
cd ATD-Mikrotik-Backup-Studio
```

Review the installer and Persian guide before running any server-side command:

```bash
less server-deployment/install-server.sh
less docs/INSTALLATION_FA.md
```

The PHP file contains explicit `REPLACE_...` placeholders. **Do not expose it publicly until every placeholder is replaced securely and authentication/state handling has been completed and tested.** The installer only copies files into a supplied existing directory; it does not detect your actual vhost/document root, generate secrets, or fully configure the relay.

After the integrated installer is implemented, the intended command will resemble:

```bash
sudo bash server-deployment/install-server.sh /ABSOLUTE/EXISTING/WEBROOT/atd-backup
```

Replace the path with a verified subdirectory under the existing HTTPS site's document root. Never guess the path, run unreviewed scripts on production, use `chmod 777`, or run PHP as root. Be especially cautious with backup directories under `/root`.

## Architecture contract

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the required integration model: preserve the tested v3 SFTP client, generate per-customer scripts/configuration from EXE inputs, and fetch pinned non-secret panel assets from GitHub during server installation. This contract is not a claim that the full package is already synchronized or production-ready.

## Security

- Never commit Telegram bot tokens, relay tokens, panel passwords, private keys, or real backup files.
- Keep secrets outside the repository and restrict server-side file permissions.
- MikroTik backups can contain sensitive network configuration; limit access and retention.
- Do not claim successful Telegram delivery until the received file is verified.

## Testing and release

Read [docs/TEST-REPORT.md](docs/TEST-REPORT.md) and [Persian installation notes](docs/INSTALLATION_FA.md). A stable release requires actual Windows/EXE build tests, RouterOS 7/SFTP tests, Telegram end-to-end tests, panel authentication/CSRF/password-rotation tests, installer/ACL tests on the target host, and responsive UI checks.

## License

No license has been selected yet. Standard copyright restrictions apply unless a license is added.


## GitHub-based server updates

For an already installed server panel, see [GitHub update instructions](docs/GITHUB-UPDATES.md). The optional update command is:

```bash
sudo bash install-server.sh --update /absolute/path/to/installed/panel
```

The updater stages files, backs up current assets, checks PHP syntax, and carries matching customer-specific constants into the updated PHP file. This is currently a development updater using the repository's `main` branch; review the test report before production use.

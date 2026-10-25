# ATD MikroTik Backup Studio

ATD MikroTik Backup Studio automates scheduled MikroTik RouterOS 7 backups, transfers backup files over SFTP, and optionally delivers them to Telegram through a password-protected management panel.

## Features

- Generates RouterOS 7 backup commands and scheduler configuration from a Windows setup tool.
- Uploads backups to a configurable remote directory over SFTP.
- Optional Telegram delivery using a bot token and destination chat ID.
- Waits for uploaded files to appear stable before sending them to Telegram.
- Tracks previously delivered files to reduce duplicate sends.
- Web panel for listing backups, manually sending or retrying delivery, deleting files with confirmation, and changing the panel password.
- Persian/English interface, light/dark themes, responsive layout, and selectable accent colors.
- Standalone server deployment that does not require changing an existing Nginx/Apache configuration.
- Automatically chooses an available public port and creates a self-signed TLS certificate, so a domain or subdomain is not required.
- Adds an allow rule for the selected port when a supported host firewall manager is detected.
- Keeps panel state in a separate protected directory and grants the service account limited access to the configured backup directory.

## Requirements

- Windows computer to generate the RouterOS configuration.
- MikroTik RouterOS 7 with SFTP access to the backup server.
- Linux server with internet access and a supported package manager (apt, dnf, or yum) for automatic installation.
- Root/sudo access on the server.
- Telegram bot token and destination chat ID only if Telegram delivery is enabled.

## How to use

### 1. Generate the backup configuration

1. Run the ATD MikroTik Backup Studio Windows generator.
2. Enter the router, SFTP host, username, password, and remote backup directory.
3. If Telegram is needed, enter the bot token and chat ID and set a strong panel password.
4. Keep the generated package private; it contains customer-specific configuration and secrets.

### 2. Configure the MikroTik router

1. Open the generated `paste-into-routeros-terminal.txt` file.
2. Paste its complete contents into the MikroTik RouterOS terminal.
3. Verify that the script and scheduler were created with the configured names.
4. Confirm that the router can upload a backup to the selected SFTP directory.

### 3. Install the standalone panel

1. Upload the generated package, including `install-server.sh`, to the Linux server.
2. From that directory, run:

   ```bash
   sudo bash install-server.sh
   ```

3. The installer installs required packages, sets up the isolated ATD service, selects a port, creates a TLS certificate, and attempts to allow the port in a recognized host firewall.
4. Open the URL printed at the end of installation. It uses the server IP and selected port; no domain or subdomain is required.

### 4. Browser certificate warning

The standalone installer uses a self-signed certificate. The browser will warn that the certificate is not trusted by a public certificate authority. The connection is encrypted, but the certificate identity is not independently validated by the browser. Verify that the IP address in the URL is the address of your server before proceeding. A trusted certificate can be configured separately if you have a suitable domain or certificate.

### 5. Use the panel

Sign in with the panel password configured during generation. Review uploaded backups, manually send or retry Telegram delivery, and use the confirmation prompt before deleting files. Confirm Telegram receipt before relying on a backup as delivered.

## Security notes

- Never publish the generated package or share its configuration files; they may contain SFTP credentials, Telegram tokens, and relay secrets.
- Keep the backup directory outside any public web document root.
- Do not use `chmod 777` or run the PHP panel as root.
- Backups may contain sensitive network configuration. Restrict server access and retention.
- An automatically opened host firewall port does not override upstream provider firewalls or network ACLs.
- The self-signed TLS certificate encrypts traffic but produces a browser trust warning.

ATD MikroTik Backup Studio — Server deployment notes

This directory contains the server deployment helper. Review the script before running it on any production host.

Safety prerequisites:
- Make a server backup and confirm SSH/root access for rollback.
- Identify the actual HTTPS virtual host and document root first.
- Do not change global Nginx/Apache configuration or open a new port unless you have explicitly reviewed the change.
- Do not run PHP-FPM as root and never use chmod 777.
- Do not expose the backup directory as public static content.
- Give the web process only the narrow access it needs; be especially careful when the backup directory is under /root.
- Keep Telegram bot token, relay token, and panel password out of source control and logs.

Run only after reviewing install-server.sh and confirming its assumptions match your server. The script has not yet been validated against every hosting/control-panel layout. After installation, test authentication and file permissions before using real router backups.

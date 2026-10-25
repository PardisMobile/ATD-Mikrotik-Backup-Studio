# Test Report

## Scope

This report separates source-level checks from end-to-end validation. It must be updated with actual environment details and results before tagging a stable release.

## Current verification status

- PHP syntax check: previously reported successful for a generated PHP template; this does not verify the complete deployed application.
- PowerShell execution: not yet verified in a Windows environment in this workflow.
- EXE build: not yet verified.
- RouterOS 7 backup creation and SFTP upload: must be verified on the target router.
- File stability / complete-upload detection: must be verified with slow and interrupted uploads.
- Telegram Bot API delivery: not yet verified against the actual bot and chat.
- Duplicate suppression after retry/restart: must be verified.
- Panel authentication, CSRF protection, delete/retry/password change: must be tested in a real PHP web-server context.
- Server installer compatibility with the actual Nginx/Apache/PHP-FPM configuration: not yet verified.
- Mobile/tablet/desktop visual QA and Persian/English layout: must be tested in browsers.

## Release gate

Do not mark a release production-ready until the Windows client, RouterOS upload, relay, panel, permission model, and installer pass end-to-end tests. Keep test credentials and router backups out of the repository.

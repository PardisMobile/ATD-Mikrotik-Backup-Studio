@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0Generate-MikroTik-Backup.ps1" exit /b 2
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Generate-MikroTik-Backup.ps1"
exit /b %ERRORLEVEL%

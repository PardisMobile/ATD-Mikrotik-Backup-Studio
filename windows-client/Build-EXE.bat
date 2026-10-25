@echo off
setlocal
title Build Amir Taheri MikroTik Backup Studio
color 0B
cd /d "%~dp0"
cls
echo.
echo   ============================================================
echo      BUILD MIKROTIK BACKUP STUDIO
echo      Created by Amir Taheri
echo   ============================================================
echo.
if not exist "Generate-MikroTik-Backup.ps1" (
  color 0C
  echo   ERROR: Generate-MikroTik-Backup.ps1 is missing.
  pause
  exit /b 2
)
set "CSC="
if exist "%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe" set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not defined CSC if exist "%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe" set "CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not defined CSC (
  color 0C
  echo   ERROR: C# compiler csc.exe was not found.
  pause
  exit /b 1
)
if not exist "AmirTaheri-Backup.ico" (
  color 0C
  echo   ERROR: AmirTaheri-Backup.ico was not found.
  pause
  exit /b 1
)
echo   Compiling EXE with custom icon...
"%CSC%" /nologo /target:exe /win32icon:"AmirTaheri-Backup.ico" /out:"MikroTikBackupGenerator.exe" /reference:System.dll "MikroTikBackupLauncher.cs"
if errorlevel 1 (
  color 0C
  echo   Build failed.
  pause
  exit /b 1
)
color 0A
echo.
echo   BUILD SUCCESSFUL
echo   Keep the EXE and Generate-MikroTik-Backup.ps1 in the same folder.
pause

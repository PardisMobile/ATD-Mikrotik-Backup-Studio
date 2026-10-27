$ErrorActionPreference = 'Stop'
$Host.UI.RawUI.WindowTitle = 'MikroTik RouterOS 7 Backup Generator'

function Read-Required([string]$Prompt, [string]$Default = '') {
    while ($true) {
        $display = if ($Default) { "$Prompt [$Default]" } else { $Prompt }
        Write-Host $display -ForegroundColor Cyan -NoNewline
        $v = Read-Host
        if ($Default -and [string]::IsNullOrWhiteSpace($v)) { $v = $Default }
        if (-not [string]::IsNullOrWhiteSpace($v)) { return $v.Trim() }
        Write-Host 'This field is required. Please try again.' -ForegroundColor Yellow
    }
}
function Read-SecretText([string]$Prompt) {
    $s = Read-Host $Prompt -AsSecureString
    $p = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($p) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p) }
}
function Escape-RouterString([string]$s) {
    return $s.Replace('\','\\').Replace('"','\"')
}
function Escape-PhpSingle([string]$s) {
    return $s.Replace('\','\\').Replace("'","\'")
}
function Escape-JsonString([string]$s) {
    return ConvertTo-Json -InputObject $s -Compress
}
function New-HexRandom([int]$ByteCount) {
    $bytes = New-Object byte[] $ByteCount
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return ([BitConverter]::ToString($bytes) -replace '-', '').ToLowerInvariant()
}
function Get-Sha256Text([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}
function Convert-HexToBytes([string]$Hex) {
    $bytes = New-Object byte[] ([int]($Hex.Length / 2))
    for ($i = 0; $i -lt $bytes.Length; $i++) { $bytes[$i] = [Convert]::ToByte($Hex.Substring($i * 2, 2), 16) }
    return ,$bytes
}

Clear-Host
$Host.UI.RawUI.WindowTitle = 'Amir Taheri - MikroTik Backup Studio'
Write-Host ''
Write-Host '============================================================' -ForegroundColor DarkCyan
Write-Host '       MIKROTIK BACKUP STUDIO - ROUTEROS 7' -ForegroundColor Cyan
Write-Host '                 Created by Amir Taheri' -ForegroundColor White
Write-Host '                 Orax Tech Solutions LLC' -ForegroundColor Magenta
Write-Host '                 Contact: +989347682358' -ForegroundColor Gray
Write-Host '============================================================' -ForegroundColor DarkCyan
Write-Host ''
Write-Host '  Create a MikroTik backup script and daily schedule.' -ForegroundColor Gray
Write-Host '  Backups are unencrypted. Keep generated files and passwords private.' -ForegroundColor Yellow
Write-Host ''

Write-Host 'Choose how you want to use the backup tool:' -ForegroundColor Cyan
Write-Host '  1) SFTP only - create backups and upload them to your Linux server.'
Write-Host '  2) SFTP + Telegram panel - upload backups and manage automatic Telegram delivery.'
Write-Host '  Note: Telegram Bot Token and Chat ID are entered later in the web panel.' -ForegroundColor Gray
do { $mode = Read-Host 'Choose 1 or 2' } while ($mode -notin @('1','2'))

$useSftp = $true
$useTelegram = $mode -eq '2'
if ($mode -eq '1') { $useTelegram = $false }

Write-Host ''
Write-Host 'SFTP settings (required in both modes)' -ForegroundColor Cyan
Write-Host 'Use the same Linux server where the panel will be installed (mode 2). The panel reads backups from this server.' -ForegroundColor Gray
Write-Host 'Use the real Linux path, not a chroot-relative path. The folder must exist and be writable.' -ForegroundColor Gray
$sftpHost = Read-Required 'SFTP server address (IP or hostname)'
$sftpPort = '22'
Write-Host 'SFTP port is fixed to 22.' -ForegroundColor DarkGray
$sftpUser = Read-Required 'SFTP username'
$sftpPass = Read-SecretText 'SFTP password (stored in generated script; use a restricted SFTP account)'
$remoteDir = Read-Required 'Backup folder on Linux (absolute path, e.g. /root/uploads)' '/root/uploads'
$remoteDir = $remoteDir.TrimEnd('/')
if ([string]::IsNullOrWhiteSpace($remoteDir)) { $remoteDir = '/' }
# Relative names resolve under /root, as documented for this product.
if (-not $remoteDir.StartsWith('/')) { $remoteDir = '/root/' + $remoteDir.TrimStart('/') }
if ($remoteDir -notmatch '^/[A-Za-z0-9._/-]+$' -or $remoteDir -eq '/' -or $remoteDir -match '(^|/)\.\.?(/|$)') { throw 'Use a safe absolute SFTP directory containing only letters, numbers, dot, underscore, dash and slash; no spaces or dot-dot segments.' }
$panelFolderName = Split-Path -Leaf $remoteDir.TrimEnd('/')
if ([string]::IsNullOrWhiteSpace($panelFolderName) -or $panelFolderName -in @('.', '..') -or $panelFolderName -notmatch '^[A-Za-z0-9_-]{1,64}$') { throw 'Remote directory must end with a simple folder name, e.g. /root/uploads or /Upload.' }
$panelPath = '/' + $panelFolderName + '/send-backup.php'

$maxUploadMb = '45'
$panelPassword = ''

if ($useTelegram) {
    Write-Host ''
    Write-Host 'Telegram bot token and Chat ID will be configured later in the web panel.' -ForegroundColor Cyan
    do {
        $publicPortInput = Read-Required 'Public HTTPS panel port (20000-60000; open this TCP port in your provider firewall if needed)' '24443'
        $publicPort = 0
        $validPort = [int]::TryParse($publicPortInput, [ref]$publicPort) -and $publicPort -ge 20000 -and $publicPort -le 60000
        if (-not $validPort) { Write-Host 'Enter a port from 20000 through 60000.' -ForegroundColor Yellow }
    } while (-not $validPort)
    while ($true) {
        $panelPassword = Read-SecretText 'Create panel password (minimum 8 characters)'
        if ($panelPassword.Length -lt 8) {
            Write-Host 'Password must contain at least 8 characters. Please try again.' -ForegroundColor Yellow
            continue
        }
        $confirmPanelPassword = Read-SecretText 'Re-enter panel password to confirm'
        if ($panelPassword -cne $confirmPanelPassword) {
            Write-Host 'The passwords do not match. Please enter them again.' -ForegroundColor Yellow
            continue
        }
        $confirmPanelPassword = $null
        break
    }
}

Write-Host ''
Write-Host 'TIME ZONE / REGION' -ForegroundColor Cyan
Write-Host 'Choose the time zone used by the router and the Linux-side backup schedule.' -ForegroundColor Gray
Write-Host 'This sets the RouterOS time-zone name and records the same IANA zone for panel configuration.' -ForegroundColor DarkGray
Write-Host '  1) Iran       - Asia/Tehran' -ForegroundColor White
Write-Host '  2) India      - Asia/Kolkata' -ForegroundColor White
Write-Host '  3) Germany    - Europe/Berlin' -ForegroundColor White
Write-Host '  4) USA        - America/New_York' -ForegroundColor White
Write-Host '  5) Manual     - enter an IANA time-zone name, e.g. Asia/Dubai or America/Los_Angeles' -ForegroundColor White
do { $timezoneChoice = Read-Host 'Select time zone [1-5]' } while ($timezoneChoice -notin @('1','2','3','4','5'))
$timeZoneName = switch ($timezoneChoice) {
    '1' { 'Asia/Tehran' }
    '2' { 'Asia/Kolkata' }
    '3' { 'Europe/Berlin' }
    '4' { 'America/New_York' }
    '5' {
        while ($true) {
            $manualZone = Read-Required 'IANA time-zone name (case-sensitive; example Asia/Dubai)'
            if (($manualZone -match '^[A-Za-z_+-]+(?:/[A-Za-z0-9_+.-]+)+$') -or ($manualZone -eq 'UTC')) { break }
            Write-Host 'Invalid format. Use an IANA name such as Asia/Dubai, Europe/Paris, America/Los_Angeles, or UTC.' -ForegroundColor Yellow
        }
        $manualZone
    }
}
Write-Host ("Selected time zone: {0}" -f $timeZoneName) -ForegroundColor Green
Write-Host 'Note: RouterOS must support this time-zone name. Verify the router clock after setup.' -ForegroundColor DarkGray
Write-Host ''
Write-Host 'SCHEDULER SETTINGS' -ForegroundColor Cyan
$scriptName = Read-Required 'Name for the MikroTik backup script' 'mikrotik-backup'
if ($scriptName -notmatch '^[A-Za-z0-9_-]{1,40}$') { throw 'Use 1-40 characters: English letters, numbers, dash or underscore.' }

function Read-BackupTime([string]$label, [string]$defaultTime) {
    while ($true) {
        $value = Read-Required "$label (HH:MM)" $defaultTime
        if ($value -match '^([01]\d|2[0-3]):([0-5]\d)$') { return "$value`:00" }
        Write-Host 'Invalid time. Use HH:MM, from 00:00 to 23:59.' -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host 'BACKUP FREQUENCY' -ForegroundColor Cyan
Write-Host '  1) Once per day'
Write-Host '  2) Twice per day'
do { $frequency = Read-Host 'Choose 1 or 2' } while ($frequency -notin @('1','2'))

Write-Host ''
Write-Host 'TIME SETUP' -ForegroundColor Cyan
Write-Host '  1) Use default time(s): 00:00 (and 12:00 for twice daily)'
Write-Host '  2) Enter custom time(s)'
do { $timeMode = Read-Host 'Choose 1 or 2' } while ($timeMode -notin @('1','2'))

if ($timeMode -eq '1') {
    $scheduleTimes = @('00:00:00')
    if ($frequency -eq '2') { $scheduleTimes += '12:00:00' }
} else {
    $scheduleTimes = @(Read-BackupTime 'Enter first daily backup time' '00:00')
    if ($frequency -eq '2') {
        $secondTime = Read-BackupTime 'Enter second daily backup time' '12:00'
        if ($secondTime -eq $scheduleTimes[0]) {
            throw 'The two daily backup times must be different.'
        }
        $scheduleTimes += $secondTime
    }
}
Write-Host ''
Write-Host 'Keep local backup after upload?' -ForegroundColor Cyan
Write-Host '  Y) Yes, keep the local .backup file'
Write-Host '  N) No, delete it only after successful delivery'
do { $keepLocal = Read-Host 'Keep local file? [Y/N]' } while ($keepLocal -notmatch '^(?i:y|n)$')
$deleteAfterUpload = $keepLocal -match '^(?i:n)$'

$outDir = Join-Path $PSScriptRoot 'generated-output'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$obsoleteSchedulerFile = Join-Path $outDir 'scheduler-commands.txt'
if (Test-Path $obsoleteSchedulerFile) { Remove-Item $obsoleteSchedulerFile -Force }
# Remove obsolete separately generated panel assets from prior runs; the server now fetches verified code from GitHub.
foreach ($obsolete in @('install.sh', 'send-backup.php', 'panel.css', 'panel.js', 'router-backup.rsc')) {
    $obsoletePath = Join-Path $outDir $obsolete
    if (Test-Path $obsoletePath -PathType Leaf) { Remove-Item $obsoletePath -Force }
}

$routerName = 'RouterOS Identity is read dynamically on the router'
$hostEsc = Escape-RouterString $sftpHost
$userEsc = Escape-RouterString $sftpUser
$passEsc = Escape-RouterString $sftpPass
$dirEsc = Escape-RouterString $remoteDir

$telegramBlock = '# Telegram delivery is handled automatically by the Linux-side cron job; RouterOS only uses SFTP.'

$cleanupCondition = '($backupOK = true) && ($sftpOK = true)'

$routerScript = @"
# Generated MikroTik RouterOS 7 backup script
# Backup is deliberately unencrypted. Restrict access to the resulting files.
# Upload uses SFTP. Remote directory must already exist and be writable. Do not run concurrent copies of this script.
:local sftpHost "$hostEsc"
:local sftpPort $sftpPort
:local sftpUser "$userEsc"
:local sftpPass "$passEsc"
:local remoteDir "$dirEsc"

:local routerName [/system identity get name]
# Preserve the established RouterOS identity-based backup filename behavior.
:local safeName ""
:for i from=0 to=([:len `$routerName] - 1) do={
    :local ch [:pick `$routerName `$i (`$i + 1)]
    :if (`$ch = " ") do={ :set safeName (`$safeName . "_") } else={ :set safeName (`$safeName . `$ch) }
}
:if ([:len `$safeName] = 0) do={ :set safeName "mikrotik" }
:local d [/system clock get date]
:local t [/system clock get time]
# RouterOS date expected as mmm/DD/YYYY
:local stamp ([:pick `$d 7 11] . [:pick `$d 0 3] . [:pick `$d 4 6] . "-" . [:pick `$t 0 2] . [:pick `$t 3 5] . [:pick `$t 6 8])
:local fn (`$safeName . "-" . `$stamp)
:local localFile (`$fn . ".backup")
:local remoteFile (`$remoteDir . "/" . `$localFile)
:local backupOK false
:local sftpOK false

:log info ("BACKUP: starting " . `$localFile)

:do {
    /system backup save name=`$fn dont-encrypt=yes
    :delay 10s
    :local ids [/file find where name=`$localFile]
    :if ([:len `$ids] = 0) do={ :error "Backup file not found" }
    :local sz [/file get `$ids size]
    :if (`$sz = 0) do={ :error "Backup file is empty" }
    :set backupOK true
    :log info ("BACKUP: created " . `$localFile . " bytes=" . `$sz)
} on-error={
    :log error "BACKUP: creation failed; local file retained if present"
}

:if (`$backupOK) do={
    :do {
        /tool fetch address=`$sftpHost port=`$sftpPort mode=sftp user=`$sftpUser password=`$sftpPass src-path=`$localFile dst-path=`$remoteFile upload=yes
        :set sftpOK true
        :log info "BACKUP: SFTP upload command completed"
    } on-error={
        :log error "BACKUP: SFTP upload failed; local file retained"
    }
}

# Telegram delivery is handled by the Linux server; keep RouterOS backup/SFTP workflow unchanged.

$(if ($deleteAfterUpload) {
    @(
        ':if (' + $cleanupCondition + ') do={'
        '    :do {'
        '        /file remove [/file find where name=$localFile]'
        '        :log info ("BACKUP: SFTP upload completed; local file removed: " . $localFile)'
        '    } on-error={'
        '        :log error ("BACKUP: delivery succeeded but local cleanup failed: " . $localFile)'
        '    }'
        '} else={'
        '    :log error ("BACKUP: backup creation or SFTP upload failed; local file retained: " . $localFile)'
        '}'
    ) -join [Environment]::NewLine
} else {
    ':log info ("BACKUP: local file retention selected; keeping " . $localFile)'
})
"@

# Produce a safely quoted, ready-to-copy Linux command for creating the chosen SFTP directory.
$linuxDir = $remoteDir
if (-not $linuxDir.StartsWith('/')) { $linuxDir = '/root/' + $linuxDir.TrimStart('/') }
if ($linuxDir -notmatch '^/[A-Za-z0-9._/-]+$' -or $linuxDir.Contains('/../') -or $linuxDir.EndsWith('/..') -or $linuxDir -match '^/[^/]+$' -or $linuxDir -in @('/', '/root', '/home', '/etc', '/var', '/usr', '/opt', '/tmp')) { throw 'Remote directory must be a dedicated backup subdirectory, not a filesystem/system root.' }
$createDirCommand = 'mkdir -p -- ' + "'" + $linuxDir.Replace("'", "'\''") + "'"
[System.IO.File]::WriteAllText((Join-Path $outDir 'create-sftp-directory.txt'), $createDirCommand + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))

if ($useTelegram) {
    $pathPhp = Escape-PhpSingle $remoteDir
    $passwordSalt = (New-HexRandom 16)
    $pbkdf = New-Object Security.Cryptography.Rfc2898DeriveBytes($panelPassword, (Convert-HexToBytes $passwordSalt), 200000)
    $panelPasswordHash = ([BitConverter]::ToString($pbkdf.GetBytes(32)) -replace '-', '').ToLowerInvariant()
    $pbkdf.Dispose()
    $maxBytes = ([int64]$maxUploadMb) * 1024 * 1024

        $schedulePhp = ($scheduleTimes | ForEach-Object { "'" + $_ + "'" }) -join ', '
    $configPhp = @"
<?php
declare(strict_types=1);
const TELEGRAM_BOT_TOKEN = '';
const TELEGRAM_CHAT_ID = '';
const PANEL_PASSWORD_SALT = '$passwordSalt';
const PANEL_PASSWORD_HASH = '$panelPasswordHash';
const BACKUP_DIR = '$pathPhp';
const STATE_FILE = '/var/lib/atd-mikrotik-backup-studio/state.php';
const MAX_FILE_BYTES = $maxBytes;
const PUBLIC_PORT = $publicPort;
const BACKUP_SCHEDULE_TIMES = [$schedulePhp];
const TELEGRAM_DELAY_MINUTES = 2;
const DEFAULT_TIMEZONE = '$timeZoneName';
"@
    $panelHostPhp = $sftpHost.Replace('\', '\\').Replace("'", "\'")
    $configPhp = $configPhp.Replace("const PUBLIC_PORT = $publicPort;", "const PUBLIC_PORT = $publicPort; const PANEL_HOSTNAME = '$panelHostPhp';")
    $configB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($configPhp))

    $installServer = @'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $(id -u) -eq 0 ]] || { echo 'Run as root: sudo bash install.sh' >&2; exit 2; }
command -v curl >/dev/null 2>&1 || {
  if command -v apt-get >/dev/null 2>&1; then export DEBIAN_FRONTEND=noninteractive; apt-get update -y; apt-get install -y curl ca-certificates
  elif command -v dnf >/dev/null 2>&1; then dnf install -y curl ca-certificates
  elif command -v yum >/dev/null 2>&1; then yum install -y curl ca-certificates
  else echo 'Cannot install curl: apt, dnf, or yum is required.' >&2; exit 4; fi
}
TMP="$(mktemp -d /tmp/atd-bootstrap.XXXXXX)"
chmod 0700 "$TMP"
trap 'rm -rf -- "$TMP"' EXIT
API='https://api.github.com/repos/PardisMobile/ATD-Mikrotik-Backup-Studio/commits/main'
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --max-time 60 "$API" -o "$TMP/commit.json"
COMMIT="$(sed -n 's/^[[:space:]]*"sha": "\([0-9a-f]\{40\}\)",$/\1/p' "$TMP/commit.json" | sed -n '1p')"
[[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]] || { echo 'Could not resolve an immutable GitHub commit for this installation.' >&2; exit 5; }
BASE="https://raw.githubusercontent.com/PardisMobile/ATD-Mikrotik-Backup-Studio/$COMMIT/server-deployment"
fetch_asset() {
  local name="$1"
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --max-time 60 "$BASE/$name" -o "$TMP/$name"
  [[ -s "$TMP/$name" ]] || { echo "Downloaded asset is empty: $name" >&2; exit 5; }
}
# Application assets come from GitHub at install time. They are deliberately not
# embedded in this customer-specific package, so later UI/PHP changes remain updateable.
fetch_asset 'send-backup.php'
fetch_asset 'panel.css'
fetch_asset 'panel.js'
fetch_asset 'cron-helper.sh'
printf '%s' '__CONFIG_B64__' | base64 --decode > "$TMP/config.php"
chmod 0600 "$TMP/config.php"
if command -v php >/dev/null 2>&1; then
  php -l "$TMP/config.php" >/dev/null || { echo 'Generated private configuration failed PHP syntax validation.' >&2; exit 6; }
fi
fetch_asset 'install-standalone.sh'
chmod 0600 "$TMP/install-standalone.sh"
ATD_SOURCE_COMMIT="$COMMIT" bash "$TMP/install-standalone.sh" "$TMP"
'@
    $installServer = $installServer.Replace('__CONFIG_B64__', $configB64)
    $installPath = Join-Path $outDir 'install.sh'
    [System.IO.File]::WriteAllText($installPath, $installServer, [System.Text.UTF8Encoding]::new($false))
    # The generated installer contains this customer's secret configuration. Restrict it to the current Windows user.
    try {
        $acl = Get-Acl $installPath
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($rule in @($acl.Access)) { [void]$acl.RemoveAccessRule($rule) }
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $rule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList @($identity, 'FullControl', 'Allow')
        $acl.AddAccessRule($rule)
        Set-Acl -Path $installPath -AclObject $acl
    } catch { Write-Warning 'Could not restrict install.sh permissions automatically. Store the generated-output folder securely.' }
}

$schedulerLines = @()
for ($i = 0; $i -lt $scheduleTimes.Count; $i++) {
    $entryName = if ($scheduleTimes.Count -eq 1) { "$scriptName-daily" } else { "$scriptName-daily-$($i + 1)" }
    $schedulerLines += "/system scheduler add name=`"$entryName`" start-time=$($scheduleTimes[$i]) interval=1d on-event=`"/system script run $scriptName`" policy=ftp,password,read,write,policy,sensitive,test"
}
$scheduler = $schedulerLines -join "`r`n"

# One-paste RouterOS Terminal setup: creates both the script and its daily scheduler.
# The script source is wrapped in a RouterOS brace block; nested script blocks are retained.
$terminalSetup = '/system clock set time-zone-name=' + $timeZoneName + ' time-zone-autodetect=no' + "`r`n" + '/system script add name="' + $scriptName + '" policy=ftp,password,read,write,policy,sensitive,test source={' + "`r`n" + $routerScript + "`r`n}" + "`r`n" + $scheduler
[System.IO.File]::WriteAllText((Join-Path $outDir 'paste-into-routeros-terminal.txt'), $terminalSetup, [System.Text.UTF8Encoding]::new($false))

$readme = @"
ATD MikroTik Backup Studio
RouterOS 7 scheduled backups over SFTP, with optional Telegram delivery and a password-protected panel.

OUTPUT
- paste-into-routeros-terminal.txt: paste the complete file into MikroTik Terminal.
- install.sh (Telegram/Panel mode only): private server bootstrap containing installation configuration; never publish it.
- create-sftp-directory.txt: command to create the remote SFTP folder if needed.

TELEGRAM/PANEL INSTALL
1. The SFTP host must be the same Linux server as the panel, and the backup path must be the real absolute filesystem path (not a chroot-relative SFTP path).
2. Transfer install.sh securely to that Linux server.
3. Run: sudo bash install.sh
4. The installer downloads the panel application files from GitHub at install time, writes private config on the server, and installs ATD services. Future PHP/CSS/JS updates are delivered by the server updater.
5. Paste paste-into-routeros-terminal.txt into MikroTik Terminal.
6. Open the exact HTTPS URL printed by the installer and sign in with the initial panel password. Allow the selected public TCP port in the provider firewall if needed.
7. In the panel's Telegram delivery settings, enter the Bot Token and destination Chat ID, then use "Test Telegram connection". It sends the newest existing backup file; it does not send a separate text test message.

SFTP-ONLY MODE
No install.sh or web panel is created. Paste paste-into-routeros-terminal.txt into MikroTik Terminal and use create-sftp-directory.txt if the remote folder still needs to be created.

The installer uses ATD-specific paths and services and does not edit existing Nginx/Apache configuration or host-wide firewall rules. A self-signed TLS certificate may cause a browser warning. Keep install.sh private because it contains the initial configuration.
"@
[System.IO.File]::WriteAllText((Join-Path $outDir 'README.txt'), $readme, [System.Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host "Generated files: $outDir" -ForegroundColor Green
Get-ChildItem $outDir | Select-Object Name, Length | Format-Table -AutoSize
Write-Host ''
Write-Host 'NEXT STEP' -ForegroundColor Cyan
Write-Host '1. Open generated-output\paste-into-routeros-terminal.txt'
Write-Host '2. Copy the entire file and paste it into MikroTik Terminal.'
Write-Host '3. Verify the script and scheduler exist with the exact name you entered.'
Write-Host ''
Write-Host 'Created by Amir Taheri | Orax Tech Solutions LLC' -ForegroundColor DarkCyan
Write-Host '+989347682358' -ForegroundColor Gray
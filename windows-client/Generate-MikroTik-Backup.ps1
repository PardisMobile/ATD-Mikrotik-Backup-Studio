$ErrorActionPreference = 'Stop'
$Host.UI.RawUI.WindowTitle = 'MikroTik RouterOS 7 Backup Generator'

function Read-Required([string]$Prompt, [string]$Default = '') {
    while ($true) {
        if ($Default) { $v = Read-Host "$Prompt [$Default]"; if ([string]::IsNullOrWhiteSpace($v)) { $v = $Default } }
        else { $v = Read-Host $Prompt }
        if (-not [string]::IsNullOrWhiteSpace($v)) { return $v.Trim() }
        Write-Host 'This value is required.' -ForegroundColor Yellow
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
Write-Host '  Configure backup, delivery and scheduler in one pass.' -ForegroundColor Gray
Write-Host '  Backup files are unencrypted; protect generated credentials.' -ForegroundColor Yellow
Write-Host ''

Write-Host 'Choose destination mode:'
Write-Host '  1) SFTP only'
Write-Host '  2) Telegram only (still requires SFTP staging on a server)'
Write-Host '  3) SFTP + Telegram'
do { $mode = Read-Host 'Select 1, 2, or 3' } while ($mode -notin @('1','2','3'))

$useSftp = $true
$useTelegram = $mode -in @('2','3')
if ($mode -eq '1') { $useTelegram = $false }

Write-Host ''
Write-Host 'SFTP destination (required for all modes). The SFTP host must be this same Linux server where the panel will be installed; the panel reads backups from its local filesystem.' -ForegroundColor Cyan
Write-Host 'Use the real absolute Linux filesystem path, not a chroot-relative SFTP path. Create/check the folder first; the RouterOS script does not create Linux folders.' -ForegroundColor Yellow
$sftpHost = Read-Required 'SFTP hostname or IP'
$sftpPort = '22'
Write-Host 'SFTP port is fixed to 22.' -ForegroundColor DarkGray
$sftpUser = Read-Required 'SFTP username'
$sftpPass = Read-SecretText 'SFTP password (will be written into the RouterOS script; use a dedicated restricted account)'
$remoteDir = Read-Required 'Absolute Linux filesystem path on this server (not a chroot-relative SFTP path)' '/root/uploads'
$remoteDir = $remoteDir.TrimEnd('/')
if ([string]::IsNullOrWhiteSpace($remoteDir)) { $remoteDir = '/' }
# Relative names resolve under /root, as documented for this product.
if (-not $remoteDir.StartsWith('/')) { $remoteDir = '/root/' + $remoteDir.TrimStart('/') }
if ($remoteDir -notmatch '^/[A-Za-z0-9._/-]+$' -or $remoteDir -eq '/' -or $remoteDir -match '(^|/)\.\.?(/|$)') { throw 'Use a safe absolute SFTP directory containing only letters, numbers, dot, underscore, dash and slash; no spaces or dot-dot segments.' }
$panelFolderName = Split-Path -Leaf $remoteDir.TrimEnd('/')
if ([string]::IsNullOrWhiteSpace($panelFolderName) -or $panelFolderName -in @('.', '..') -or $panelFolderName -notmatch '^[A-Za-z0-9_-]{1,64}$') { throw 'Remote directory must end with a simple folder name, e.g. /root/uploads or /Upload.' }
$panelPath = '/' + $panelFolderName + '/send-backup.php'

$relayBaseUrl = ''
$relayToken = ''
$telegramBotToken = ''
$telegramChatId = ''
$maxUploadMb = '45'
$panelPassword = ''

if ($useTelegram) {
    Write-Host ''
    Write-Host 'Telegram setup (only the real Telegram details are requested).' -ForegroundColor Cyan
    do {
        $publicPortInput = Read-Required 'Public HTTPS panel port (20000-60000; open this TCP port in your provider firewall if needed)' '24443'
        $publicPort = 0
        $validPort = [int]::TryParse($publicPortInput, [ref]$publicPort) -and $publicPort -ge 20000 -and $publicPort -le 60000
        if (-not $validPort) { Write-Host 'Enter a port from 20000 through 60000.' -ForegroundColor Yellow }
    } while (-not $validPort)
    $relayBaseUrl = 'https://' + $sftpHost.Trim() + ':' + $publicPort + '/send-backup.php'
    Write-Host "Default panel/relay URL: $relayBaseUrl" -ForegroundColor Gray
    Write-Host 'The panel is served at /send-backup.php on its own HTTPS port, not inside the SFTP backup directory.' -ForegroundColor DarkGray
    $customRelay = Read-Host 'Enter a custom HTTPS relay URL only if you have a matching domain/reverse proxy, or press Enter to use this default'
    if (-not [string]::IsNullOrWhiteSpace($customRelay)) { $relayBaseUrl = $customRelay.Trim() }
    if ($relayBaseUrl -notmatch '^https://[^/]+(?::[0-9]{1,5})?/send-backup\.php$') { throw 'Enter an HTTPS URL ending exactly in /send-backup.php; for a custom path, configure a reverse proxy to that endpoint.' }
    $relayToken = (New-HexRandom 32)
    $telegramBotToken = Read-Required 'Telegram bot token (from @BotFather)'
    $telegramChatId = Read-Required 'Telegram destination chat ID (user, group or channel)'
    $panelPassword = Read-SecretText 'Choose initial password for the web management panel'
    if ($panelPassword.Length -lt 12) { throw 'Use a panel password of at least 12 characters.' }
}

Write-Host ''
Write-Host 'SCHEDULER SETTINGS' -ForegroundColor Cyan
$scriptName = Read-Required 'RouterOS script name (scheduler will use the same name)' 'mikrotik-backup'
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
do { $frequency = Read-Host 'How many backups per day? [1/2]' } while ($frequency -notin @('1','2'))

Write-Host ''
Write-Host 'TIME SETUP' -ForegroundColor Cyan
Write-Host '  1) Use default time(s): 00:00 (and 12:00 for twice daily)'
Write-Host '  2) Enter custom time(s)'
do { $timeMode = Read-Host 'Select default or custom time [1/2]' } while ($timeMode -notin @('1','2'))

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
foreach ($obsolete in @('send-backup.php', 'panel.css', 'panel.js')) {
    $obsoletePath = Join-Path $outDir $obsolete
    if (Test-Path $obsoletePath -PathType Leaf) { Remove-Item $obsoletePath -Force }
}

$routerName = 'RouterOS Identity is read dynamically on the router'
$hostEsc = Escape-RouterString $sftpHost
$userEsc = Escape-RouterString $sftpUser
$passEsc = Escape-RouterString $sftpPass
$dirEsc = Escape-RouterString $remoteDir
$relayEsc = Escape-RouterString $relayBaseUrl
$tokenEsc = Escape-RouterString $relayToken

$telegramBlock = ''
if ($useTelegram) {
$telegramBlock = @"
# SFTP fetch returns after upload; wait briefly, then PHP independently verifies remote file stability.
# This small delay is not the only completion check; the PHP relay checks size/mtime repeatedly.
:if (`$sftpOK) do={
    :delay 10s
    :do {
        :local resp [/tool fetch url="$relayEsc" http-method=post http-header-field=("Content-Type: application/json, X-Backup-Token: $tokenEsc") http-data=("{`"file`":`"" . `$localFile . "`"}") output=user as-value]
        :if ((`$resp->"status") = "finished" && (`$resp->"data") = "TELEGRAM_OK") do={
            :set telegramOK true
            :log info "BACKUP: Telegram delivery confirmed"
        } else={
            :log error ("BACKUP: Telegram relay did not confirm: " . (`$resp->"data"))
        }
    } on-error={
        :log error "BACKUP: Telegram relay request failed"
    }
}
"@
}

$cleanupCondition = if ($useTelegram) { '($backupOK = true) && ($sftpOK = true) && ($telegramOK = true)' } else { '($backupOK = true) && ($sftpOK = true)' }
$telegramInit = if ($useTelegram) { '$telegramOK false' } else { '$telegramOK true' }

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
# Restrict Identity to the filename characters accepted by the relay; replace all others with underscores.
:local safeName ""
:for i from=0 to=([:len `$routerName] - 1) do={
    :local ch [:pick `$routerName `$i (`$i + 1)]
    :if (`$ch ~ "[^A-Za-z0-9_.-]") do={ :set safeName (`$safeName . "_") } else={ :set safeName (`$safeName . `$ch) }
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
:local telegramOK $(if ($useTelegram) { 'false' } else { 'true' })

:log info ("BACKUP: starting " . `$localFile)

:do {
    /system backup save name=`$fn dont-encrypt=yes
    :delay 3s
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

$(if ($useTelegram) { $telegramBlock } else { '# Telegram disabled by generator choice.' })

$(if ($deleteAfterUpload) {
    @(
        ':if (' + $cleanupCondition + ') do={'
        '    :do {'
        '        /file remove [/file find where name=$localFile]'
        '        :log info ("BACKUP: delivery confirmed; local file removed: " . $localFile)'
        '    } on-error={'
        '        :log error ("BACKUP: delivery succeeded but local cleanup failed: " . $localFile)'
        '    }'
        '} else={'
        '    :log error ("BACKUP: delivery incomplete; local file retained: " . $localFile)'
        '}'
    ) -join [Environment]::NewLine
} else {
    ':log info ("BACKUP: local file retention selected; keeping " . $localFile)'
})
"@

# Write RouterOS script as UTF-8 without BOM
$routerPath = Join-Path $outDir 'router-backup.rsc'
[System.IO.File]::WriteAllText($routerPath, $routerScript, [System.Text.UTF8Encoding]::new($false))

# Produce a safely quoted, ready-to-copy Linux command for creating the chosen SFTP directory.
$linuxDir = $remoteDir
if (-not $linuxDir.StartsWith('/')) { $linuxDir = '/root/' + $linuxDir.TrimStart('/') }
if ($linuxDir -notmatch '^/[A-Za-z0-9._/-]+$' -or $linuxDir.Contains('/../') -or $linuxDir.EndsWith('/..') -or $linuxDir -match '^/[^/]+$' -or $linuxDir -in @('/', '/root', '/home', '/etc', '/var', '/usr', '/opt', '/tmp')) { throw 'Remote directory must be a dedicated backup subdirectory, not a filesystem/system root.' }
$createDirCommand = 'mkdir -p -- ' + "'" + $linuxDir.Replace("'", "'\''") + "'"
[System.IO.File]::WriteAllText((Join-Path $outDir 'create-sftp-directory.txt'), $createDirCommand + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))

if ($useTelegram) {
    $tokenPhp = Escape-PhpSingle $relayToken
    $botPhp = Escape-PhpSingle $telegramBotToken
    $chatPhp = Escape-PhpSingle $telegramChatId
    $pathPhp = Escape-PhpSingle $remoteDir
    $passwordSalt = (New-HexRandom 16)
    $pbkdf = New-Object Security.Cryptography.Rfc2898DeriveBytes($panelPassword, (Convert-HexToBytes $passwordSalt), 200000)
    $panelPasswordHash = ([BitConverter]::ToString($pbkdf.GetBytes(32)) -replace '-', '').ToLowerInvariant()
    $pbkdf.Dispose()
    $maxBytes = ([int64]$maxUploadMb) * 1024 * 1024

    $php = @'
<?php
declare(strict_types=1);
require_once '/etc/atd-mikrotik-backup-studio/config.php';
const STABILITY_CHECKS = 3;
const STABILITY_INTERVAL_SECONDS = 2;
const MAX_WAIT_SECONDS = 90;

session_name_guard();

function session_name_guard(): void {
    ini_set('session.use_strict_mode', '1');
    session_set_cookie_params(['httponly'=>true, 'secure'=>true, 'samesite'=>'Strict']);
    session_start();
}
function load_state(): array {
    if (!is_file(STATE_FILE)) return [];
    $raw = @file_get_contents(STATE_FILE);
    if (!is_string($raw)) return [];
    $prefix = "<?php http_response_code(404); exit; ?>\n";
    if (strncmp($raw, $prefix, strlen($prefix)) === 0) $raw = substr($raw, strlen($prefix));
    $data = json_decode($raw, true);
    return is_array($data) ? $data : [];
}
function save_state(array $state): bool {
    $tmp = STATE_FILE . '.tmp';
    $payload = "<?php http_response_code(404); exit; ?>\n" . json_encode($state, JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES);
    if (@file_put_contents($tmp, $payload, LOCK_EX) === false) return false;
    @chmod($tmp, 0600);
    return @rename($tmp, STATE_FILE);
}
function verify_panel_password(string $password): bool {
    $state = load_state();
    $salt = (string)($state['_panel_password']['salt'] ?? PANEL_PASSWORD_SALT);
    $expected = (string)($state['_panel_password']['hash'] ?? PANEL_PASSWORD_HASH);
    $actual = hash_pbkdf2('sha1', $password, hex2bin($salt), 200000, 64);
    return hash_equals($expected, $actual);
}
function csrf_token(): string {
    if (empty($_SESSION['csrf'])) $_SESSION['csrf'] = bin2hex(random_bytes(32));
    return (string)$_SESSION['csrf'];
}
function check_csrf(): bool {
    return isset($_POST['csrf'], $_SESSION['csrf']) && is_string($_POST['csrf']) && hash_equals((string)$_SESSION['csrf'], (string)$_POST['csrf']);
}
function send_telegram_file(string $name, bool $force = false): array {
    $base = realpath(BACKUP_DIR);
    if ($base === false || !preg_match('/\A[A-Za-z0-9_. -]+\.backup\z/', $name) || basename($name) !== $name) return [false, 'INVALID_FILENAME'];
    $path = realpath($base . DIRECTORY_SEPARATOR . $name);
    if ($path === false || dirname($path) !== $base || !is_file($path) || !is_readable($path)) return [false, 'FILE_NOT_FOUND'];
    $deadline=time()+MAX_WAIT_SECONDS; $stable=0; $lastSize=-1; $lastMtime=-1;
    do {
        clearstatcache(true,$path); $sz=@filesize($path); $mt=@filemtime($path);
        if ($sz === false || $mt === false || $sz < 1) $stable=0;
        elseif ($sz === $lastSize && $mt === $lastMtime) $stable++;
        else $stable=0;
        $lastSize=$sz===false?-1:$sz; $lastMtime=$mt===false?-1:$mt;
        if ($stable >= STABILITY_CHECKS) break;
        sleep(STABILITY_INTERVAL_SECONDS);
    } while (time() < $deadline);
    if ($stable < STABILITY_CHECKS) return [false,'FILE_NOT_STABLE'];
    $size=@filesize($path); if ($size===false || $size<1 || $size>MAX_FILE_BYTES) return [false,'FILE_SIZE_REJECTED'];
    $hash=hash_file('sha256',$path); $state=load_state();
    if (!$force && isset($state[$name]) && ($state[$name]['sha256']??'')===$hash && ($state[$name]['status']??'')==='sent') return [true,'ALREADY_SENT'];
    $ch=curl_init('https://api.telegram.org/bot'.TELEGRAM_BOT_TOKEN.'/sendDocument');
    curl_setopt_array($ch,[CURLOPT_POST=>true,CURLOPT_POSTFIELDS=>['chat_id'=>TELEGRAM_CHAT_ID,'document'=>new CURLFile($path,'application/octet-stream',$name),'caption'=>'MikroTik backup: '.$name],CURLOPT_RETURNTRANSFER=>true,CURLOPT_CONNECTTIMEOUT=>15,CURLOPT_TIMEOUT=>180,CURLOPT_SSL_VERIFYPEER=>true,CURLOPT_SSL_VERIFYHOST=>2]);
    $response=curl_exec($ch); $curlError=curl_error($ch); $http=(int)curl_getinfo($ch,CURLINFO_HTTP_CODE); curl_close($ch); $result=is_string($response)?json_decode($response,true):null;
    if ($curlError==='' && $http>=200 && $http<300 && is_array($result) && ($result['ok']??false)===true) {
        $state[$name]=['status'=>'sent','sha256'=>$hash,'size'=>$size,'mtime'=>filemtime($path),'sent_at'=>gmdate('c')];
        if (!save_state($state)) return [false,'STATE_SAVE_FAILED'];
        return [true,'TELEGRAM_OK'];
    }
    $state[$name]=['status'=>'failed','sha256'=>$hash,'size'=>$size,'mtime'=>filemtime($path),'failed_at'=>gmdate('c'),'error'=>$curlError!==''?$curlError:('Telegram HTTP '.$http)]; save_state($state);
    return [false,'TELEGRAM_SEND_FAILED'];
}
function esc(string $s): string { return htmlspecialchars($s, ENT_QUOTES|ENT_SUBSTITUTE, 'UTF-8'); }
function render_panel(): void {
    header('Content-Type: text/html; charset=utf-8');
    if (isset($_POST['logout'])) { $_SESSION=[]; session_destroy(); header('Location: '.$_SERVER['PHP_SELF']); return; }
    if (!empty($_POST['login'])) {
        if (verify_panel_password((string)($_POST['password'] ?? ''))) { session_regenerate_id(true); $_SESSION['admin']=true; header('Location: '.$_SERVER['PHP_SELF']); return; }
        $error='رمز عبور نادرست است.';
    }
    if (empty($_SESSION['admin'])) {
        echo '<!doctype html><html lang="fa" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>ATD MikroTik Backup Studio</title><link rel="stylesheet" href="panel.css"></head><body class="login-page"><main class="login-card"><div class="brand-mark">'.icon_svg('router').'</div><p class="eyebrow">ATD · MIKROTIK BACKUP STUDIO</p><h1>مدیریت بکاپ‌ها</h1><p class="muted">برای ورود، رمز عبور پنل را وارد کنید.</p>'.(isset($error)?'<div class="alert alert-error">'.esc($error).'</div>':'').'<form method="post" class="login-form"><label for="password">رمز عبور</label><input id="password" type="password" name="password" required autocomplete="current-password" placeholder="رمز عبور پنل"><button class="btn btn-primary" name="login" value="1">ورود به پنل <span class="btn-icon">'.icon_svg('arrow-left').'</span></button></form><p class="login-foot">محافظت‌شده توسط ATD Security</p></main><script src="panel.js" defer></script></body></html>'; return;
    }
    if ($_SERVER['REQUEST_METHOD'] === 'POST' && empty($_POST['login']) && empty($_POST['logout'])) {
        if (!check_csrf()) { http_response_code(403); exit('Invalid session token. Refresh the page and retry.'); }
        $action=(string)($_POST['action']??''); $name=(string)($_POST['file']??'');
        if ($action==='send') { [$ok,$message]=send_telegram_file($name, true); $_SESSION['flash']=['ok'=>$ok,'message'=>$message]; }
        elseif ($action==='delete') {
            $base=realpath(BACKUP_DIR); $path=($base!==false && basename($name)===$name && preg_match('/\A[A-Za-z0-9_. -]+\.backup\z/',$name))?realpath($base.DIRECTORY_SEPARATOR.$name):false;
            if ($path!==false && dirname($path)===$base && is_file($path) && @unlink($path)) { $st=load_state(); unset($st[$name]); save_state($st); $_SESSION['flash']=['ok'=>true,'message'=>'DELETED']; }
            else $_SESSION['flash']=['ok'=>false,'message'=>'DELETE_FAILED'];
        } elseif ($action==='password') {
            $old=(string)($_POST['old_password']??''); $new=(string)($_POST['new_password']??'');
            if (!verify_panel_password($old)) $_SESSION['flash']=['ok'=>false,'message'=>'CURRENT_PASSWORD_INVALID'];
            elseif (strlen($new)<12) $_SESSION['flash']=['ok'=>false,'message'=>'PASSWORD_TOO_SHORT'];
            else { $st=load_state(); $salt=bin2hex(random_bytes(16)); $st['_panel_password']=['salt'=>$salt,'hash'=>hash_pbkdf2('sha1',$new,hex2bin($salt),200000,64),'changed_at'=>gmdate('c')]; if(save_state($st)) $_SESSION['flash']=['ok'=>true,'message'=>'PASSWORD_UPDATED']; else $_SESSION['flash']=['ok'=>false,'message'=>'STATE_SAVE_FAILED']; }
        }
        header('Location: '.$_SERVER['PHP_SELF']); exit;
    }
    $csrf=csrf_token();
    $flash=$_SESSION['flash']??null; unset($_SESSION['flash']);
    $base=realpath(BACKUP_DIR); $files=[];
    if ($base !== false && is_readable($base)) { foreach (glob($base.DIRECTORY_SEPARATOR.'*.backup') ?: [] as $f) { if (is_file($f) && is_readable($f)) $files[]=$f; } }
    usort($files, fn($a,$b)=>filemtime($b)<=>filemtime($a)); $state=load_state();
    $totalBytes=0; foreach($files as $f) { $totalBytes += (int)filesize($f); }
    $sentCount=0; $failedCount=0; foreach($files as $f) { $st=$state[basename($f)]['status']??''; if($st==='sent')$sentCount++; elseif($st==='failed')$failedCount++; }
    $lang = (($_COOKIE['atd_lang'] ?? 'fa') === 'en') ? 'en' : 'fa'; $isEn = $lang==='en';
    $t = $isEn ? ['title'=>'Backup management','subtitle'=>'Your MikroTik backup files, in one place.','files'=>'Backup files','sent'=>'Sent to Telegram','failed'=>'Failed delivery','storage'=>'Total storage','search'=>'Search backups…','name'=>'File name','size'=>'Size','date'=>'Modified','status'=>'Telegram status','actions'=>'Actions','sent_status'=>'Sent','failed_status'=>'Failed','pending'=>'Not sent','empty'=>'No .backup files found in this directory.','path'=>'Backup directory','logout'=>'Sign out','refresh'=>'Refresh','delete'=>'Delete','send'=>'Send / retry','confirm'=>'Are you sure you want to delete this backup?','language'=>'فارسی','theme'=>'Toggle theme','settings'=>'Panel','password'=>'Change password','old'=>'Current password','new'=>'New password (12+ characters)','save'=>'Update password','cancel'=>'Cancel','login'=>'Sign in','welcome'=>'Welcome back','secure'=>'Secure backup workspace','bytes'=>'bytes'] : ['title'=>'مدیریت بکاپ‌ها','subtitle'=>'فایل‌های بکاپ میکروتیک، یک‌جا و مرتب.','files'=>'تعداد بکاپ‌ها','sent'=>'ارسال‌شده به تلگرام','failed'=>'ارسال ناموفق','storage'=>'حجم کل فایل‌ها','search'=>'جست‌وجوی بکاپ…','name'=>'نام فایل','size'=>'حجم','date'=>'آخرین تغییر','status'=>'وضعیت تلگرام','actions'=>'عملیات','sent_status'=>'ارسال‌شده','failed_status'=>'ناموفق','pending'=>'ارسال‌نشده','empty'=>'فایلی با پسوند .backup در این مسیر پیدا نشد.','path'=>'مسیر بکاپ','logout'=>'خروج','refresh'=>'تازه‌سازی','delete'=>'حذف','send'=>'ارسال / تلاش مجدد','confirm'=>'از حذف این فایل بکاپ مطمئن هستید؟','language'=>'English','theme'=>'تغییر تم','settings'=>'پنل','password'=>'تغییر رمز عبور','old'=>'رمز فعلی','new'=>'رمز جدید (حداقل ۱۲ کاراکتر)','save'=>'ذخیره رمز','cancel'=>'انصراف','login'=>'ورود','welcome'=>'خوش آمدید','secure'=>'محیط امن مدیریت بکاپ','bytes'=>'بایت'];
    echo '<!doctype html><html lang="'.($isEn?'en':'fa').'" dir="'.($isEn?'ltr':'rtl').'"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light dark"><title>ATD · '.esc($t['title']).'</title><link rel="stylesheet" href="panel.css"></head><body><div class="app-shell"><aside class="sidebar"><a class="brand" href="'.esc($_SERVER['PHP_SELF']).'"><span class="brand-mark">'.icon_svg('router').'</span><span><strong>ATD</strong><small>MIKROTIK BACKUP STUDIO</small></span></a><div class="side-label">'.esc($t['settings']).'</div><div class="side-active">'.icon_svg('layout').'<span>'.esc($t['title']).'</span></div><div class="sidebar-bottom"><span class="online-dot"></span><span>RouterOS 7 · '.($isEn?'Protected':'محافظت‌شده').'</span></div></aside><main class="main-content"><header class="topbar"><div class="topbar-heading"><div class="breadcrumb">ATD <span>/</span> '.esc($t['title']).'</div><h1>'.esc($t['title']).'</h1><p>'.esc($t['subtitle']).'</p></div><div class="top-actions"><button class="icon-btn" type="button" id="themeToggle" aria-label="'.esc($t['theme']).'">'.icon_svg('moon').'</button><div class="theme-colors" aria-label="Accent color"><button class="color-swatch" style="background:#1769e0" data-accent="#1769e0" aria-label="Blue"></button><button class="color-swatch" style="background:#0d9488" data-accent="#0d9488" aria-label="Teal"></button><button class="color-swatch" style="background:#7c3aed" data-accent="#7c3aed" aria-label="Violet"></button><button class="color-swatch" style="background:#db2777" data-accent="#db2777" aria-label="Rose"></button><button class="color-swatch" style="background:#ea580c" data-accent="#ea580c" aria-label="Orange"></button></div><button class="language-btn" type="button" id="languageToggle">'.esc($t['language']).'</button><form method="post"><button class="btn btn-ghost" name="logout" value="1">'.icon_svg('logout').'<span>'.esc($t['logout']).'</span></button></form></div></header>';
    if (is_array($flash)) echo '<div class="alert '.(!empty($flash['ok'])?'alert-success':'alert-error').'">'.esc((string)($flash['message']??'')).'</div>';
    echo '<section class="welcome-strip"><div class="welcome-copy"><span class="eyebrow">ATD BACKUP CENTER</span><h2>'.esc($t['welcome']).' 👋</h2><p>'.esc($t['secure']).'</p></div><div class="welcome-art" aria-hidden="true">'.icon_svg('cloud').'</div></section>';
    echo '<section class="stats-grid"><article class="stat-card"><span class="stat-icon blue">'.icon_svg('files').'</span><span class="stat-label">'.esc($t['files']).'</span><strong>'.count($files).'</strong><small>'.esc($t['path']).': <code>'.esc(BACKUP_DIR).'</code></small></article><article class="stat-card"><span class="stat-icon green">'.icon_svg('send').'</span><span class="stat-label">'.esc($t['sent']).'</span><strong>'.$sentCount.'</strong><small>'.($isEn?'Successful deliveries':'ارسال‌های موفق ثبت‌شده').'</small></article><article class="stat-card"><span class="stat-icon orange">'.icon_svg('alert').'</span><span class="stat-label">'.esc($t['failed']).'</span><strong>'.$failedCount.'</strong><small>'.($isEn?'Files needing attention':'فایل‌های نیازمند بررسی').'</small></article><article class="stat-card"><span class="stat-icon purple">'.icon_svg('database').'</span><span class="stat-label">'.esc($t['storage']).'</span><strong>'.esc(format_bytes($totalBytes)).'</strong><small>'.($isEn?'Combined backup size':'مجموع حجم بکاپ‌ها').'</small></article></section>';
    echo '<section class="files-panel password-panel"><div class="panel-heading"><div><h2>'.icon_svg('shield').' '.esc($t['password']).'</h2><p>'.($isEn?'Use a strong password with at least 12 characters.':'برای امنیت بیشتر، رمز قوی با حداقل ۱۲ نویسه انتخاب کنید.').'</p></div></div><form method="post" class="password-form"><input type="hidden" name="csrf" value="'.esc($csrf).'"><input type="hidden" name="action" value="password"><label>'.esc($t['old']).'<input type="password" name="old_password" required autocomplete="current-password"></label><label>'.esc($t['new']).'<input type="password" name="new_password" minlength="12" required autocomplete="new-password"></label><button class="btn btn-primary" type="submit">'.esc($t['save']).'</button></form></section>';
    echo '<section class="files-panel"><div class="panel-heading"><div><h2>'.icon_svg('files').' '.esc($isEn?'Your backups':'فایل‌های بکاپ شما').'</h2><p>'.($isEn?'Review recent backups and Telegram delivery status.':'وضعیت فایل‌ها و ارسال تلگرام را بررسی کنید.').'</p></div><div class="panel-tools"><label class="search-box">'.icon_svg('search').'<input id="backupSearch" type="search" placeholder="'.esc($t['search']).'" autocomplete="off"></label><button class="btn btn-primary" type="button" onclick="location.reload()">'.icon_svg('refresh').' <span>'.esc($t['refresh']).'</span></button></div></div><div class="table-wrap"><table id="backupTable"><thead><tr><th>'.esc($t['name']).'</th><th>'.esc($t['size']).'</th><th>'.esc($t['date']).'</th><th>'.esc($t['status']).'</th><th>'.esc($t['actions']).'</th></tr></thead><tbody>';
    foreach ($files as $f) { $n=basename($f); $st=$state[$n]??[]; $status=(string)($st['status']??'pending'); $statusClass=$status==='sent'?'status-sent':($status==='failed'?'status-failed':'status-pending'); $statusText=$status==='sent'?$t['sent_status']:($status==='failed'?$t['failed_status']:$t['pending']); echo '<tr data-search="'.esc(strtolower($n)).'"><td><div class="file-name"><span class="file-icon">'.icon_svg('file').'</span><span><strong>'.esc($n).'</strong><small>'.esc($isEn?'MikroTik backup file':'فایل پشتیبان میکروتیک').'</small></span></div></td><td class="nowrap">'.esc(format_bytes((int)filesize($f))).'</td><td class="nowrap">'.esc(date('Y-m-d H:i',filemtime($f))).'</td><td><span class="status-pill '.$statusClass.'"><i></i>'.esc($statusText).'</span></td><td><div class="row-actions"><form method="post" class="inline-action"><input type="hidden" name="csrf" value="'.esc($csrf).'"/><input type="hidden" name="action" value="send"/><input type="hidden" name="file" value="'.esc($n).'"/><button class="icon-btn" type="submit" title="'.esc($t['send']).'" aria-label="'.esc($t['send']).'">'.icon_svg('send').'</button></form><form method="post" class="inline-action" onsubmit="return confirm(&quot;'.esc($t['confirm']).'&quot;)"><input type="hidden" name="csrf" value="'.esc($csrf).'"/><input type="hidden" name="action" value="delete"/><input type="hidden" name="file" value="'.esc($n).'"/><button class="icon-btn danger" type="submit" title="'.esc($t['delete']).'" aria-label="'.esc($t['delete']).'">'.icon_svg('trash').'</button></form></div></td></tr>'; }
    if (!$files) echo '<tr><td colspan="5"><div class="empty-state">'.icon_svg('folder-empty').'<strong>'.esc($t['empty']).'</strong></div></td></tr>';
    echo '</tbody></table></div><div class="panel-footer"><span>'.($isEn?'Showing':'نمایش'). ' <strong>'.count($files).'</strong> '.($isEn?'backup files':'فایل بکاپ').'</span><span class="footer-secure">'.icon_svg('shield').' '.($isEn?'Private server storage':'ذخیره‌سازی خصوصی روی سرور').'</span></div></section><footer class="app-footer"><span>© '.date('Y').' ATD · MikroTik Backup Studio</span><span>'.($isEn?'Built for safer backups':'ساخته‌شده برای بکاپ‌گیری امن‌تر').'</span></footer></main></div><script src="panel.js" defer></script></body></html>';
}
function icon_svg(string $name): string {
    $paths = [
        'router'=>'<rect x="3" y="8" width="18" height="9" rx="2"/><path d="M7 12h.01M11 12h.01M15 12h.01M7 17v3m10-3v3M9 5l3-2 3 2"/>',
        'arrow-left'=>'<path d="M19 12H5m7 7-7-7 7-7"/>','moon'=>'<path d="M20.9 13A9 9 0 0 1 11 3.1 9 9 0 1 0 20.9 13Z"/>',
        'layout'=>'<rect x="3" y="3" width="18" height="18" rx="3"/><path d="M9 3v18M9 9h12"/>','logout'=>'<path d="M10 17l5-5-5-5m5 5H3"/><path d="M12 3h6a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-6"/>',
        'cloud'=>'<path d="M20 16.2A4.5 4.5 0 0 0 18 7.5a6 6 0 0 0-11.5 1.7A4 4 0 0 0 7 17h12"/><path d="M12 12v8m-3-3 3 3 3-3"/>',
        'files'=>'<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8Z"/><path d="M14 2v6h6M8 13h8M8 17h8"/>',
        'send'=>'<path d="m22 2-7 20-4-9-9-4Z"/><path d="M22 2 11 13"/>','alert'=>'<path d="m10.3 3.9-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.7-3.1l-8-14a2 2 0 0 0-3.4 0Z"/><path d="M12 9v4m0 4h.01"/>',
        'database'=>'<ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5v14a9 3 0 0 0 18 0V5M3 12a9 3 0 0 0 18 0"/>','search'=>'<circle cx="11" cy="11" r="7"/><path d="m20 20-4-4"/>','refresh'=>'<path d="M20 7v5h-5M4 17v-5h5"/><path d="M5.6 9A7 7 0 0 1 18 6l2 6M4 12l2 6a7 7 0 0 0 12.4-3"/>',
        'file'=>'<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8Z"/><path d="M14 2v6h6"/>','trash'=>'<path d="M3 6h18M8 6V4h8v2m3 0-1 14H6L5 6m4 4v6m6-6v6"/>','shield'=>'<path d="M12 22s8-4 8-11V5l-8-3-8 3v6c0 7 8 11 8 11Z"/><path d="m9 12 2 2 4-4"/>','folder-empty'=>'<path d="M3 7a2 2 0 0 1 2-2h5l2 2h7a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2Z"/><path d="M3 10h18"/>'
    ];
    return '<svg class="svg-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'.($paths[$name]??$paths['file']).'</svg>';
}
function format_bytes(int $bytes): string {
    if ($bytes < 1024) return $bytes.' B';
    $units=['KB','MB','GB','TB']; $value=$bytes/1024; $i=0;
    while($value>=1024 && $i<count($units)-1){$value/=1024;$i++;}
    return number_format($value, $value<10?1:0).' '.$units[$i];
}

if ($_SERVER['REQUEST_METHOD'] === 'GET' || (!empty($_SESSION['admin']) && $_SERVER['REQUEST_METHOD'] === 'POST') || (!empty($_POST['login']) && $_SERVER['REQUEST_METHOD'] === 'POST')) {
    render_panel();
    exit;
}
if ($_SERVER['REQUEST_METHOD'] !== 'POST') { http_response_code(405); exit('METHOD_NOT_ALLOWED'); }
$provided = $_SERVER['HTTP_X_BACKUP_TOKEN'] ?? '';
if (!hash_equals(RELAY_TOKEN, $provided)) { http_response_code(403); exit('FORBIDDEN'); }
$input = json_decode(file_get_contents('php://input'), true);
$name = is_array($input) ? ($input['file'] ?? '') : '';
if (!is_string($name) || !preg_match('/\A[A-Za-z0-9_.-]+-\d{4}[A-Za-z]{3}\d{2}-\d{6}\.backup\z/', $name)) {
    http_response_code(400); exit('INVALID_FILENAME');
}
$base = realpath(BACKUP_DIR);
$path = $base === false ? false : realpath($base . DIRECTORY_SEPARATOR . $name);
if ($base === false || $path === false || dirname($path) !== $base || !is_file($path) || !is_readable($path)) {
    http_response_code(404); exit('FILE_NOT_FOUND');
}
// Wait until the file size and modification time remain unchanged across consecutive checks.
$deadline = time() + MAX_WAIT_SECONDS;
$stable = 0; $lastSize = -1; $lastMtime = -1;
do {
    clearstatcache(true, $path);
    $sizeNow = @filesize($path); $mtimeNow = @filemtime($path);
    if ($sizeNow === false || $mtimeNow === false || $sizeNow < 1) { $stable = 0; }
    elseif ($sizeNow === $lastSize && $mtimeNow === $lastMtime) { $stable++; }
    else { $stable = 0; }
    $lastSize = $sizeNow === false ? -1 : $sizeNow;
    $lastMtime = $mtimeNow === false ? -1 : $mtimeNow;
    if ($stable >= STABILITY_CHECKS) break;
    sleep(STABILITY_INTERVAL_SECONDS);
} while (time() < $deadline);
if ($stable < STABILITY_CHECKS) { http_response_code(425); exit('FILE_NOT_STABLE'); }
$size = filesize($path);
if ($size === false || $size < 1 || $size > MAX_FILE_BYTES) { http_response_code(413); exit('FILE_SIZE_REJECTED'); }
$hash = hash_file('sha256', $path);
$state = load_state();
if (isset($state[$name]) && ($state[$name]['sha256'] ?? '') === $hash && ($state[$name]['status'] ?? '') === 'sent') {
    http_response_code(200); exit('TELEGRAM_OK'); // Idempotent success: never send the same version twice.
}
$ch = curl_init('https://api.telegram.org/bot' . TELEGRAM_BOT_TOKEN . '/sendDocument');
curl_setopt_array($ch, [
    CURLOPT_POST => true,
    CURLOPT_POSTFIELDS => [
        'chat_id' => TELEGRAM_CHAT_ID,
        'document' => new CURLFile($path, 'application/octet-stream', $name),
        'caption' => 'MikroTik backup: ' . $name
    ],
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_CONNECTTIMEOUT => 15,
    CURLOPT_TIMEOUT => 180,
    CURLOPT_SSL_VERIFYPEER => true,
    CURLOPT_SSL_VERIFYHOST => 2
]);
$response = curl_exec($ch);
$curlError = curl_error($ch);
$status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);
$result = is_string($response) ? json_decode($response, true) : null;

if ($curlError === '' && $status >= 200 && $status < 300 &&
    is_array($result) && ($result['ok'] ?? false) === true) {
    $state[$name] = ['status'=>'sent','sha256'=>$hash,'size'=>$size,'mtime'=>filemtime($path),'sent_at'=>gmdate('c')];
    if (!save_state($state)) { error_log('Telegram sent but state could not be saved; duplicate protection may be unavailable.'); }
    http_response_code(200);
    exit('TELEGRAM_OK');
}
$state[$name] = ['status'=>'failed','sha256'=>$hash,'size'=>$size,'mtime'=>filemtime($path),'attempted_at'=>gmdate('c'),'http'=>$status];
save_state($state);
error_log('MikroTik backup Telegram delivery failed; HTTP=' . $status . '; error=' . $curlError);
http_response_code(502);
exit('TELEGRAM_FAILED');
'@
    # Keep customer-specific values separate from the versioned PHP application code.
    $phpTemplate = $php
    $phpHash = Get-Sha256Text $phpTemplate
    $configPhp = @"
<?php
declare(strict_types=1);
const RELAY_TOKEN = '$tokenPhp';
const TELEGRAM_BOT_TOKEN = '$botPhp';
const TELEGRAM_CHAT_ID = '$chatPhp';
const PANEL_PASSWORD_SALT = '$passwordSalt';
const PANEL_PASSWORD_HASH = '$panelPasswordHash';
const BACKUP_DIR = '$pathPhp';
const STATE_FILE = '/var/lib/atd-mikrotik-backup-studio/state.php';
const MAX_FILE_BYTES = $maxBytes;
const PUBLIC_PORT = $publicPort;
"@
    $configB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($configPhp))

    $css = @'
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=Vazirmatn:wght@400;500;600;700;800&display=swap');
:root{color-scheme:light;--bg:#f3f6fb;--surface:#fff;--surface-2:#f8faff;--text:#182230;--muted:#718096;--line:#e5eaf2;--blue:#1769e0;--blue-soft:#e9f1ff;--green:#16845b;--green-soft:#e6f7ef;--orange:#b96a11;--orange-soft:#fff2df;--purple:#7054d8;--shadow:0 8px 28px rgba(31,53,87,.055);--radius:18px}
*{box-sizing:border-box}html{min-height:100%;scroll-behavior:smooth}body{margin:0;background:var(--bg);color:var(--text);font-family:Inter,Vazirmatn,"Segoe UI",sans-serif;font-size:14px;line-height:1.55;transition:background .25s,color .25s}html[dir="rtl"] body{font-family:Vazirmatn,Inter,"Segoe UI",sans-serif}button,input{font:inherit}button{cursor:pointer}.svg-icon{width:19px;height:19px;display:inline-block;vertical-align:middle;flex-shrink:0}.app-shell{min-height:100vh}.sidebar{position:fixed;inset-block:0;inset-inline-start:0;width:248px;padding:28px 18px;background:var(--surface);border-inline-end:1px solid var(--line);display:flex;flex-direction:column;z-index:5}.brand{display:flex;align-items:center;gap:12px;padding:0 8px 34px;color:inherit;text-decoration:none}.brand-mark{width:44px;height:44px;display:grid;place-items:center;background:linear-gradient(145deg,#2878f0,#1352bd);color:#fff;border-radius:14px;box-shadow:0 7px 16px #1769e033}.brand-mark .svg-icon{width:25px;height:25px}.brand strong{display:block;font-size:20px;letter-spacing:.07em;font-weight:800}.brand small{display:block;color:var(--muted);font-size:9px;letter-spacing:.055em;white-space:nowrap}.side-label{padding:0 12px 10px;text-transform:uppercase;color:var(--muted);font-size:10px;font-weight:700;letter-spacing:.09em}.side-active{display:flex;align-items:center;gap:12px;padding:13px 14px;border-radius:12px;color:var(--blue);background:var(--blue-soft);font-weight:700}.sidebar-bottom{margin-top:auto;display:flex;align-items:center;gap:9px;padding:16px 10px;color:var(--muted);font-size:11px;border-top:1px solid var(--line)}.online-dot{width:8px;height:8px;background:#21b879;border-radius:50%;box-shadow:0 0 0 4px #21b8791c}.main-content{margin-inline-start:248px;padding:30px clamp(18px,3vw,44px) 22px;max-width:1700px}.topbar{display:flex;justify-content:space-between;align-items:center;gap:20px;margin-bottom:26px}.breadcrumb{font-size:11px;color:var(--muted);margin-bottom:8px}.breadcrumb span{padding:0 8px;color:#b4bfce}.topbar h1{margin:0;font-size:clamp(23px,2.2vw,30px);letter-spacing:-.035em;font-weight:800}.topbar p{margin:5px 0 0;color:var(--muted)}.top-actions,.panel-tools,.row-actions{display:flex;align-items:center;gap:10px}.top-actions form{margin:0}.icon-btn{display:inline-grid;place-items:center;width:40px;height:40px;background:var(--surface);border:1px solid var(--line);border-radius:12px;color:var(--muted);transition:transform .2s,border-color .2s,background .2s}.icon-btn:hover:not(:disabled){transform:translateY(-2px);border-color:#a9c8f7;color:var(--blue)}.icon-btn:disabled{opacity:.38;cursor:not-allowed}.inline-action{display:inline;margin:0}.password-form{display:flex;flex-wrap:wrap;gap:14px;padding:20px 24px;align-items:end}.password-form label{display:grid;gap:7px;flex:1;min-width:180px;font-size:12px;font-weight:650}.password-form input{height:40px;padding:0 12px;border:1px solid var(--line);border-radius:10px;background:var(--surface-2);color:var(--text);min-width:0}.alert-success{color:#14784d;background:#e8f8f0;border:1px solid #c5efda}.theme-colors{display:flex;gap:7px;align-items:center;padding:0 3px}.color-swatch{width:18px;height:18px;border:2px solid var(--surface);outline:1px solid var(--line);border-radius:50%;padding:0}.color-swatch[aria-pressed=true]{outline:2px solid var(--text);outline-offset:2px}.icon-btn.danger{color:#d14343}.language-btn{height:40px;padding:0 14px;border:1px solid var(--line);border-radius:12px;background:var(--surface);color:var(--text);font-weight:600}.btn{min-height:40px;padding:0 14px;display:inline-flex;align-items:center;justify-content:center;gap:8px;border-radius:11px;border:1px solid transparent;font-weight:650;transition:transform .2s,box-shadow .2s}.btn:hover{transform:translateY(-1px)}.btn-primary{background:var(--blue);color:white;box-shadow:0 5px 12px #1769e020}.btn-primary:hover{box-shadow:0 8px 18px #1769e032}.btn-ghost{background:var(--surface);border-color:var(--line);color:var(--text)}.welcome-strip{position:relative;overflow:hidden;display:flex;align-items:center;justify-content:space-between;min-height:154px;padding:28px 32px;margin-bottom:22px;border:1px solid #cfe0fc;border-radius:var(--radius);background:linear-gradient(110deg,#eaf2ff 0%,#f7faff 58%,#e8f1ff 100%);animation:rise-in .55s both}.welcome-copy{position:relative;z-index:1}.eyebrow{font-size:10px;font-weight:800;letter-spacing:.12em;color:var(--blue)}.welcome-strip h2{margin:7px 0 4px;font-size:23px;letter-spacing:-.025em}.welcome-strip p{margin:0;color:#61738c}.welcome-art{position:absolute;inset-inline-end:6%;top:50%;transform:translateY(-50%);width:118px;height:118px;border-radius:34px;display:grid;place-items:center;color:#1769e0;background:#ffffffa6;box-shadow:0 15px 35px #1769e01a;rotate:-8deg}.welcome-art .svg-icon{width:66px;height:66px;stroke-width:1.2}.stats-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:16px;margin-bottom:24px}.stat-card{position:relative;min-width:0;padding:21px 20px 18px;background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);box-shadow:var(--shadow);animation:rise-in .55s both}.stat-card:nth-child(2){animation-delay:.06s}.stat-card:nth-child(3){animation-delay:.12s}.stat-card:nth-child(4){animation-delay:.18s}.stat-icon{width:39px;height:39px;display:grid;place-items:center;border-radius:12px;margin-bottom:17px}.stat-icon.blue{background:var(--blue-soft);color:var(--blue)}.stat-icon.green{background:var(--green-soft);color:var(--green)}.stat-icon.orange{background:var(--orange-soft);color:var(--orange)}.stat-icon.purple{background:#f0ecff;color:var(--purple)}.stat-label{display:block;color:var(--muted);font-size:12px;font-weight:600}.stat-card>strong{display:block;font-size:29px;line-height:1.3;letter-spacing:-.04em;margin:4px 0 7px;font-weight:800;overflow-wrap:anywhere}.stat-card small{display:block;font-size:10px;color:var(--muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.stat-card code{font-family:ui-monospace,monospace;font-size:10px}.files-panel{background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);box-shadow:var(--shadow);overflow:hidden;animation:rise-in .6s .12s both}.panel-heading{padding:24px 25px;display:flex;align-items:center;justify-content:space-between;gap:18px;border-bottom:1px solid var(--line)}.panel-heading h2{display:flex;align-items:center;gap:9px;margin:0;font-size:17px;font-weight:750}.panel-heading h2 .svg-icon{color:var(--blue)}.panel-heading p{margin:5px 0 0;color:var(--muted);font-size:12px}.search-box{display:flex;align-items:center;gap:9px;width:min(260px,35vw);height:40px;padding:0 12px;background:var(--surface-2);border:1px solid var(--line);border-radius:11px;color:var(--muted)}.search-box input{width:100%;min-width:0;border:0;outline:0;background:transparent;color:var(--text)}.table-wrap{width:100%;overflow-x:auto}table{border-collapse:collapse;width:100%;min-width:780px;text-align:start}th{padding:14px 22px;background:var(--surface-2);color:var(--muted);font-size:10px;text-transform:uppercase;letter-spacing:.045em;font-weight:750;white-space:nowrap}td{padding:16px 22px;border-top:1px solid var(--line);font-size:12px}tbody tr{transition:background .2s}tbody tr:hover{background:var(--surface-2)}.file-name{display:flex;align-items:center;gap:11px;min-width:250px}.file-icon{display:grid;place-items:center;width:37px;height:40px;border:1px solid var(--line);border-radius:10px;background:var(--surface-2);color:var(--blue)}.file-name strong{display:block;font-size:12px;font-weight:700;overflow-wrap:anywhere}.file-name small{display:block;margin-top:3px;color:var(--muted);font-size:10px}.nowrap{white-space:nowrap}.status-pill{display:inline-flex;align-items:center;gap:7px;padding:6px 9px;border-radius:99px;font-size:10px;font-weight:700;white-space:nowrap}.status-pill i{width:6px;height:6px;border-radius:50%;background:currentColor}.status-sent{background:var(--green-soft);color:var(--green)}.status-failed{background:#ffebeb;color:#bf3434}.status-pending{background:var(--orange-soft);color:var(--orange)}.row-actions{gap:6px}.row-actions .icon-btn{width:34px;height:34px;border-radius:9px}.panel-footer{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:15px 24px;color:var(--muted);font-size:11px;border-top:1px solid var(--line)}.footer-secure{display:flex;align-items:center;gap:6px}.footer-secure .svg-icon{width:15px;height:15px;color:var(--green)}.empty-state{display:flex;min-height:170px;align-items:center;justify-content:center;flex-direction:column;gap:12px;color:var(--muted)}.empty-state .svg-icon{width:35px;height:35px;opacity:.55}.app-footer{display:flex;justify-content:space-between;gap:12px;padding:20px 2px 0;color:var(--muted);font-size:10px}.login-page{min-height:100vh;display:grid;place-items:center;padding:24px;background:radial-gradient(ellipse at 10% 10%,#dbeafe 0,transparent 42%),var(--bg)}.login-card{width:min(100%,430px);padding:36px;background:var(--surface);border:1px solid var(--line);border-radius:24px;box-shadow:0 24px 70px #23395b12;animation:rise-in .5s both}.login-card>.brand-mark{margin-bottom:23px}.login-card h1{margin:7px 0;font-size:27px}.muted{color:var(--muted)}.login-form{display:grid;gap:9px;margin-top:25px}.login-form label{font-size:12px;font-weight:700}.login-form input{width:100%;height:48px;padding:0 13px;border:1px solid var(--line);border-radius:11px;background:var(--surface-2);color:var(--text);outline:none}.login-form input:focus{border-color:var(--blue);box-shadow:0 0 0 3px #1769e018}.login-form .btn{margin-top:8px;height:47px}.btn-icon{display:inline-flex}.login-foot{margin:22px 0 0;padding-top:17px;border-top:1px solid var(--line);color:var(--muted);font-size:10px;text-align:center}.alert{padding:11px 13px;border-radius:10px;margin-top:15px}.alert-error{color:#b42323;background:#fff0f0;border:1px solid #ffd9d9}
html[data-theme="dark"]{color-scheme:dark;--bg:#10151e;--surface:#171e29;--surface-2:#1c2532;--text:#edf2fa;--muted:#9aa8bc;--line:#2a3545;--blue:#75aaff;--blue-soft:#1d3455;--green:#5ad2a1;--green-soft:#173b31;--orange:#ffc16f;--orange-soft:#3d2d1b;--purple:#b7a6ff;--shadow:0 8px 28px rgba(0,0,0,.12)}html[data-theme="dark"] .welcome-strip{background:linear-gradient(110deg,#1b2c45,#1a2433 65%,#202b3c);border-color:#304662}html[data-theme="dark"] .welcome-strip p{color:#a9bad2}html[data-theme="dark"] .welcome-art{background:#273a54;color:#8db9ff}html[data-theme="dark"] .status-failed{background:#422626;color:#ff9d9d}html[data-theme="dark"] .login-page{background:radial-gradient(ellipse at 10% 10%,#1a2c46 0,transparent 42%),var(--bg)}html[data-theme="dark"] .alert-error{background:#422626;color:#ffb2b2;border-color:#633232}
@keyframes rise-in{from{opacity:0;transform:translateY(10px)}to{opacity:1;transform:translateY(0)}}@media(prefers-reduced-motion:reduce){*,*::before,*::after{animation-duration:.01ms!important;animation-iteration-count:1!important;scroll-behavior:auto!important;transition-duration:.01ms!important}}
@media(max-width:1200px){.stats-grid{grid-template-columns:repeat(2,minmax(0,1fr))}.sidebar{width:220px}.main-content{margin-inline-start:220px;padding-inline:24px}.panel-heading{align-items:flex-start;flex-direction:column}.panel-tools{width:100%}.search-box{flex:1;width:auto}}
@media(max-width:760px){.password-form{padding:16px;display:grid}.password-form label{min-width:0}.theme-colors{gap:5px}.sidebar{position:static;width:auto;height:auto;padding:13px 16px;border-inline-end:0;border-bottom:1px solid var(--line)}.brand{padding:0;gap:10px}.brand-mark{width:38px;height:38px;border-radius:12px}.brand strong{font-size:17px}.sidebar .side-label,.sidebar .side-active,.sidebar-bottom{display:none}.main-content{margin:0;padding:21px 14px 18px}.topbar{align-items:flex-start;margin-bottom:20px;gap:12px}.topbar h1{font-size:23px}.topbar p{font-size:12px;max-width:270px}.top-actions{gap:6px;flex-wrap:wrap;justify-content:flex-end}.top-actions .btn{width:40px;padding:0;font-size:0}.top-actions .btn .svg-icon{width:18px}.language-btn,.icon-btn{height:38px}.language-btn{padding:0 10px}.welcome-strip{min-height:145px;padding:22px 20px}.welcome-strip h2{font-size:19px}.welcome-strip p{max-width:65%;font-size:11px}.welcome-art{width:75px;height:75px;inset-inline-end:5%;border-radius:23px}.welcome-art .svg-icon{width:45px;height:45px}.stats-grid{gap:10px;margin-bottom:16px}.stat-card{padding:15px;border-radius:14px}.stat-icon{width:33px;height:33px;margin-bottom:11px}.stat-card>strong{font-size:24px}.stat-card small{font-size:9px}.files-panel{border-radius:15px}.panel-heading{padding:18px 16px}.panel-heading h2{font-size:15px}.panel-tools{gap:7px}.panel-tools .btn{padding:0 10px}.panel-tools .btn span{display:none}.search-box{min-width:0}.panel-footer{padding:13px 15px;align-items:flex-start;flex-direction:column}.app-footer{flex-direction:column;gap:5px}.login-card{padding:27px 23px}}
@media(max-width:390px){.topbar{flex-direction:column}.top-actions{width:100%;justify-content:flex-start}.stats-grid{grid-template-columns:repeat(2,minmax(0,1fr))}.stat-card{padding:13px}.stat-card>strong{font-size:22px}.welcome-art{opacity:.55}.welcome-strip p{max-width:75%}}
'@
    $js = @'
(function(){
  const root=document.documentElement;
  const savedTheme=(()=>{try{return localStorage.getItem('atd-theme')}catch(e){return null}})();
  if(savedTheme==='dark')root.dataset.theme='dark';
  const theme=document.getElementById('themeToggle');
  if(theme)theme.addEventListener('click',function(){const dark=root.dataset.theme!=='dark';if(dark)root.dataset.theme='dark';else delete root.dataset.theme;try{localStorage.setItem('atd-theme',dark?'dark':'light')}catch(e){}});
  const accents=['#1769e0','#0d9488','#7c3aed','#db2777','#ea580c'];
  const savedAccent=(()=>{try{return localStorage.getItem('atd-accent')}catch(e){return null}})();
  function setAccent(color){if(!accents.includes(color))return;root.style.setProperty('--blue',color);root.style.setProperty('--accent',color);root.style.setProperty('--blue-soft',color+'20');document.querySelectorAll('[data-accent]').forEach(b=>b.setAttribute('aria-pressed',b.dataset.accent===color?'true':'false'));try{localStorage.setItem('atd-accent',color)}catch(e){}}
  if(savedAccent)setAccent(savedAccent);
  document.querySelectorAll('[data-accent]').forEach(b=>b.addEventListener('click',()=>setAccent(b.dataset.accent)));
  const lang=document.getElementById('languageToggle');
  if(lang)lang.addEventListener('click',function(){const next=(document.documentElement.lang==='fa')?'en':'fa';document.cookie='atd_lang='+next+'; path=/; max-age=31536000; SameSite=Lax';location.reload()});
  const search=document.getElementById('backupSearch');
  if(search)search.addEventListener('input',function(){const q=this.value.trim().toLocaleLowerCase();document.querySelectorAll('#backupTable tbody tr[data-search]').forEach(function(row){row.hidden=!row.dataset.search.toLocaleLowerCase().includes(q)})});
})();
'@

    $cssHash = Get-Sha256Text $css
    $jsHash = Get-Sha256Text $js

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
BASE='https://raw.githubusercontent.com/PardisMobile/ATD-Mikrotik-Backup-Studio/main/server-deployment'
TMP="$(mktemp -d /tmp/atd-bootstrap.XXXXXX)"
chmod 0700 "$TMP"
trap 'rm -rf -- "$TMP"' EXIT
fetch_asset() {
  local name="$1" expected="$2"
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --max-time 60 "$BASE/$name" -o "$TMP/$name"
  [[ -s "$TMP/$name" ]] || { echo "Downloaded asset is empty: $name" >&2; exit 5; }
  printf '%s  %s\n' "$expected" "$TMP/$name" | sha256sum --check --status || {
    echo "Asset checksum mismatch: $name. This package and GitHub assets are from different revisions; regenerate the package." >&2
    exit 5
  }
}
fetch_asset 'send-backup.php' '__PHP_SHA256__'
fetch_asset 'panel.css' '__CSS_SHA256__'
fetch_asset 'panel.js' '__JS_SHA256__'
printf '%s' '__CONFIG_B64__' | base64 --decode > "$TMP/config.php"
chmod 0600 "$TMP/config.php"
if command -v php >/dev/null 2>&1; then
  php -l "$TMP/config.php" >/dev/null || { echo 'Generated private configuration failed PHP syntax validation.' >&2; exit 6; }
fi
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --max-time 60 'https://raw.githubusercontent.com/PardisMobile/ATD-Mikrotik-Backup-Studio/main/server-deployment/install-standalone.sh' -o "$TMP/install-standalone.sh"
[[ -s "$TMP/install-standalone.sh" ]] || { echo 'Could not download the ATD runtime installer.' >&2; exit 5; }
chmod 0600 "$TMP/install-standalone.sh"
bash "$TMP/install-standalone.sh" "$TMP"
'@
    $installServer = $installServer.Replace('__PHP_SHA256__', $phpHash).
                                    Replace('__CSS_SHA256__', $cssHash).
                                    Replace('__JS_SHA256__', $jsHash).
                                    Replace('__CONFIG_B64__', $configB64)
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
$terminalSetup = '/system script add name="' + $scriptName + '" policy=ftp,password,read,write,policy,sensitive,test source={' + "`r`n" + $routerScript + "`r`n}" + "`r`n" + $scheduler
[System.IO.File]::WriteAllText((Join-Path $outDir 'paste-into-routeros-terminal.txt'), $terminalSetup, [System.Text.UTF8Encoding]::new($false))

$readme = @"
ATD MikroTik Backup Studio
RouterOS 7 scheduled backups over SFTP, with optional Telegram delivery and a password-protected panel.

OUTPUT
- paste-into-routeros-terminal.txt: paste the complete file into MikroTik Terminal.
- install.sh: customer-specific server bootstrap. It contains secret configuration; do not share it publicly.
- router-backup.rsc: RouterOS script source.
- create-sftp-directory.txt: command to create the remote SFTP folder if needed.

INSTALL
1. Transfer install.sh to the Linux server using a secure method.
2. Run: sudo bash install.sh
3. The installer fetches version-matched panel code from GitHub, checks SHA-256 hashes, creates the private server configuration, and installs the panel.
4. Paste paste-into-routeros-terminal.txt into MikroTik Terminal.
5. Open the HTTPS URL printed by the installer and sign in with the initial panel password.

The server installer is generated for Telegram/panel mode. In SFTP-only mode, no panel installer is needed; use the RouterOS output and create-sftp-directory.txt as required.
The installer uses ATD-specific paths and services. It does not edit existing Nginx/Apache configuration. A self-signed TLS certificate may cause a browser warning. Keep install.sh private because it contains the initial configuration.
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
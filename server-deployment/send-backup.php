<?php
declare(strict_types=1);
require_once '/etc/atd-mikrotik-backup-studio/config.php';
const STABILITY_CHECKS = 3;
const STABILITY_INTERVAL_SECONDS = 2;
const MAX_WAIT_SECONDS = 90;

if (PHP_SAPI !== 'cli') session_name_guard();

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
function telegram_settings(): array {
    $state = load_state();
    $saved = $state['_telegram_settings'] ?? [];
    $token = is_array($saved) ? trim((string)($saved['bot_token'] ?? '')) : '';
    $chat = is_array($saved) ? trim((string)($saved['chat_id'] ?? '')) : '';
    // Backward compatibility for installations created by older generators.
    if ($token === '') $token = defined('TELEGRAM_BOT_TOKEN') ? trim((string)TELEGRAM_BOT_TOKEN) : '';
    if ($chat === '') $chat = defined('TELEGRAM_CHAT_ID') ? trim((string)TELEGRAM_CHAT_ID) : '';
    return ['bot_token'=>$token, 'chat_id'=>$chat];
}
function valid_telegram_settings(string $token, string $chat): bool {
    return (bool)preg_match('/\A[0-9]{5,}:[A-Za-z0-9_-]{20,}\z/', $token)
        && (bool)preg_match('/\A-?[0-9]{1,20}\z/', $chat);
}
function telegram_api(string $token, string $method, array $fields = []): array {
    $ch = curl_init('https://api.telegram.org/bot'.$token.'/'.$method);
    curl_setopt_array($ch, [CURLOPT_POST=>true, CURLOPT_POSTFIELDS=>$fields, CURLOPT_RETURNTRANSFER=>true,
        CURLOPT_CONNECTTIMEOUT=>12, CURLOPT_TIMEOUT=>30, CURLOPT_SSL_VERIFYPEER=>true, CURLOPT_SSL_VERIFYHOST=>2]);
    $response = curl_exec($ch); $error = curl_error($ch); $http = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE); curl_close($ch);
    $data = is_string($response) ? json_decode($response, true) : null;
    return ['ok'=>$error==='' && $http>=200 && $http<300 && is_array($data) && ($data['ok']??false)===true,
        'http'=>$http, 'error'=>$error, 'data'=>is_array($data)?$data:[]];
}
function send_telegram_file(string $name, bool $force = false): array {
    $tg = telegram_settings();
    if (!valid_telegram_settings($tg['bot_token'], $tg['chat_id'])) return [false, 'TELEGRAM_NOT_CONFIGURED'];
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
    $ch=curl_init('https://api.telegram.org/bot'.$tg['bot_token'].'/sendDocument');
    curl_setopt_array($ch,[CURLOPT_POST=>true,CURLOPT_POSTFIELDS=>['chat_id'=>$tg['chat_id'],'document'=>new CURLFile($path,'application/octet-stream',$name),'caption'=>'MikroTik backup: '.$name],CURLOPT_RETURNTRANSFER=>true,CURLOPT_CONNECTTIMEOUT=>15,CURLOPT_TIMEOUT=>180,CURLOPT_SSL_VERIFYPEER=>true,CURLOPT_SSL_VERIFYHOST=>2]);
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
        } elseif ($action==='telegram_settings') {
            $current=telegram_settings();
            $token=trim((string)($_POST['bot_token']??'')); $chat=trim((string)($_POST['chat_id']??''));
            if ($token==='') $token=$current['bot_token'];
            if (!valid_telegram_settings($token,$chat)) $_SESSION['flash']=['ok'=>false,'message'=>'TELEGRAM_SETTINGS_INVALID'];
            else {
                $test=telegram_api($token,'getMe');
                if (!$test['ok']) $_SESSION['flash']=['ok'=>false,'message'=>'TELEGRAM_TOKEN_INVALID'];
                else {
                    $st=load_state(); $st['_telegram_settings']=['bot_token'=>$token,'chat_id'=>$chat,'updated_at'=>gmdate('c')];
                    $_SESSION['flash']=save_state($st)?['ok'=>true,'message'=>'TELEGRAM_SETTINGS_SAVED']:['ok'=>false,'message'=>'STATE_SAVE_FAILED'];
                }
            }
        } elseif ($action==='telegram_test') {
            $tg=telegram_settings();
            if (!valid_telegram_settings($tg['bot_token'],$tg['chat_id'])) $_SESSION['flash']=['ok'=>false,'message'=>'TELEGRAM_NOT_CONFIGURED'];
            else {
                $test=telegram_api($tg['bot_token'],'sendMessage',['chat_id'=>$tg['chat_id'],'text'=>'ATD MikroTik Backup Studio: Telegram connection test successful.']);
                $_SESSION['flash']=$test['ok']?['ok'=>true,'message'=>'TELEGRAM_TEST_OK']:['ok'=>false,'message'=>'TELEGRAM_TEST_FAILED'];
            }
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
    $tg=telegram_settings(); $tgConfigured=valid_telegram_settings($tg['bot_token'],$tg['chat_id']);
    $tgChatDisplay=$tg['chat_id'];
    echo '<section class="files-panel telegram-panel"><div class="panel-heading"><div><h2>'.icon_svg('send').' '.esc($isEn?'Telegram delivery settings':'تنظیمات اتصال تلگرام').'</h2><p>'.esc($isEn?'Configure or replace your bot credentials here; the generator no longer asks for them.':'توکن ربات و چت مقصد را اینجا وارد یا هر زمان لازم شد تغییر دهید؛ جنراتور دیگر این اطلاعات را نمی‌پرسد.').'</p></div><span class="status-pill '.($tgConfigured?'status-sent':'status-pending').'"><i></i>'.esc($tgConfigured?($isEn?'Configured':'تنظیم‌شده'):($isEn?'Setup required':'نیازمند تنظیم')).'</span></div><div class="telegram-guides"><article class="guide-card"><span class="guide-step">01</span><h3>'.esc($isEn?'Get a Bot Token':'دریافت Bot Token').'</h3><p>'.($isEn?'Open Telegram and message @BotFather. Run /newbot (or select your existing bot), then copy its API token. Keep it secret, and open your bot and press Start before testing delivery.':'در تلگرام به @BotFather پیام بدهید؛ دستور /newbot را اجرا کنید یا ربات قبلی را انتخاب کنید و API Token را کپی کنید. توکن را محرمانه نگه دارید؛ سپس وارد ربات خودتان شوید و Start را بزنید.').'</p><a class="guide-link" href="https://t.me/BotFather" target="_blank" rel="noopener noreferrer">@BotFather ↗</a></article><article class="guide-card"><span class="guide-step">02</span><h3>'.esc($isEn?'Find your Chat ID':'پیدا کردن Chat ID').'</h3><p>'.($isEn?'Open @userinfobot and press Start. Copy the numeric ID it shows. For a group, add your bot to the group and use that group’s ID instead.':'به @userinfobot پیام بدهید و Start را بزنید؛ عددی که نمایش می‌دهد Chat ID شماست. برای گروه، ربات را به گروه اضافه کنید و شناسه همان گروه را وارد کنید.').'</p><a class="guide-link" href="https://t.me/userinfobot" target="_blank" rel="noopener noreferrer">@userinfobot ↗</a></article></div><form method="post" class="telegram-form"><input type="hidden" name="csrf" value="'.esc($csrf).'"><input type="hidden" name="action" value="telegram_settings"><label>'.esc($isEn?'Bot Token':'توکن ربات (Bot Token)').'<input type="password" name="bot_token" autocomplete="new-password" placeholder="'.esc($tgConfigured?($isEn?'Leave blank to keep current token':'برای حفظ توکن فعلی خالی بگذارید'):($isEn?'Paste token from @BotFather':'توکن دریافتی از BotFather را وارد کنید')).'"><small>'.esc($isEn?'Tokens are stored on the server and never displayed back.':'توکن در سرور ذخیره می‌شود و دوباره به‌صورت متن نمایش داده نمی‌شود.').'</small></label><label>'.esc($isEn?'Destination Chat ID':'شناسه مقصد (Chat ID)').'<input type="text" name="chat_id" required inputmode="numeric" pattern="-?[0-9]{1,20}" value="'.esc($tgChatDisplay).'" placeholder="'.esc($isEn?'e.g. 123456789 or -100…':'مثلاً 123456789 یا -100…').'"><small>'.esc($isEn?'Numeric IDs only; group IDs are often negative.':'شناسه عددی؛ شناسه گروه‌ها معمولاً منفی است.').'</small></label><div class="telegram-actions"><button class="btn btn-primary" type="submit">'.esc($isEn?'Save Telegram settings':'ذخیره تنظیمات تلگرام').'</button></div></form><form method="post" class="telegram-test-form"><input type="hidden" name="csrf" value="'.esc($csrf).'"><input type="hidden" name="action" value="telegram_test"><button class="btn btn-ghost" type="submit" '.(!$tgConfigured?'disabled':'').'>'.icon_svg('send').' '.esc($isEn?'Send test message':'ارسال پیام آزمایشی').'</button><small>'.esc($isEn?'Sends one visible test message to the configured chat.':'یک پیام آزمایشی واقعی به چت تنظیم‌شده ارسال می‌کند.').'</small></form></section>';
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

if (PHP_SAPI === 'cli' && in_array('--worker', $argv ?? [], true)) {
    $marker = '/var/lib/atd-mikrotik-backup-studio/worker-started-at';
    if (!is_file($marker)) {
        @file_put_contents($marker, (string)time(), LOCK_EX);
        exit(0); // First run establishes a baseline; never bulk-send historical backups.
    }
    $startedAt = (int)trim((string)@file_get_contents($marker));
    if ($startedAt < 1) { fwrite(STDERR, "Invalid worker start marker.\\n"); exit(1); }
    $tg = telegram_settings();
    if (!valid_telegram_settings($tg['bot_token'], $tg['chat_id'])) {
        fwrite(STDOUT, "Telegram is not configured; automatic delivery skipped.\\n");
        exit(0);
    }
    $base = realpath(BACKUP_DIR);
    if ($base === false || !is_readable($base)) { fwrite(STDERR, "Backup directory is not readable.\\n"); exit(1); }
    $state = load_state();
    foreach (glob($base . DIRECTORY_SEPARATOR . '*.backup') ?: [] as $path) {
        if (!is_file($path) || !is_readable($path)) continue;
        $name = basename($path);
        $mtime = @filemtime($path);
        if ($mtime === false || $mtime < $startedAt) continue;
        if (!preg_match('/\\A[A-Za-z0-9_. -]+\\.backup\\z/', $name)) {
            fwrite(STDERR, "Skipped unsupported backup filename: " . $name . "\\n");
            continue;
        }
        clearstatcache(true, $path);
        $hash = @hash_file('sha256', $path);
        if (!is_string($hash)) continue;
        $entry = $state[$name] ?? [];
        if (($entry['sha256'] ?? '') === $hash && ($entry['status'] ?? '') === 'sent') continue;
        $lastAttempt = strtotime((string)($entry['failed_at'] ?? $entry['attempted_at'] ?? '')) ?: 0;
        if (($entry['sha256'] ?? '') === $hash && ($entry['status'] ?? '') === 'failed' && $lastAttempt > time() - 900) continue;
        [$ok, $message] = send_telegram_file($name, false);
        fwrite($ok ? STDOUT : STDERR, $name . ': ' . $message . "\\n");
        $state = load_state();
    }
    exit(0);
}

if ($_SERVER['REQUEST_METHOD'] === 'GET' || (!empty($_SESSION['admin']) && $_SERVER['REQUEST_METHOD'] === 'POST') || (!empty($_POST['login']) && $_SERVER['REQUEST_METHOD'] === 'POST')) {
    render_panel();
    exit;
}
if ($_SERVER['REQUEST_METHOD'] !== 'POST') { http_response_code(405); exit('METHOD_NOT_ALLOWED'); }
$provided = $_SERVER['HTTP_X_BACKUP_TOKEN'] ?? '';
if (!hash_equals(RELAY_TOKEN, $provided)) { http_response_code(403); exit('FORBIDDEN'); }
$tg = telegram_settings();
if (!valid_telegram_settings($tg['bot_token'], $tg['chat_id'])) { http_response_code(503); exit('TELEGRAM_NOT_CONFIGURED'); }
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
$ch = curl_init('https://api.telegram.org/bot' . $tg['bot_token'] . '/sendDocument');
curl_setopt_array($ch, [
    CURLOPT_POST => true,
    CURLOPT_POSTFIELDS => [
        'chat_id' => $tg['chat_id'],
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
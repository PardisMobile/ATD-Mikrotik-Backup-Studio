<?php
declare(strict_types=1);
require_once '/etc/atd-mikrotik-backup-studio/config.php';
const STABILITY_CHECKS = 2;
const STABILITY_INTERVAL_SECONDS = 2;
const MAX_WAIT_SECONDS = 30;

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
    $deadline=time()+MAX_WAIT_SECONDS; $stable=0; $lastSize=-1;
    do {
        clearstatcache(true,$path); $sz=@filesize($path);
        if ($sz === false || $sz < 1) $stable=0;
        elseif ($sz === $lastSize) $stable++;
        else $stable=0;
        $lastSize=$sz===false?-1:$sz;
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
function delivery_schedule_settings(): array {
    $state = load_state();
    $saved = $state['_delivery_schedule'] ?? [];
    if (is_array($saved) && isset($saved['backup_times']) && is_array($saved['backup_times'])) $times = array_values(array_map('strval', $saved['backup_times']));
    elseif (defined('BACKUP_SCHEDULE_TIMES') && is_array(BACKUP_SCHEDULE_TIMES)) $times = array_values(array_map('strval', BACKUP_SCHEDULE_TIMES));
    else $times = [];
    $delay = is_array($saved) && isset($saved['delay_minutes']) ? (int)$saved['delay_minutes'] : (defined('TELEGRAM_DELAY_MINUTES') ? (int)TELEGRAM_DELAY_MINUTES : 2);
    return ['backup_times'=>$times, 'delay_minutes'=>max(0, min(30, $delay))];
}
function normalize_backup_times(string $input): ?array {
    $input = trim($input);
    if ($input === '') return null;
    $parts = preg_split('/\s*,\s*/', $input);
    if (!is_array($parts) || count($parts) < 1 || count($parts) > 2) return null;
    $times = [];
    foreach ($parts as $part) {
        if (!preg_match('/\A([01][0-9]|2[0-3]):([0-5][0-9])\z/', $part)) return null;
        $time = $part . ':00';
        if (in_array($time, $times, true)) return null;
        $times[] = $time;
    }
    return $times;
}
function selected_timezone(): string {
    $state = load_state(); $zone = (string)($state['_timezone'] ?? (defined('DEFAULT_TIMEZONE') ? DEFAULT_TIMEZONE : 'UTC'));
    try { new DateTimeZone($zone); return $zone; } catch (Throwable $e) { return 'UTC'; }
}
function detected_system_timezone(): string {
    // Prefer the active /etc/localtime link because timedatectl changes it at runtime.
    $local=realpath('/etc/localtime');
    if (is_string($local) && str_contains($local,'/zoneinfo/')) { $zone=substr($local,strpos($local,'/zoneinfo/')+10); try { new DateTimeZone($zone); return $zone; } catch (Throwable $e) {} }
    $configured = @file_get_contents('/etc/timezone');
    if (is_string($configured) && trim($configured) !== '') { $zone=trim($configured); try { new DateTimeZone($zone); return $zone; } catch (Throwable $e) {} }
    return date_default_timezone_get();
}
function cron_apply_worker_available(): bool {
    return is_file('/etc/cron.d/atd-mikrotik-backup-apply') && is_readable('/etc/cron.d/atd-mikrotik-backup-apply');
}
function latest_backup_name(): ?string {
    $base = realpath(BACKUP_DIR);
    if ($base === false || !is_readable($base)) return null;
    $files = [];
    foreach (glob($base . DIRECTORY_SEPARATOR . '*.backup') ?: [] as $path) if (is_file($path) && is_readable($path)) $files[] = $path;
    if (!$files) return null;
    usort($files, static fn($a, $b) => filemtime($b) <=> filemtime($a));
    return basename($files[0]);
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
    if (($_GET['ajax'] ?? '') === 'update_status' && !empty($_SESSION['admin'])) {
        header('Content-Type: application/json; charset=utf-8');
        $statusFile='/var/lib/atd-mikrotik-backup-studio/panel-update.status';
        $status=is_readable($statusFile)?trim((string)file_get_contents($statusFile)):'';
        if ($status==='' || !is_array(json_decode($status,true))) $status=json_encode(['status'=>'unavailable','message'=>'Panel updater is not configured yet.']);
        echo $status; exit;
    }
    if ($_SERVER['REQUEST_METHOD'] === 'POST' && empty($_POST['login']) && empty($_POST['logout'])) {
        if (!check_csrf()) { http_response_code(403); exit('Invalid session token. Refresh the page and retry.'); }
        $action=(string)($_POST['action']??''); $name=(string)($_POST['file']??'');
        if ($action==='delete') {
            $base=realpath(BACKUP_DIR); $path=($base!==false && basename($name)===$name && preg_match('/\A[A-Za-z0-9_. -]+\.backup\z/',$name))?realpath($base.DIRECTORY_SEPARATOR.$name):false;
            if ($path!==false && dirname($path)===$base && is_file($path) && @unlink($path)) { $st=load_state(); unset($st[$name]); save_state($st); $_SESSION['flash']=['ok'=>true,'message'=>'DELETED']; }
            else $_SESSION['flash']=['ok'=>false,'message'=>'DELETE_FAILED'];
        } elseif ($action==='password') {
            $old=(string)($_POST['old_password']??''); $new=(string)($_POST['new_password']??'');
            if (!verify_panel_password($old)) $_SESSION['flash']=['ok'=>false,'message'=>'CURRENT_PASSWORD_INVALID'];
            elseif (strlen($new)<8) $_SESSION['flash']=['ok'=>false,'message'=>'PASSWORD_TOO_SHORT'];
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
            if (!valid_telegram_settings($tg['bot_token'],$tg['chat_id'])) {
                $_SESSION['flash']=['ok'=>false,'message'=>'TELEGRAM_NOT_CONFIGURED'];
            } else {
                $latest=latest_backup_name();
                if ($latest===null) $_SESSION['flash']=['ok'=>false,'message'=>'NO_BACKUP_FILES'];
                else {
                    [$ok,$message]=send_telegram_file($latest, true);
                    $_SESSION['flash']=['ok'=>$ok,'message'=>($ok?'TELEGRAM_TEST_OK: ':'TELEGRAM_TEST_FAILED: ').$latest.($ok?'':' ('.$message.')')];
                }
            }
        } elseif ($action==='update_start') {
            $out=[]; $code=1;
            if (!is_executable('/usr/bin/sudo') || !is_executable('/usr/local/sbin/atd-mikrotik-backup-panel-update')) {
                $_SESSION['flash']=['ok'=>false,'message'=>'PANEL_UPDATER_NOT_INSTALLED'];
            } else {
                exec('/usr/bin/sudo -n /usr/local/sbin/atd-mikrotik-backup-panel-update 2>&1',$out,$code);
                $_SESSION['flash']=$code===0?['ok'=>true,'message'=>'UPDATE_STARTED']:['ok'=>false,'message'=>'UPDATE_START_FAILED'];
            }
        } elseif ($action==='timezone') {
            $zone=trim((string)($_POST['timezone']??''));
            if ($zone==='Manual') $zone=trim((string)($_POST['timezone_manual']??''));
            try { new DateTimeZone($zone); } catch (Throwable $e) { $zone=''; }
            if ($zone==='' || !preg_match('/\\A(?:UTC|[A-Za-z_+-]+(?:\\/[A-Za-z0-9_+.-]+)+)\\z/',$zone)) {
                $_SESSION['flash']=['ok'=>false,'message'=>'TIMEZONE_INVALID'];
            } elseif (!cron_apply_worker_available()) {
                $_SESSION['flash']=['ok'=>false,'message'=>'CRON_UPDATE_WORKER_MISSING'];
            } elseif (!is_executable('/usr/bin/sudo') || !is_executable('/usr/local/sbin/atd-mikrotik-backup-set-timezone')) {
                $_SESSION['flash']=['ok'=>false,'message'=>'SYSTEM_TIMEZONE_HELPER_MISSING'];
            } else {
                $st=load_state(); $oldZone=$st['_timezone']??null;
                $st['_timezone']=$zone; $st['_timezone_updated_at']=gmdate('c');
                if (!save_state($st)) {
                    $_SESSION['flash']=['ok'=>false,'message'=>'STATE_SAVE_FAILED'];
                } else {
                    $requestPath=dirname(STATE_FILE).'/requested-system-timezone';
                    $requestTmp=$requestPath.'.tmp';
                    $written=@file_put_contents($requestTmp,$zone."\n",LOCK_EX);
                    if ($written===false || !@chmod($requestTmp,0600) || !@rename($requestTmp,$requestPath)) {
                        @unlink($requestTmp);
                        $restore=load_state(); if ($oldZone===null) unset($restore['_timezone']); else $restore['_timezone']=$oldZone; save_state($restore);
                        $_SESSION['flash']=['ok'=>false,'message'=>'SYSTEM_TIMEZONE_REQUEST_FAILED'];
                    } else {
                        $out=[]; $code=1;
                        exec('/usr/bin/sudo -n /usr/local/sbin/atd-mikrotik-backup-set-timezone 2>&1',$out,$code);
                        if ($code===0) {
                            $_SESSION['flash']=['ok'=>true,'message'=>'TIMEZONE_SAVED_SYSTEM_AND_CRON'];
                        } else {
                            $restore=load_state(); if ($oldZone===null) unset($restore['_timezone']); else $restore['_timezone']=$oldZone; save_state($restore);
                            @file_put_contents($requestTmp,detected_system_timezone()."\n",LOCK_EX); @chmod($requestTmp,0600); @rename($requestTmp,$requestPath);
                            $_SESSION['flash']=['ok'=>false,'message'=>'SYSTEM_TIMEZONE_APPLY_FAILED'];
                        }
                    }
                }
            }
        } elseif ($action==='delivery_schedule') {
            $times=normalize_backup_times((string)($_POST['backup_times']??''));
            $delayRaw=(string)($_POST['delay_minutes']??'2');
            if ($times===null || !preg_match('/\A(?:[0-9]|[12][0-9]|30)\z/',$delayRaw)) {
                $_SESSION['flash']=['ok'=>false,'message'=>'DELIVERY_SCHEDULE_INVALID'];
            } else {
                $oldState=load_state(); $oldSchedule=$oldState['_delivery_schedule']??null;
                $oldState['_delivery_schedule']=['backup_times'=>$times,'delay_minutes'=>(int)$delayRaw,'updated_at'=>gmdate('c')];
                if (!save_state($oldState)) $_SESSION['flash']=['ok'=>false,'message'=>'STATE_SAVE_FAILED'];
                elseif (!cron_apply_worker_available()) {
                    $restored=load_state();
                    if ($oldSchedule===null) unset($restored['_delivery_schedule']); else $restored['_delivery_schedule']=$oldSchedule;
                    save_state($restored);
                    $_SESSION['flash']=['ok'=>false,'message'=>'CRON_UPDATE_WORKER_MISSING'];
                } else $_SESSION['flash']=['ok'=>true,'message'=>'DELIVERY_SCHEDULE_SAVED (Cron applies within one minute)'];
            }
        }
        header('Location: '.$_SERVER['PHP_SELF']); exit;
    }
    $csrf=csrf_token();
    $systemTimezone=detected_system_timezone(); $selectedTimezone=selected_timezone();
    try { $serverNow=(new DateTimeImmutable('now',new DateTimeZone($systemTimezone)))->format('Y-m-d H:i:s'); } catch (Throwable $e) { $serverNow=date('Y-m-d H:i:s'); }
    $flash=$_SESSION['flash']??null; unset($_SESSION['flash']);
    $base=realpath(BACKUP_DIR); $files=[];
    if ($base !== false && is_readable($base)) { foreach (glob($base.DIRECTORY_SEPARATOR.'*.backup') ?: [] as $f) { if (is_file($f) && is_readable($f)) $files[]=$f; } }
    usort($files, fn($a,$b)=>filemtime($b)<=>filemtime($a)); $state=load_state();
    $allFiles=$files; $searchQuery=trim((string)($_GET['q']??''));
    if ($searchQuery!=='') $files=array_values(array_filter($files, static fn($path)=>stripos(basename($path),$searchQuery)!==false));
    $totalFiles=count($files); $perPage=20; $totalPages=max(1,(int)ceil($totalFiles/$perPage)); $currentPage=max(1,min($totalPages,(int)($_GET['page']??1))); $filesOnPage=array_slice($files,($currentPage-1)*$perPage,$perPage);
    $totalBytes=0; foreach($allFiles as $f) { $totalBytes += (int)filesize($f); }
    $sentCount=0; $failedCount=0; foreach($allFiles as $f) { $st=$state[basename($f)]['status']??''; if($st==='sent')$sentCount++; elseif($st==='failed')$failedCount++; }
    $lang = (($_COOKIE['atd_lang'] ?? 'fa') === 'en') ? 'en' : 'fa'; $isEn = $lang==='en';
    $t = $isEn ? ['title'=>'Backup management','subtitle'=>'Your MikroTik backup files, in one place.','files'=>'Backup files','sent'=>'Sent to Telegram','failed'=>'Failed delivery','storage'=>'Total storage','search'=>'Search backups…','name'=>'File name','size'=>'Size','date'=>'Modified','status'=>'Telegram status','actions'=>'Delete','sent_status'=>'Sent','failed_status'=>'Failed','pending'=>'Not sent','empty'=>'No .backup files found in this directory.','path'=>'Backup directory','logout'=>'Sign out','refresh'=>'Refresh','delete'=>'Delete','confirm'=>'Are you sure you want to delete this backup?','language'=>'فارسی','theme'=>'Toggle theme','settings'=>'Panel','password'=>'Change password','old'=>'Current password','new'=>'New password (8+ characters)','save'=>'Update password','cancel'=>'Cancel','login'=>'Sign in','welcome'=>'Welcome back','secure'=>'Secure backup workspace','bytes'=>'bytes'] : ['title'=>'مدیریت بکاپ‌ها','subtitle'=>'فایل‌های بکاپ میکروتیک، یک‌جا و مرتب.','files'=>'تعداد بکاپ‌ها','sent'=>'ارسال‌شده به تلگرام','failed'=>'ارسال ناموفق','storage'=>'حجم کل فایل‌ها','search'=>'جست‌وجوی بکاپ…','name'=>'نام فایل','size'=>'حجم','date'=>'آخرین تغییر','status'=>'وضعیت تلگرام','actions'=>'حذف','sent_status'=>'ارسال‌شده','failed_status'=>'ناموفق','pending'=>'ارسال‌نشده','empty'=>'فایلی با پسوند .backup در این مسیر پیدا نشد.','path'=>'مسیر بکاپ','logout'=>'خروج','refresh'=>'تازه‌سازی','delete'=>'حذف','confirm'=>'از حذف این فایل بکاپ مطمئن هستید؟','language'=>'English','theme'=>'تغییر تم','settings'=>'پنل','password'=>'تغییر رمز عبور','old'=>'رمز فعلی','new'=>'رمز جدید (حداقل ۸ کاراکتر)','save'=>'ذخیره رمز','cancel'=>'انصراف','login'=>'ورود','welcome'=>'خوش آمدید','secure'=>'محیط امن مدیریت بکاپ','bytes'=>'بایت'];
    echo '<!doctype html><html lang="'.($isEn?'en':'fa').'" dir="'.($isEn?'ltr':'rtl').'"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light dark"><title>ATD · '.esc($t['title']).'</title><link rel="stylesheet" href="panel.css"></head><body><div class="app-shell"><aside class="sidebar"><a class="brand" href="'.esc($_SERVER['PHP_SELF']).'"><span class="brand-mark">'.icon_svg('router').'</span><span><strong>ATD</strong><small>MIKROTIK BACKUP STUDIO</small></span></a><nav class="sidebar-nav" aria-label="'.esc($isEn?'Main navigation':'ناوبری اصلی').'"><button type="button" class="side-tab" data-panel-tab="dashboard">'.icon_svg('layout').'<span>'.esc($isEn?'Dashboard':'داشبورد').'</span></button><button type="button" class="side-tab" data-panel-tab="backups">'.icon_svg('files').'<span>'.esc($isEn?'Backups':'بکاپ‌ها').'</span></button><button type="button" class="side-tab" data-panel-tab="telegram">'.icon_svg('send').'<span>'.esc($isEn?'Telegram':'تلگرام').'</span></button><button type="button" class="side-tab" data-panel-tab="settings">'.icon_svg('shield').'<span>'.esc($isEn?'Settings':'تنظیمات').'</span></button></nav><div class="sidebar-bottom"><span class="online-dot"></span><span>RouterOS 7 · '.($isEn?'Protected':'محافظت‌شده').'</span></div></aside><main class="main-content"><header class="topbar"><div class="topbar-heading"><div class="breadcrumb">ATD <span>/</span> '.esc($t['title']).'</div><h1>'.esc($t['title']).'</h1><p>'.esc($t['subtitle']).'</p></div><div class="server-clock-widget"><span>'.esc($isEn?'Linux server time':'ساعت سرور لینوکس').'</span><time id="serverClockTop" data-server-clock data-epoch="'.time().'" data-timezone="'.esc($systemTimezone).'">'.esc($serverNow).'</time><small>'.esc($systemTimezone).'</small></div><div class="top-actions"><button class="icon-btn" type="button" id="themeToggle" aria-label="'.esc($t['theme']).'">'.icon_svg('moon').'</button><div class="theme-colors" aria-label="Accent color"><button class="color-swatch" style="background:#1769e0" data-accent="#1769e0" aria-label="Blue"></button><button class="color-swatch" style="background:#0d9488" data-accent="#0d9488" aria-label="Teal"></button><button class="color-swatch" style="background:#7c3aed" data-accent="#7c3aed" aria-label="Violet"></button><button class="color-swatch" style="background:#db2777" data-accent="#db2777" aria-label="Rose"></button><button class="color-swatch" style="background:#ea580c" data-accent="#ea580c" aria-label="Orange"></button></div><button class="language-btn" type="button" id="languageToggle">'.esc($t['language']).'</button><form method="post"><button class="btn btn-ghost" name="logout" value="1">'.icon_svg('logout').'<span>'.esc($t['logout']).'</span></button></form></div></header>';
    if (is_array($flash)) echo '<div class="alert '.(!empty($flash['ok'])?'alert-success':'alert-error').'">'.esc((string)($flash['message']??'')).'</div>';
    echo '<section class="welcome-strip" data-panel-section="dashboard"><div class="welcome-copy"><span class="eyebrow">ATD BACKUP CENTER</span><h2>'.esc($t['welcome']).' 👋</h2><p>'.esc($t['secure']).'</p></div><div class="welcome-art" aria-hidden="true">'.icon_svg('cloud').'</div></section>';
    echo '<section class="stats-grid" data-panel-section="dashboard"><article class="stat-card"><span class="stat-icon blue">'.icon_svg('files').'</span><span class="stat-label">'.esc($t['files']).'</span><strong>'.count($allFiles).'</strong><small>'.esc($t['path']).': <code>'.esc(BACKUP_DIR).'</code></small></article><article class="stat-card"><span class="stat-icon green">'.icon_svg('send').'</span><span class="stat-label">'.esc($t['sent']).'</span><strong>'.$sentCount.'</strong><small>'.($isEn?'Successful deliveries':'ارسال‌های موفق ثبت‌شده').'</small></article><article class="stat-card"><span class="stat-icon orange">'.icon_svg('alert').'</span><span class="stat-label">'.esc($t['failed']).'</span><strong>'.$failedCount.'</strong><small>'.($isEn?'Files needing attention':'فایل‌های نیازمند بررسی').'</small></article><article class="stat-card"><span class="stat-icon purple">'.icon_svg('database').'</span><span class="stat-label">'.esc($t['storage']).'</span><strong>'.esc(format_bytes($totalBytes)).'</strong><small>'.($isEn?'Combined backup size':'مجموع حجم بکاپ‌ها').'</small></article></section>';
    echo '<section class="files-panel password-panel" data-panel-section="settings"><div class="panel-heading"><div><h2>'.icon_svg('shield').' '.esc($t['password']).'</h2><p>'.($isEn?'Use a strong password with at least 8 characters.':'برای امنیت بیشتر، رمز قوی با حداقل ۸ نویسه انتخاب کنید.').'</p></div></div><form method="post" class="password-form"><input type="hidden" name="csrf" value="'.esc($csrf).'"><input type="hidden" name="action" value="password"><label>'.esc($t['old']).'<input type="password" name="old_password" required autocomplete="current-password"></label><label>'.esc($t['new']).'<input type="password" name="new_password" minlength="8" required autocomplete="new-password"></label><button class="btn btn-primary" type="submit">'.esc($t['save']).'</button></form></section>';
    $tg=telegram_settings(); $tgConfigured=valid_telegram_settings($tg['bot_token'],$tg['chat_id']);
    $tgChatDisplay=$tg['chat_id'];
    $deliverySchedule=delivery_schedule_settings();
    $deliveryTimesInput=implode(', ',array_map(static fn($time)=>substr((string)$time,0,5),$deliverySchedule['backup_times']));
    $deliveryTimesLabel=$deliveryTimesInput!==''?$deliveryTimesInput:($isEn?'Not configured (legacy install)':'ثبت نشده (نصب قدیمی)');
    echo '<section class="files-panel update-panel" data-panel-section="settings"><div class="panel-heading"><div><h2>'.icon_svg('refresh').' '.esc($isEn?'Panel updates':'به‌روزرسانی پنل').'</h2><p>'.esc($isEn?'Check and install the latest compatible panel files without opening a terminal.':'نسخهٔ جدید پنل را بدون ورود به ترمینال بررسی و نصب کنید.').'</p></div></div><form method="post" class="timezone-form update-form"><input type="hidden" name="csrf" value="'.esc($csrf).'"/><input type="hidden" name="action" value="update_start"/><button class="btn btn-primary" type="submit">'.esc($isEn?'Start panel update':'بررسی و نصب به‌روزرسانی').'</button><small id="updateStatus" aria-live="polite">'.esc($isEn?'The updater validates files and checks the PHP service after installation.':'آپدیتر فایل‌ها را بررسی می‌کند و پس از نصب، سلامت سرویس PHP را کنترل می‌کند.').'</small></form></section>';
    echo '<section class="files-panel timezone-panel" data-panel-section="settings"><div class="panel-heading"><div><h2>'.icon_svg('clock').' '.esc($isEn?'Server clock and time zone':'ساعت سرور و منطقهٔ زمانی').'</h2><p>'.esc($isEn?'Detected Linux system time zone: ':'منطقهٔ زمانی فعلی سیستم لینوکس: ').esc($systemTimezone).'</p></div></div><div class="timezone-warning"><strong>'.esc($isEn?'Important time-zone warning':'هشدار مهم منطقهٔ زمانی').'</strong><p>'.esc($isEn?'Saving this setting changes the Linux system time zone and the Linux Cron schedule zone, but does not set the actual system clock. RouterOS has its own time zone: if you change this after installation, update the router time-zone-name to the same supported IANA zone. Keep NTP enabled for accurate time.':'ذخیره این تنظیم، منطقهٔ زمانی سیستم لینوکس و زمان‌بندی Cron را تغییر می‌دهد، اما ساعت واقعی سیستم را دستی تنظیم نمی‌کند. روتر میکروتیک منطقهٔ زمانی جداگانه دارد؛ اگر پس از نصب این گزینه را تغییر می‌دهید، time-zone-name روتر را نیز روی همان نام پشتیبانی‌شده تنظیم کنید. برای دقت ساعت، همگام‌سازی NTP فعال بماند.').'</p></div><form method="post" class="timezone-form"><input type="hidden" name="csrf" value="'.esc($csrf).'"><input type="hidden" name="action" value="timezone"><label>'.esc($isEn?'Linux server and backup schedule time zone':'منطقهٔ زمانی سرور لینوکس و زمان‌بندی بکاپ').'<select name="timezone"><option value="Asia/Tehran"'.($selectedTimezone==='Asia/Tehran'?' selected':'').'>Iran — Asia/Tehran</option><option value="Asia/Kolkata"'.($selectedTimezone==='Asia/Kolkata'?' selected':'').'>India — Asia/Kolkata</option><option value="Europe/Berlin"'.($selectedTimezone==='Europe/Berlin'?' selected':'').'>Germany — Europe/Berlin</option><option value="America/New_York"'.($selectedTimezone==='America/New_York'?' selected':'').'>USA — America/New_York</option><option value="Manual"'.(!in_array($selectedTimezone,["Asia/Tehran","Asia/Kolkata","Europe/Berlin","America/New_York"],true)?" selected":"").'>Manual</option></select><input type="text" name="timezone_manual" value="'.esc(!in_array($selectedTimezone,["Asia/Tehran","Asia/Kolkata","Europe/Berlin","America/New_York"],true)?$selectedTimezone:"").'" placeholder="Asia/Dubai" autocomplete="off"><small>'.esc($isEn?'For Manual, enter an IANA name such as Asia/Dubai or America/Los_Angeles.':'برای Manual نام استاندارد وارد کنید؛ مثل Asia/Dubai یا America/Los_Angeles.').'</small></label><button class="btn btn-primary" type="submit">'.esc($isEn?'Apply Linux time zone':'اعمال منطقهٔ زمانی لینوکس').'</button><small>'.esc($isEn?'Selected zone (applied to Linux + Cron): ':'منطقهٔ انتخاب‌شده (لینوکس + Cron): ').esc($selectedTimezone).'</small></form></section>';
    echo '<section class="files-panel telegram-panel" data-panel-section="telegram"><div class="panel-heading"><div><h2>'.icon_svg('send').' '.esc($isEn?'Telegram delivery settings':'تنظیمات اتصال تلگرام').'</h2><p>'.esc($isEn?'Configure or replace your bot credentials here; the generator no longer asks for them.':'توکن ربات و چت مقصد را اینجا وارد یا هر زمان لازم شد تغییر دهید؛ جنراتور دیگر این اطلاعات را نمی‌پرسد.').'</p></div><span class="status-pill '.($tgConfigured?'status-sent':'status-pending').'"><i></i>'.esc($tgConfigured?($isEn?'Configured':'تنظیم‌شده'):($isEn?'Setup required':'نیازمند تنظیم')).'</span></div><div class="telegram-guides"><article class="guide-card"><span class="guide-step">01</span><h3>'.esc($isEn?'Get a Bot Token':'دریافت Bot Token').'</h3><p>'.($isEn?'Open Telegram and message @BotFather. Run /newbot (or select your existing bot), then copy its API token. Keep it secret, and open your bot and press Start before testing delivery.':'در تلگرام به @BotFather پیام بدهید؛ دستور /newbot را اجرا کنید یا ربات قبلی را انتخاب کنید و API Token را کپی کنید. توکن را محرمانه نگه دارید؛ سپس وارد ربات خودتان شوید و Start را بزنید.').'</p><a class="guide-link" href="https://t.me/BotFather" target="_blank" rel="noopener noreferrer">@BotFather ↗</a></article><article class="guide-card"><span class="guide-step">02</span><h3>'.esc($isEn?'Find your Chat ID':'پیدا کردن Chat ID').'</h3><p>'.($isEn?'Open @userinfobot and press Start. Copy the numeric ID it shows. For a group, add your bot to the group and use that group’s ID instead.':'به @userinfobot پیام بدهید و Start را بزنید؛ عددی که نمایش می‌دهد Chat ID شماست. برای گروه، ربات را به گروه اضافه کنید و شناسه همان گروه را وارد کنید.').'</p><a class="guide-link" href="https://t.me/userinfobot" target="_blank" rel="noopener noreferrer">@userinfobot ↗</a></article></div><form method="post" class="telegram-form"><input type="hidden" name="csrf" value="'.esc($csrf).'"><input type="hidden" name="action" value="telegram_settings"><label>'.esc($isEn?'Bot Token':'توکن ربات (Bot Token)').'<input type="password" name="bot_token" autocomplete="new-password" placeholder="'.esc($tgConfigured?($isEn?'Leave blank to keep current token':'برای حفظ توکن فعلی خالی بگذارید'):($isEn?'Paste token from @BotFather':'توکن دریافتی از BotFather را وارد کنید')).'"><small>'.esc($isEn?'Tokens are stored on the server and never displayed back.':'توکن در سرور ذخیره می‌شود و دوباره به‌صورت متن نمایش داده نمی‌شود.').'</small></label><label>'.esc($isEn?'Destination Chat ID':'شناسه مقصد (Chat ID)').'<input type="text" name="chat_id" required inputmode="numeric" pattern="-?[0-9]{1,20}" value="'.esc($tgChatDisplay).'" placeholder="'.esc($isEn?'e.g. 123456789 or -100…':'مثلاً 123456789 یا -100…').'"><small>'.esc($isEn?'Numeric IDs only; group IDs are often negative.':'شناسه عددی؛ شناسه گروه‌ها معمولاً منفی است.').'</small></label><div class="telegram-actions"><button class="btn btn-primary" type="submit">'.esc($isEn?'Save Telegram settings':'ذخیره تنظیمات تلگرام').'</button></div></form><form method="post" class="telegram-form"><input type="hidden" name="csrf" value="'.esc($csrf).'"><input type="hidden" name="action" value="delivery_schedule"><label>'.esc($isEn?'Router backup time(s) (HH:MM, up to two)':'ساعت بکاپ روتر (HH:MM، حداکثر دو ساعت)').'<input type="text" name="backup_times" required value="'.esc($deliveryTimesInput).'" placeholder="00:00, 12:00"><small>'.esc(($isEn?'Current schedule: ':'زمان‌بندی فعلی: ').$deliveryTimesLabel).'</small></label><label>'.esc($isEn?'Telegram delay after backup (minutes)':'فاصله ارسال تلگرام پس از بکاپ (دقیقه)').'<input type="number" name="delay_minutes" min="0" max="30" required value="'.esc((string)$deliverySchedule['delay_minutes']).'"><small>'.esc($isEn?'The scanner retries once per minute for six minutes after this delay.':'اسکنر پس از این فاصله، شش دقیقه هر دقیقه تلاش می‌کند تا آپلود کامل شود.').'</small></label><div class="telegram-actions"><button class="btn btn-primary" type="submit">'.esc($isEn?'Save delivery schedule':'ذخیره زمان‌بندی ارسال').'</button></div><small style="grid-column:1/-1">'.esc($isEn?'This controls Linux-side Cron only; it does not change the RouterOS scheduler. Keep these times aligned with the router and the server local time zone.':'این تنظیم فقط Cron سرور را تغییر می‌دهد و Scheduler روتر را تغییر نمی‌دهد. ساعت‌ها باید با برنامه روتر و منطقه زمانی سرور هماهنگ باشند.').'</small></form><form method="post" class="telegram-test-form"><input type="hidden" name="csrf" value="'.esc($csrf).'"><input type="hidden" name="action" value="telegram_test"><button class="btn btn-ghost" type="submit" '.(!$tgConfigured?'disabled':'').'>'.icon_svg('send').' '.esc($isEn?'Test Telegram connection':'تست اتصال تلگرام').'</button><small>'.esc($isEn?'Finds and sends the newest backup file from the configured server folder.':'آخرین فایل بکاپ موجود در پوشه تنظیم‌شده سرور را پیدا و به تلگرام ارسال می‌کند.').'</small></form></section>';
    echo '<section class="files-panel" data-panel-section="backups"><div class="panel-heading"><div><h2>'.icon_svg('files').' '.esc($isEn?'Your backups':'فایل‌های بکاپ شما').'</h2><p>'.($isEn?'Review recent backups and Telegram delivery status.':'وضعیت فایل‌ها و ارسال تلگرام را بررسی کنید.').'</p></div><div class="panel-tools"><label class="search-box">'.icon_svg('search').'<input id="backupSearch" type="search" value="'.esc($searchQuery).'" placeholder="'.esc($t['search']).'" autocomplete="off"></label><button class="btn btn-primary" type="button" id="refreshPanel">'.icon_svg('refresh').' <span>'.esc($t['refresh']).'</span></button></div></div><div class="table-wrap"><table id="backupTable"><thead><tr><th>'.esc($t['name']).'</th><th>'.esc($t['size']).'</th><th>'.esc($t['date']).'</th><th>'.esc($t['status']).'</th><th>'.esc($t['actions']).'</th></tr></thead><tbody>';
    foreach ($filesOnPage as $f) { $n=basename($f); $st=$state[$n]??[]; $status=(string)($st['status']??'pending'); $statusClass=$status==='sent'?'status-sent':($status==='failed'?'status-failed':'status-pending'); $statusText=$status==='sent'?$t['sent_status']:($status==='failed'?$t['failed_status']:$t['pending']); echo '<tr data-search="'.esc(strtolower($n)).'"><td><div class="file-name"><span class="file-icon">'.icon_svg('file').'</span><span><strong>'.esc($n).'</strong><small>'.esc($isEn?'MikroTik backup file':'فایل پشتیبان میکروتیک').'</small></span></div></td><td class="nowrap">'.esc(format_bytes((int)filesize($f))).'</td><td class="nowrap">'.esc(date('Y-m-d H:i',filemtime($f))).'</td><td><span class="status-pill '.$statusClass.'"><i></i>'.esc($statusText).'</span></td><td><div class="row-actions"><form method="post" class="inline-action" onsubmit="return confirm(&quot;'.esc($t['confirm']).'&quot;)"><input type="hidden" name="csrf" value="'.esc($csrf).'"/><input type="hidden" name="action" value="delete"/><input type="hidden" name="file" value="'.esc($n).'"/><button class="icon-btn danger" type="submit" title="'.esc($t['delete']).'" aria-label="'.esc($t['delete']).'">'.icon_svg('trash').'</button></form></div></td></tr>'; }
    if (!$files) echo '<tr><td colspan="5"><div class="empty-state">'.icon_svg('folder-empty').'<strong>'.esc($t['empty']).'</strong></div></td></tr>';
    echo '</tbody></table></div><div class="panel-footer"><span>'.($isEn?'Showing':'نمایش'). ' <strong>'.($totalFiles===0?0:(($currentPage-1)*$perPage+1)).'–'.min($currentPage*$perPage,$totalFiles).'</strong> '.($isEn?'of':'از').' <strong>'.$totalFiles.'</strong> '.($isEn?'backup files':'فایل بکاپ').'</span><nav class="pagination" aria-label="Pagination">'.($currentPage>1?'<a class="page-link" href="?page='.($currentPage-1).($searchQuery!==''?'&amp;q='.rawurlencode($searchQuery):'').'">'.esc($isEn?'Previous':'قبلی').'</a>':'').'<span>'.esc((string)$currentPage).' / '.esc((string)$totalPages).'</span>'.($currentPage<$totalPages?'<a class="page-link" href="?page='.($currentPage+1).($searchQuery!==''?'&amp;q='.rawurlencode($searchQuery):'').'">'.esc($isEn?'Next':'بعدی').'</a>':'').'</nav><span class="footer-secure">'.icon_svg('shield').' '.($isEn?'Private server storage':'ذخیره‌سازی خصوصی روی سرور').'</span></div></section><footer class="app-footer"><span>© '.date('Y').' ATD · MikroTik Backup Studio</span><span>'.($isEn?'Code by <a href="https://wa.me/pardis.mobile.kish" target="_blank" rel="noopener noreferrer">Amir Taheri</a>':'کدنویسی توسط <a href="https://wa.me/pardis.mobile.kish" target="_blank" rel="noopener noreferrer">Amir Taheri</a>').'</span></footer></main></div><script src="panel.js" defer></script></body></html>';
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

// Automatic server-side scan. RouterOS and the SFTP workflow do not call this endpoint.
if (PHP_SAPI === 'cli' && in_array('--scan-backups', $argv ?? [], true)) {
    $lockHandle = @fopen(dirname(STATE_FILE) . '/telegram-scan.lock', 'c');
    if ($lockHandle === false || !flock($lockHandle, LOCK_EX | LOCK_NB)) exit(0);
    $baselinePath = dirname(STATE_FILE) . '/telegram-scan-started-at';
    $baseline = is_file($baselinePath) ? (int)trim((string)@file_get_contents($baselinePath)) : 0;
    if ($baseline <= 0) {
        @file_put_contents($baselinePath, (string)time(), LOCK_EX);
        @chmod($baselinePath, 0600);
        fwrite(STDOUT, "ATD Telegram scan baseline initialized; existing files are left untouched.\n");
        exit(0);
    }
    $base = realpath(BACKUP_DIR);
    if ($base === false || !is_readable($base)) {
        fwrite(STDERR, "ATD Telegram scan: backup directory is unavailable.\n");
        exit(2);
    }
    foreach (glob($base . DIRECTORY_SEPARATOR . '*.backup') ?: [] as $path) {
        if (!is_file($path) || !is_readable($path)) continue;
        $mtime = @filemtime($path);
        if ($mtime === false || $mtime < $baseline) continue;
        $name = basename($path);
        if (!preg_match('/\\A[A-Za-z0-9_. -]+\\.backup\\z/', $name)) continue;
        [$ok, $message] = send_telegram_file($name, false);
        if (!$ok && $message !== 'ALREADY_SENT') fwrite(STDERR, "ATD Telegram scan: {$name}: {$message}\n");
    }
    exit(0);
}

if ($_SERVER['REQUEST_METHOD'] === 'GET' || (!empty($_SESSION['admin']) && $_SERVER['REQUEST_METHOD'] === 'POST') || (!empty($_POST['login']) && $_SERVER['REQUEST_METHOD'] === 'POST')) {
    render_panel();
    exit;
}
if ($_SERVER['REQUEST_METHOD'] !== 'POST') { http_response_code(405); exit('METHOD_NOT_ALLOWED'); }
http_response_code(405);
exit('METHOD_NOT_ALLOWED');
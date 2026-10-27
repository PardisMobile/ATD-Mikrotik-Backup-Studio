(function(){
  const root=document.documentElement;
  const accents=['#1769e0','#0d9488','#7c3aed','#db2777','#ea580c'];
  const safeGet=(key)=>{try{return localStorage.getItem(key)}catch(e){return null}};
  const savedTheme=safeGet('atd-theme');
  if(savedTheme==='dark')root.dataset.theme='dark';
  function setAccent(color){
    if(!accents.includes(color))return;
    root.style.setProperty('--blue',color);root.style.setProperty('--accent',color);root.style.setProperty('--blue-soft',color+'20');
    document.querySelectorAll('[data-accent]').forEach(b=>b.setAttribute('aria-pressed',b.dataset.accent===color?'true':'false'));
    try{localStorage.setItem('atd-accent',color)}catch(e){}
  }
  function syncAccentSwatches(){
    const color=safeGet('atd-accent');
    document.querySelectorAll('[data-accent]').forEach(b=>b.setAttribute('aria-pressed',b.dataset.accent===color?'true':'false'));
  }
  const savedAccent=safeGet('atd-accent');if(savedAccent)setAccent(savedAccent);else syncAccentSwatches();
  function initTimezoneSelector(){
    const zoneSelect=document.querySelector('select[name="timezone"]');
    if(!zoneSelect)return;
    const form=zoneSelect.closest('form'),manual=form&&form.querySelector('[name="timezone_manual"]');
    if(manual){manual.hidden=zoneSelect.value!=='Manual';manual.required=zoneSelect.value==='Manual';}
  }
  let messageTimer=null;
  function dismissMessage(box){
    if(!box||!box.isConnected)return;
    box.hidden=true;
    box.textContent='';
    box.classList.remove('alert-error','alert-success');
  }
  function showMessage(message,ok){
    let box=document.querySelector('.ajax-message');
    if(!box){box=document.createElement('div');box.className='alert ajax-message';const main=document.querySelector('.main-content');if(main)main.prepend(box);}
    if(messageTimer!==null)clearTimeout(messageTimer);
    box.textContent=message;box.classList.toggle('alert-success',!!ok);box.classList.toggle('alert-error',!ok);
    box.hidden=false;
    messageTimer=setTimeout(()=>dismissMessage(box),7000);
  }
  function clearStaleAlerts(){
    document.querySelectorAll('.main-content .alert:not(.ajax-message)').forEach(box=>{
      if(box.dataset.autoDismissBound==='1')return;
      box.dataset.autoDismissBound='1';
      setTimeout(()=>dismissMessage(box),7000);
    });
  }
  async function loadPage(url){
    const response=await fetch(url,{credentials:'same-origin',headers:{'X-Requested-With':'XMLHttpRequest'}});
    if(!response.ok)throw new Error('Request failed ('+response.status+')');
    const html=await response.text();
    const parsed=new DOMParser().parseFromString(html,'text/html');
    const fresh=parsed.querySelector('.app-shell'),current=document.querySelector('.app-shell');
    if(!fresh||!current)throw new Error('Unexpected response from panel.');
    current.replaceWith(fresh);
    document.title=parsed.title||document.title;
    document.documentElement.lang=parsed.documentElement.lang;
    document.documentElement.dir=parsed.documentElement.dir;
    history.replaceState({},'',response.url||url);
    applyPanelSection();
    startClocks();
    initTimezoneSelector();
    syncAccentSwatches();
  }
  async function submitAjax(form){
    const isUpdateForm=form.classList.contains('update-form');
    const submitters=form.querySelectorAll('button[type="submit"],button:not([type])');
    submitters.forEach(b=>{b.dataset.oldText=b.innerHTML;b.disabled=true;b.classList.add('is-loading')});
    try{
      const response=await fetch(form.action||location.href,{method:'POST',body:new FormData(form),credentials:'same-origin',redirect:'follow',headers:{'X-Requested-With':'XMLHttpRequest'}});
      if(!response.ok)throw new Error('Request failed ('+response.status+')');
      if(form.querySelector('[name="action"]')?.value==='telegram_test'){
        const data=await response.json();
        showMessage(data.message||'Telegram test finished.',!!data.ok);
        return;
      }
      const html=await response.text(),parsed=new DOMParser().parseFromString(html,'text/html');
      const updateStarted=isUpdateForm&&(parsed.querySelector('.alert')?.textContent||'').includes('UPDATE_STARTED');
      const fresh=parsed.querySelector('.app-shell'),current=document.querySelector('.app-shell');
      if(!fresh||!current)throw new Error('Unexpected response from panel.');
      current.replaceWith(fresh);
      document.title=parsed.title||document.title;
      document.documentElement.lang=parsed.documentElement.lang;document.documentElement.dir=parsed.documentElement.dir;
      if(response.url)history.replaceState({},'',response.url);
      applyPanelSection();
      startClocks();
      initTimezoneSelector();
      syncAccentSwatches();
      clearStaleAlerts();
      if(updateStarted)pollUpdateStatus();
    }catch(error){showMessage('Operation failed: '+error.message,false)}
    finally{submitters.forEach(b=>{b.disabled=false;b.classList.remove('is-loading')})}
  }
  let clockTimer=null;
  function applyPanelSection(){
    const allowed=['dashboard','backups','telegram','settings'];
    let active=safeGet('atd-panel-section');if(!allowed.includes(active))active='dashboard';
    document.querySelectorAll('[data-panel-section]').forEach(section=>{section.hidden=section.dataset.panelSection!==active;});
    document.querySelectorAll('[data-panel-tab]').forEach(tab=>{const selected=tab.dataset.panelTab===active;tab.setAttribute('aria-current',selected?'page':'false');tab.classList.toggle('is-active',selected);});
  }
  function setPanelSection(name){
    if(!['dashboard','backups','telegram','settings'].includes(name))return;
    try{localStorage.setItem('atd-panel-section',name)}catch(e){}
    applyPanelSection();
  }
  async function pollUpdateStatus(){
    const target=document.getElementById('updateStatus');if(!target)return;
    target.textContent='Update requested. Waiting for the updater…';
    for(let i=0;i<180;i++){
      try{
        const r=await fetch(location.pathname+'?ajax=update_status',{credentials:'same-origin',headers:{'X-Requested-With':'XMLHttpRequest'}});
        if(r.ok){
          const data=await r.json();
          if(data.status==='running'){target.textContent='Update is running. Keep this page open…';}
          else if(data.status==='success'){target.textContent='Update completed successfully.';return;}
          else if(data.status==='failed'){target.textContent='Update failed (exit code '+String(data.exit_code??'unknown')+'). Check the server updater log.';return;}
          else if(data.status==='unavailable'){target.textContent=data.message||'Updater status is unavailable.';return;}
        }
      }catch(e){}
      await new Promise(resolve=>setTimeout(resolve,2000));
    }
    target.textContent='Update status is taking longer than expected. Check again in a moment.';
  }
  function renderClock(el){
    const epoch=parseInt(el.dataset.epoch||'0',10);if(!epoch)return;
    const zone=el.dataset.timezone||'UTC';const date=new Date(epoch*1000);
    try{
      const parts=new Intl.DateTimeFormat('en-GB',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'}).formatToParts(date);
      const v={};parts.forEach(p=>{v[p.type]=p.value});
      el.textContent=v.year+'-'+v.month+'-'+v.day+' '+v.hour+':'+v.minute+':'+v.second;
    }catch(e){el.textContent='Time unavailable'}
    el.dataset.epoch=String(epoch+1);
  }
  function startClocks(){
    document.querySelectorAll('[data-server-clock]').forEach(renderClock);
    if(clockTimer!==null)clearInterval(clockTimer);
    clockTimer=setInterval(()=>document.querySelectorAll('[data-server-clock]').forEach(renderClock),1000);
  }
  applyPanelSection();
  startClocks();
  clearStaleAlerts();
  document.addEventListener('click',async function(event){
    const tab=event.target.closest('[data-panel-tab]');if(tab){setPanelSection(tab.dataset.panelTab);return}
    const theme=event.target.closest('#themeToggle');
    if(theme){const dark=root.dataset.theme!=='dark';if(dark)root.dataset.theme='dark';else delete root.dataset.theme;try{localStorage.setItem('atd-theme',dark?'dark':'light')}catch(e){}return}
    const accent=event.target.closest('[data-accent]');if(accent){setAccent(accent.dataset.accent);return}
    const lang=event.target.closest('#languageToggle');if(lang){const next=(document.documentElement.lang==='fa')?'en':'fa';document.cookie='atd_lang='+next+'; path=/; max-age=31536000; SameSite=Lax';try{await loadPage(location.href)}catch(e){location.reload()}return}
    const checkUpdates=event.target.closest('#checkUpdates');
    if(checkUpdates){
      const status=document.getElementById('checkUpdateStatus');checkUpdates.disabled=true;
      const fa=document.documentElement.lang==='fa';
      if(status)status.textContent=fa?'در حال بررسی GitHub…':'Checking GitHub…';
      try{
        const response=await fetch(location.pathname+'?ajax=check_update',{credentials:'same-origin',headers:{'X-Requested-With':'XMLHttpRequest'}});
        if(!response.ok)throw new Error('HTTP '+response.status);
        const data=await response.json();
        if(!status)return;
        if(data.status==='current')status.textContent=fa?'پنل به‌روز است. نسخه: '+data.installed:'Panel is up to date. Version: '+data.installed;
        else if(data.status==='available')status.textContent=(fa?'نسخهٔ جدید موجود است: ':'Update available: ')+data.latest.slice(0,12);
        else if(data.status==='unknown')status.textContent=fa?'نسخهٔ نصب‌شده ثبت نشده؛ یک بار آپدیت اجرا کنید.':'Installed version is unknown; run the updater once.';
        else status.textContent=data.message||(fa?'بررسی آپدیت ناموفق بود.':'Update check failed.');
      }catch(error){if(status)status.textContent=(fa?'خطا در بررسی آپدیت: ':'Update check failed: ')+error.message;}
      finally{checkUpdates.disabled=false;}
      return;
    }
    const refresh=event.target.closest('#refreshPanel');if(refresh){refresh.disabled=true;try{await loadPage(location.href)}catch(e){showMessage('Refresh failed: '+e.message,false)}finally{refresh.disabled=false}return}
    const pageLink=event.target.closest('.pagination a');if(pageLink){event.preventDefault();try{await loadPage(pageLink.href)}catch(e){showMessage('Could not change page: '+e.message,false)}}
  });
  document.addEventListener('submit',function(event){
    const form=event.target;
    if(!(form instanceof HTMLFormElement)||!document.querySelector('.app-shell'))return;
    if(form.querySelector('[name="logout"]')||form.classList.contains('login-form'))return;
    if(!form.querySelector('[name="csrf"]'))return;
    const action=form.querySelector('[name="action"]')?.value;
    if(action==='timezone'||action==='update_start')return;
    event.preventDefault();submitAjax(form);
  });
  let searchTimer=null;
  document.addEventListener('input',function(event){
    const search=event.target.closest('#backupSearch');if(!search)return;
    const value=search.value;
    if(searchTimer!==null)clearTimeout(searchTimer);
    searchTimer=setTimeout(async function(){
      const url=new URL(location.href);url.searchParams.set('page','1');
      if(value.trim())url.searchParams.set('q',value.trim());else url.searchParams.delete('q');
      const caret=value.length;
      try{await loadPage(url.toString());const next=document.getElementById('backupSearch');if(next){next.focus();next.setSelectionRange(caret,caret)}}catch(e){showMessage('Search failed: '+e.message,false)}
    },300);
  });
  document.addEventListener('change',function(event){
    const select=event.target.closest('select[name="timezone"]');if(!select)return;
    const form=select.closest('form'),manual=form&&form.querySelector('[name="timezone_manual"]');
    if(manual){manual.hidden=select.value!=='Manual';manual.required=select.value==='Manual';}
  });
  initTimezoneSelector();
})();
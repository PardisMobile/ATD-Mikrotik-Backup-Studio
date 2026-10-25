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
/* esx_families v0.8.0-p3d2 — Modern NUI core (router + safety net + auto-recovery) */
(function(){
  const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'esx_families';
  const root = document.getElementById('qfm-root');
  if(!root){ console.warn('[qfm] root missing'); return; }

  function post(cb, data){
    return fetch(`https://${RES}/${cb}`, {
      method:'POST',
      headers:{'Content-Type':'application/json;charset=UTF-8'},
      body: JSON.stringify(data||{})
    }).catch(()=>{});
  }

  // إغلاق طارئ يُنهي focus + يلغي أي dialog معلّق على Lua
  function emergencyClose(token, reason){
    root.classList.remove('qfm-open');
    root.innerHTML = '';
    post('qfm:close', { reason: reason||'emergency' });
    if(token){
      post('qfm:dlg', { token: token, ok:false, error:'screen_missing' });
    }
  }

  const Q = {
    open(html){
      root.innerHTML = `<div class="qfm-scrim"></div><div class="qfm-window">${html}</div>`;
      root.classList.add('qfm-open');
      const sc = root.querySelector('.qfm-scrim');
      if(sc) sc.addEventListener('click', ()=> Q.close('scrim'));
    },
    close(reason){
      root.classList.remove('qfm-open');
      root.innerHTML = '';
      post('qfm:close', { reason: reason||'manual' });
    },
    bindItems(){
      root.querySelectorAll('.qfm-item[data-action]').forEach(el=>{
        el.addEventListener('click', ()=>{
          const act = el.getAttribute('data-action');
          const id  = el.getAttribute('data-id') || '';
          Q.close('select');
          post('qfm:select', { action: act, id: id });
        });
      });
    }
  };

  // ESC / Backspace closes (+ يلغي أي pending dialog)
  document.addEventListener('keydown', (e)=>{
    if(!root.classList.contains('qfm-open')) return;
    if(e.key === 'Escape' || e.key === 'Backspace'){
      e.preventDefault();
      const tok = root.getAttribute('data-pending-token');
      root.removeAttribute('data-pending-token');
      if(tok){ post('qfm:dlg', { token: tok, ok:false, cancel:true }); }
      Q.close('key');
    }
  });

  // NUI message handler — مع safety net كامل
  window.addEventListener('message', (ev)=>{
    const d = ev.data || {};
    if(d.qfm !== true) return;
    console.log('[DIAG_P3D3_MSG] cmd=', d.cmd, 'screen=', d.screen, 'has_screens=', !!(window.QFM_SCREENS && window.QFM_SCREENS[d.screen]), 'payload_items=', (d.payload && d.payload.items && d.payload.items.length));

    if(d.cmd === 'close'){ Q.close('lua'); return; }
    if(d.cmd !== 'open' || !d.screen) return;

    const tok = (d.payload && d.payload.token) || null;

    // الحالة الطبيعية
    if(window.QFM_SCREENS && typeof window.QFM_SCREENS[d.screen] === 'function'){
      try{
        if(tok) root.setAttribute('data-pending-token', tok);
        window.QFM_SCREENS[d.screen](Q, d.payload || {});
        return;
      }catch(err){
        console.error('[qfm] screen error:', d.screen, err);
        emergencyClose(tok, 'screen_error');
        return;
      }
    }

    // ⚠️ screen مفقود — هذا اللي كان يسبّب "ماوس بدون قائمة"
    console.error('[qfm] missing screen:', d.screen, '— sending failsafe close');
    emergencyClose(tok, 'screen_missing');
  });

  // Watchdog: لو الـDOM فاضي وقد مرّت ثواني على فتح focus، نفك القفل
  // (طبقة حماية إضافية — تُستخدم فقط عبر أمر يدوي qfm_unstick من Lua)
  window.QFM_FORCE_UNSTICK = function(){
    root.classList.remove('qfm-open');
    root.innerHTML = '';
    post('qfm:close', { reason:'force_unstick' });
  };

  window.QFM = Q;
  window.QFM_SCREENS = window.QFM_SCREENS || {};
  console.log('[qfm] core.js v0.8.0-p3d2 loaded');
})();

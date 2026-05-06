/* esx_families v0.8.0 — Modern NUI core (router + NUI bridge) */
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

  const Q = {
    open(html){
      root.innerHTML = `<div class="qfm-scrim"></div><div class="qfm-window">${html}</div>`;
      root.classList.add('qfm-open');
      // close on scrim click
      root.querySelector('.qfm-scrim').addEventListener('click', ()=> Q.close('scrim'));
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
          // Close UI first, then trigger Lua handler (Phase 1: opens ox_lib sub-menu)
          Q.close('select');
          post('qfm:select', { action: act, id: id });
        });
      });
    }
  };

  // ESC / Backspace closes
  document.addEventListener('keydown', (e)=>{
    if(!root.classList.contains('qfm-open')) return;
    if(e.key === 'Escape' || e.key === 'Backspace'){
      e.preventDefault();
      Q.close('key');
    }
  });

  // NUI message handler
  window.addEventListener('message', (ev)=>{
    const d = ev.data || {};
    if(d.qfm !== true) return;
    if(d.cmd === 'open' && d.screen && window.QFM_SCREENS && window.QFM_SCREENS[d.screen]){
      window.QFM_SCREENS[d.screen](Q, d.payload || {});
    } else if(d.cmd === 'close'){
      Q.close('lua');
    }
  });

  window.QFM = Q;
  window.QFM_SCREENS = window.QFM_SCREENS || {};
})();

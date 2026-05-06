/* esx_families v0.8.0 — F6 Interactive Dialogs (list / input / confirm)
   Corporate Blue style, RTL, FA icons. */
(function(){
  function esc(s){ return String(s==null?'':s).replace(/[&<>"']/g, c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }

  function header(title, subtitle){
    return `<div class="qfm-header">
      <div class="qfm-title"><i class="fas fa-list-check" style="margin-left:8px;color:var(--qfm-gold-1)"></i>${esc(title||'')}</div>
      ${subtitle?`<div class="qfm-sub">${esc(subtitle)}</div>`:''}
    </div>`;
  }
  function footer(extra){
    return `<div class="qfm-footer">${extra||''}<kbd>ESC</kbd> للإغلاق</div>`;
  }

  // ---------- LIST ----------
  // payload: { token, title, subtitle, items:[{id,title,desc,fa,iconColor,readOnly,danger}], backToken }
  window.QFM_SCREENS.dlg_list = function(Q, p){
    console.log('[DIAG_P3D3_RENDER] dlg_list called: title=', p.title, 'items=', (p.items||[]).length, 'token=', p.token);
    const items = (p.items||[]).map((o, i)=>{
      const fa   = o.fa || (o.readOnly ? 'fa-circle-info' : 'fa-chevron-left');
      const cls  = o.iconColor ? ` qfm-icon-${o.iconColor}` : '';
      const ro   = o.readOnly ? ' qfm-readonly' : '';
      const dn   = o.danger ? ' qfm-danger' : '';
      const data = o.readOnly ? '' : ` data-dlg-idx="${i}"`;
      return `<div class="qfm-item${ro}${dn}"${data}>
        <div class="qfm-icon${cls}"><i class="fas ${esc(fa)}"></i></div>
        <div class="qfm-body">
          <div class="qfm-item-title">${esc(o.title||'')}</div>
          ${o.desc ? `<div class="qfm-item-desc">${esc(o.desc)}</div>` : ''}
        </div>
        ${o.readOnly?'':'<div class="qfm-chev"><i class="fas fa-chevron-left"></i></div>'}
      </div>`;
    }).join('');

    const backBtn = p.backToken ? `<button class="qfm-back-btn" id="qfm-back"><i class="fas fa-arrow-right"></i> رجوع</button>` : '';
    Q.open(`${header(p.title, p.subtitle)}
      <div class="qfm-list qfm-list-1col">${items || '<div class="qfm-empty">لا توجد عناصر</div>'}</div>
      ${footer(backBtn)}`);

    // Bind item clicks → dlg:result (selected idx)
    document.querySelectorAll('.qfm-item[data-dlg-idx]').forEach(el=>{
      el.addEventListener('click', ()=>{
        const idx = parseInt(el.getAttribute('data-dlg-idx'),10);
        Q.close('select');
        fetch(`https://${(typeof GetParentResourceName==='function')?GetParentResourceName():'esx_families'}/qfm:dlg`, {
          method:'POST', headers:{'Content-Type':'application/json;charset=UTF-8'},
          body: JSON.stringify({ token: p.token, ok:true, value: idx })
        }).catch(()=>{});
      });
    });
    const back = document.getElementById('qfm-back');
    if(back && p.backToken){
      back.addEventListener('click', ()=>{
        Q.close('back');
        fetch(`https://${(typeof GetParentResourceName==='function')?GetParentResourceName():'esx_families'}/qfm:dlg`, {
          method:'POST', headers:{'Content-Type':'application/json;charset=UTF-8'},
          body: JSON.stringify({ token: p.token, ok:false, back:true })
        }).catch(()=>{});
      });
    }
  };

  // ---------- INPUT ----------
  // payload: { token, title, subtitle, fields:[{type:'input'|'number'|'select', label, placeholder, required, min, max, default, options:[{value,label}]}] }
  window.QFM_SCREENS.dlg_input = function(Q, p){
    const fields = (p.fields||[]).map((f,i)=>{
      const lbl = `<label class="qfm-field-label">${esc(f.label||('Field '+(i+1)))}${f.required?' <span style="color:#f87171">*</span>':''}</label>`;
      if(f.type === 'select'){
        const opts = (f.options||[]).map(o=>`<option value="${esc(o.value)}">${esc(o.label)}</option>`).join('');
        return `<div class="qfm-field">${lbl}<select class="qfm-input" data-fi="${i}">${opts}</select></div>`;
      }
      const itype = f.type==='number' ? 'number' : 'text';
      const ph = f.placeholder ? ` placeholder="${esc(f.placeholder)}"` : '';
      const def = f.default!=null ? ` value="${esc(f.default)}"` : '';
      const minmax = (f.min!=null?` min="${f.min}"`:'')+(f.max!=null?` max="${f.max}"`:'');
      return `<div class="qfm-field">${lbl}<input class="qfm-input" type="${itype}" data-fi="${i}"${ph}${def}${minmax}></div>`;
    }).join('');

    Q.open(`${header(p.title, p.subtitle)}
      <div class="qfm-form">${fields}</div>
      <div class="qfm-actions">
        <button class="qfm-btn qfm-btn-ghost" id="qfm-cancel"><i class="fas fa-xmark"></i> إلغاء</button>
        <button class="qfm-btn qfm-btn-primary" id="qfm-submit"><i class="fas fa-check"></i> تأكيد</button>
      </div>
      ${footer('')}`);

    function send(ok, value){
      Q.close(ok?'submit':'cancel');
      fetch(`https://${(typeof GetParentResourceName==='function')?GetParentResourceName():'esx_families'}/qfm:dlg`, {
        method:'POST', headers:{'Content-Type':'application/json;charset=UTF-8'},
        body: JSON.stringify({ token: p.token, ok: ok, value: value })
      }).catch(()=>{});
    }
    document.getElementById('qfm-cancel').addEventListener('click', ()=> send(false, null));
    document.getElementById('qfm-submit').addEventListener('click', ()=>{
      const out = [];
      let valid = true;
      (p.fields||[]).forEach((f,i)=>{
        const el = document.querySelector(`[data-fi="${i}"]`);
        let v = el ? el.value : '';
        if(f.type==='number') v = (v===''?null:Number(v));
        if(f.required && (v===''||v==null)) valid = false;
        out.push(v);
      });
      if(!valid){ alert('يرجى تعبئة الحقول المطلوبة (*)'); return; }
      send(true, out);
    });
    // auto-focus first
    const first = document.querySelector('.qfm-input');
    if(first) first.focus();
  };

  // ---------- CONFIRM ----------
  // payload: { token, title, content, danger:true|false, confirmText, cancelText }
  window.QFM_SCREENS.dlg_confirm = function(Q, p){
    const dn = p.danger ? ' qfm-confirm-danger' : '';
    Q.open(`<div class="qfm-confirm${dn}">
      <div class="qfm-confirm-icon"><i class="fas ${p.danger?'fa-triangle-exclamation':'fa-circle-question'}"></i></div>
      <div class="qfm-confirm-title">${esc(p.title||'تأكيد')}</div>
      <div class="qfm-confirm-content">${esc(p.content||'')}</div>
      <div class="qfm-actions">
        <button class="qfm-btn qfm-btn-ghost" id="qfm-cancel"><i class="fas fa-xmark"></i> ${esc(p.cancelText||'إلغاء')}</button>
        <button class="qfm-btn ${p.danger?'qfm-btn-danger':'qfm-btn-primary'}" id="qfm-ok"><i class="fas fa-check"></i> ${esc(p.confirmText||'تأكيد')}</button>
      </div>
    </div>${footer('')}`);

    function send(ok){
      Q.close(ok?'confirm':'cancel');
      fetch(`https://${(typeof GetParentResourceName==='function')?GetParentResourceName():'esx_families'}/qfm:dlg`, {
        method:'POST', headers:{'Content-Type':'application/json;charset=UTF-8'},
        body: JSON.stringify({ token: p.token, ok: ok })
      }).catch(()=>{});
    }
    document.getElementById('qfm-cancel').addEventListener('click', ()=> send(false));
    document.getElementById('qfm-ok').addEventListener('click', ()=> send(true));
  };
})();

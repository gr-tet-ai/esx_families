/* esx_families v0.8.0 — F6 main screen */
(function(){
  function esc(s){ return String(s==null?'':s).replace(/[&<>"']/g, c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  function item(o){
    const ic   = o.icon || '•';
    const cls  = o.iconColor ? ` qfm-icon-${o.iconColor}` : '';
    const ro   = o.readOnly ? ' qfm-readonly' : '';
    const data = o.readOnly ? '' : ` data-action="${esc(o.action)}" data-id="${esc(o.id||'')}"`;
    return `<div class="qfm-item${ro}"${data}>
      <div class="qfm-icon${cls}">${esc(ic)}</div>
      <div class="qfm-body">
        <div class="qfm-item-title">${esc(o.title)}</div>
        ${o.desc ? `<div class="qfm-item-desc">${esc(o.desc)}</div>` : ''}
      </div>
      <div class="qfm-chev">‹</div>
    </div>`;
  }
  window.QFM_SCREENS = window.QFM_SCREENS || {};
  window.QFM_SCREENS.f6_main = function(Q, p){
    const items = (p.items||[]).map(item).join('');
    const html = `
      <div class="qfm-header">
        <div class="qfm-title">🏛️ ${(p.title||'نظام العوائل').replace(/[<>]/g,'')}</div>
        ${p.subtitle ? `<div class="qfm-sub">${(p.subtitle||'').replace(/[<>]/g,'')}</div>` : ''}
      </div>
      <div class="qfm-list">${items}</div>
      <div class="qfm-footer"><kbd>ESC</kbd> للإغلاق · <kbd>F6</kbd> لإعادة الفتح</div>`;
    Q.open(html);
    Q.bindItems();
  };
})();

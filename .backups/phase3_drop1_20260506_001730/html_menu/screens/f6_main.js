/* esx_families v0.8.0 — F6 main screen (FA icons + 2-col grid) */
(function(){
  function esc(s){ return String(s==null?'':s).replace(/[&<>"']/g, c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  function item(o){
    const fa   = o.fa || 'fa-circle';
    const cls  = o.iconColor ? ` qfm-icon-${o.iconColor}` : '';
    const ro   = o.readOnly ? ' qfm-readonly' : '';
    const data = o.readOnly ? '' : ` data-action="${esc(o.action)}" data-id="${esc(o.id||'')}"`;
    return `<div class="qfm-item${ro}"${data}>
      <div class="qfm-icon${cls}"><i class="fas ${esc(fa)}"></i></div>
      <div class="qfm-body">
        <div class="qfm-item-title">${esc(o.title)}</div>
        ${o.desc ? `<div class="qfm-item-desc">${esc(o.desc)}</div>` : ''}
      </div>
      <div class="qfm-chev"><i class="fas fa-chevron-left"></i></div>
    </div>`;
  }
  window.QFM_SCREENS = window.QFM_SCREENS || {};
  window.QFM_SCREENS.f6_main = function(Q, p){
    const items = (p.items||[]).map(item).join('');
    const html = `
      <div class="qfm-header">
        <div class="qfm-title"><i class="fas fa-shield-halved" style="margin-left:8px;color:var(--qfm-gold-1)"></i>${esc(p.title||'نظام العوائل')}</div>
        ${p.subtitle ? `<div class="qfm-sub">${esc(p.subtitle)}</div>` : ''}
      </div>
      <div class="qfm-list">${items}</div>
      <div class="qfm-footer"><kbd>ESC</kbd> للإغلاق · <kbd>F6</kbd> لإعادة الفتح</div>`;
    Q.open(html);
    Q.bindItems();
  };
})();

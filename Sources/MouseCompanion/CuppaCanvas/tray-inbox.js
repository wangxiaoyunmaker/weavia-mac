/* Native-owned material summaries and explicit command queue. No canvas/storage writes. */
(() => {
  'use strict';
  if (globalThis.cuppaTrayInbox) return;
  const workspace = document.getElementById('workspace');
  if (!workspace) return;
  const currentProject = new URLSearchParams(location.search).get('project') || '';
  const page = crypto.randomUUID();
  let items = [], signature = '', available = false, busy = false, request = null;
  let status = '', selected = new Set(), drag = null;
  const panel = document.createElement('aside');
  panel.id = 'tray-inbox';
  panel.setAttribute('aria-label', '当前项目待整理素材');
  panel.innerHTML = `<button type="button" id="tray-inbox-toggle" aria-expanded="false" aria-controls="tray-inbox-body">待整理 <span id="tray-inbox-count">0</span><span aria-hidden="true"> ▾</span></button><div id="tray-inbox-body" hidden><p class="tray-inbox-help">当前项目的文字素材 · 选择后放入，或拖动手柄到画布空白处。原素材保留在托盘。</p><div class="tray-inbox-actions"><label><input type="checkbox" id="tray-inbox-all"> 全选</label><button type="button" id="tray-inbox-save">放入画布</button></div><div id="tray-inbox-list"></div><footer><button type="button" id="tray-inbox-open">打开全局托盘</button><p id="tray-inbox-status" role="status" aria-live="polite"></p></footer></div>`;
  workspace.append(panel);
  const el = id => document.getElementById('tray-inbox-' + id);
  const pending = () => items.filter(item => !item.saved);
  // Locked submissions can retry their frozen native payload; only repositioning is disabled.
  const eligible = () => pending();
  const disabled = () => !available || busy || !!request;
  const active = () => location.hash === '#cuppa' && !workspace.hidden && (new URLSearchParams(location.search).get('project') || '') === currentProject;
  const plain = value => typeof value === 'string' ? value : '';
  function update() {
    panel.classList.toggle('tray-inbox-collapsed', el('body').hidden);
    const rows = pending(), usable = eligible();
    selected = new Set([...selected].filter(id => usable.some(item => item.id === id)));
    el('count').textContent = String(rows.length);
    el('save').textContent = selected.size ? `放入画布 (${selected.size})` : '放入画布';
    el('save').disabled = disabled() || !selected.size;
    el('open').disabled = disabled();
    el('all').disabled = disabled() || !usable.length;
    el('all').checked = !!usable.length && selected.size === usable.length;
    el('all').indeterminate = !!selected.size && selected.size < usable.length;
    panel.querySelectorAll('[data-tray-select]').forEach(input => {
      input.checked = selected.has(input.dataset.traySelect);
      input.disabled = disabled();
    });
    panel.querySelectorAll('[data-tray-drag]').forEach(button => {
      button.disabled = disabled() || !!items.find(item => item.id === button.dataset.trayDrag)?.locked;
    });
    el('status').textContent = status || (!available ? '未连接原生托盘；请在应用内使用。' : request ? '正在等待托盘确认…' : busy ? '托盘正在处理，请稍候。' : rows.length ? '仅显示尚未放入画布的素材。' : '此项目暂无待整理素材。');
  }
  function render() {
    const list = el('list'), scroll = list.scrollTop;
    const focusId = document.activeElement?.dataset.traySelect || document.activeElement?.dataset.trayDrag;
    const focusDrag = !!document.activeElement?.dataset.trayDrag;
    list.replaceChildren();
    for (const item of pending()) {
      const row = document.createElement('article'); row.className = 'tray-inbox-item';
      const header = document.createElement('header');
      const label = document.createElement('label');
      const check = document.createElement('input'); check.type = 'checkbox'; check.dataset.traySelect = item.id;
      check.setAttribute('aria-label', '选择 ' + (item.title || '未命名素材'));
      check.onchange = () => { status = ''; check.checked ? selected.add(item.id) : selected.delete(item.id); update(); };
      const title = document.createElement('strong'); title.textContent = item.title || '未命名素材';
      label.append(check, title);
      const grip = document.createElement('button'); grip.type = 'button'; grip.dataset.trayDrag = item.id;
      grip.textContent = '⠿'; grip.setAttribute('aria-label', '拖动 ' + (item.title || '未命名素材') + ' 到画布；也可勾选后放入');
      grip.title = '按住拖到画布空白处；键盘请使用勾选和放入按钮';
      grip.onpointerdown = event => startDrag(event, item, grip);
      header.append(label, grip);
      const text = document.createElement('p'); text.className = 'tray-inbox-preview'; text.textContent = item.text;
      const source = document.createElement('small'); source.textContent = [item.sourceLabel, item.sourceURL, item.locked ? '待核对 · 勾选重试原提交' : ''].filter(Boolean).join(' · ') || '未标注来源';
      row.append(header, text, source); list.append(row);
    }
    list.scrollTop = scroll;
    if (focusId) [...panel.querySelectorAll(focusDrag ? '[data-tray-drag]' : '[data-tray-select]')].find(node => (focusDrag ? node.dataset.trayDrag : node.dataset.traySelect) === focusId)?.focus({preventScroll:true});
    update();
  }
  function enqueue(action, ids, placement) {
    if (disabled() || !active()) return false;
    const validIds = [...new Set(ids)].filter(id => eligible().some(item => item.id === id));
    if (action === 'save' && !validIds.length) return false;
    status = '';
    request = {token:crypto.randomUUID(), page, projectId:currentProject, action, ids:validIds, createdAt:Date.now()};
    if (placement) request.placement = placement;
    update(); return true;
  }
  function dropPoint(x, y) {
    if (!active()) return null;
    const r = workspace.getBoundingClientRect();
    if (x < r.left || x >= r.right || y < r.top || y >= r.bottom) return null;
    // Hit testing rejects cards, toolbars, dialogs and overlays, not just the panel rectangle.
    const hit = document.elementFromPoint(x, y);
    if (hit !== workspace && hit !== document.getElementById('world')) return null;
    const scale = typeof zoom === 'number' ? zoom : NaN;
    if (!Number.isFinite(scale) || scale <= 0 || typeof pan === 'undefined') return null;
    const point = {x:(x-r.left-pan.x)/scale, y:(y-r.top-pan.y)/scale};
    return Number.isFinite(point.x) && Number.isFinite(point.y) ? point : null;
  }
  function cancelDrag() {
    if (!drag) return;
    const prior = drag; drag = null;
    document.removeEventListener('pointermove', moveDrag, true);
    document.removeEventListener('pointerup', finishDrag, true);
    document.removeEventListener('pointercancel', cancelPointer, true);
    prior.ghost.remove(); panel.classList.remove('tray-inbox-dragging');
    if (prior.grip.hasPointerCapture(prior.pointerId)) prior.grip.releasePointerCapture(prior.pointerId);
  }
  function moveDrag(event) {
    if (!drag || event.pointerId !== drag.pointerId) return;
    event.preventDefault(); event.stopImmediatePropagation();
    drag.moved ||= Math.hypot(event.clientX-drag.x, event.clientY-drag.y) > 5;
    drag.ghost.hidden = !drag.moved;
    drag.ghost.style.left = event.clientX + 14 + 'px'; drag.ghost.style.top = event.clientY + 14 + 'px';
    drag.ghost.textContent = dropPoint(event.clientX,event.clientY) ? '松开放入画布' : '移到画布空白处 · Esc 取消';
  }
  function finishDrag(event) {
    if (!drag || event.pointerId !== drag.pointerId) return;
    event.preventDefault(); event.stopImmediatePropagation();
    const id = drag.id, point = drag.moved && dropPoint(event.clientX,event.clientY);
    cancelDrag();
    if (point) enqueue('save', [id], point);
  }
  function cancelPointer(event) { if (drag && event.pointerId === drag.pointerId) cancelDrag(); }
  function startDrag(event, item, grip) {
    if (event.button !== 0 || event.isPrimary === false || disabled() || item.locked || !active()) return;
    event.preventDefault(); event.stopPropagation(); cancelDrag(); status = '';
    if (typeof cancelCanvasAction === 'function') cancelCanvasAction();
    const ghost = document.createElement('div'); ghost.className = 'tray-inbox-ghost'; ghost.hidden = true; document.body.append(ghost);
    drag = {id:item.id, pointerId:event.pointerId, x:event.clientX, y:event.clientY, moved:false, grip, ghost};
    grip.setPointerCapture(event.pointerId); panel.classList.add('tray-inbox-dragging');
    document.addEventListener('pointermove', moveDrag, true);
    document.addEventListener('pointerup', finishDrag, true);
    document.addEventListener('pointercancel', cancelPointer, true); update();
  }
  panel.addEventListener('lostpointercapture', cancelPointer);
  for (const type of ['pointerdown','pointerup','click','dblclick','contextmenu']) panel.addEventListener(type, event => event.stopPropagation());
  panel.addEventListener('wheel', event => { event.stopPropagation(); if (event.ctrlKey || event.metaKey) event.preventDefault(); }, {passive:false});
  panel.addEventListener('keydown', event => { if (event.key !== 'Escape') event.stopPropagation(); });
  el('toggle').onclick = () => { cancelDrag(); const expand = el('body').hidden; if (expand) window.dispatchEvent(new CustomEvent('cuppa:auxiliary-open', { detail: { id: 'tray' } })); el('body').hidden = !expand; el('toggle').setAttribute('aria-expanded', String(expand)); update(); };
  window.addEventListener('cuppa:auxiliary-open', event => {
    if (event.detail?.id === 'tray') return;
    cancelDrag(); el('body').hidden = true; el('toggle').setAttribute('aria-expanded', 'false'); update();
  });
  el('all').onchange = () => { status = ''; selected = new Set(el('all').checked ? eligible().map(item => item.id) : []); update(); };
  el('save').onclick = () => enqueue('save', [...selected]);
  el('open').onclick = () => enqueue('open', []);
  // This module loads before canvas-toolkit: intercept at window capture so canvas
  // Delete/shortcut handlers never act while a tray control owns focus.
  window.addEventListener('keydown', event => {
    if (drag && event.key === 'Escape') { event.preventDefault(); event.stopImmediatePropagation(); cancelDrag(); return; }
    if (panel.contains(event.target)) { if (event.key === 'Escape' && !el('body').hidden) { event.preventDefault(); el('body').hidden = true; el('toggle').setAttribute('aria-expanded', 'false'); update(); el('toggle').focus(); } event.stopImmediatePropagation(); }
  }, true);
  document.addEventListener('visibilitychange', () => { if (document.hidden) cancelDrag(); });
  window.addEventListener('blur', cancelDrag);
  window.addEventListener('resize', cancelDrag);
  const navigate = () => { cancelDrag(); request = null; status = ''; update(); };
  window.addEventListener('hashchange', navigate);
  window.addEventListener('popstate', navigate);
  window.addEventListener('pagehide', navigate);
  globalThis.cuppaTrayInbox = Object.freeze({
    inspect() { return {page, projectId:currentProject, request:request && active() ? JSON.parse(JSON.stringify(request)) : null}; },
    // Native getWindowX/Y and ArkUI bounds are both vp. Native normalizes to
    // this Web component; scale to CSS viewport pixels before the shared hit
    // test so density, window offsets, pan and zoom are each accounted once.
    nativeDropPoint(x, y, expectedPage, expectedProject) {
      if (expectedPage !== page || expectedProject !== currentProject || disabled() || !active() ||
          !Number.isFinite(x) || !Number.isFinite(y) || x < 0 || y < 0 || x >= 1 || y >= 1 ||
          !Number.isFinite(innerWidth) || !Number.isFinite(innerHeight) || innerWidth <= 0 || innerHeight <= 0) return null;
      const placement = dropPoint(x * innerWidth, y * innerHeight);
      return placement ? {page, projectId:currentProject, placement} : null;
    },
    sync(snapshot) {
      if (!snapshot || snapshot.page !== page || snapshot.projectId !== currentProject || !Array.isArray(snapshot.items)) return false;
      const seen = new Set();
      const next = snapshot.items.filter(item => item && item.project === currentProject && typeof item.id === 'string' && item.id && !seen.has(item.id) && seen.add(item.id)).map(item => ({id:item.id,title:plain(item.title),text:plain(item.text),sourceLabel:plain(item.sourceLabel),sourceURL:plain(item.sourceURL),saved:item.saved === true,locked:item.locked === true}));
      const nextSignature = JSON.stringify(next), nextBusy = snapshot.busy === true;
      if (drag && (signature !== nextSignature || nextBusy || snapshot.error)) cancelDrag();
      available = true; busy = nextBusy;
      if (typeof snapshot.error === 'string' && snapshot.error) status = snapshot.error;
      items = next;
      // Native polling updates the count only. Open material details explicitly.
      if (signature !== nextSignature) { signature = nextSignature; render(); } else update();
      return true;
    },
    ack(token, result) {
      if (!request || request.token !== token || !active() || !result || typeof result.ok !== 'boolean') return false;
      request = null; status = plain(result.message) || (result.ok ? '托盘已确认；正在更新待整理列表。' : '未能完成，请重试。');
      update(); return true;
    }
  });
  update();
})();

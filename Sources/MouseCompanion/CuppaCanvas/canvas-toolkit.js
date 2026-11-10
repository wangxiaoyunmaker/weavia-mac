/* Canvas-only circling and annotation. No screenshot, OCR, network or automatic AI.
 * Only an explicit preview confirmation creates a short-lived native request. */
(() => {
  'use strict';
  if (globalThis.cuppaCanvasTools) return;
  const NS = 'http://www.w3.org/2000/svg';
  const workspace = $('#workspace'), toolbar = $('#canvas-toolbar');
  const modes = ['rectangle', 'lasso', 'pen'];
  const labels = { rectangle: '框选', lasso: '套索', pen: '画笔' };
  const paths = {
    rectangle: '<rect x="4" y="4" width="16" height="16" rx="1" stroke-dasharray="3 2"/>',
    lasso: '<path d="M19 15c2-2 2-5 0-7-3-4-10-4-13-1-4 4-2 9 3 10 4 1 8-1 8-3 0-2-4-1-4 1 0 3 3 4 5 2l2-3"/>',
    pen: '<path d="m5 20 4-14h6l4 14M9 6l3-4 3 4M8 11h8"/>',
    undo: '<path d="m9 5-5 5 5 5M4 10h10a6 6 0 0 1 0 12h-4" transform="translate(1 -2)"/>'
  };
  let gesture = null, history = [], preview = null, pending = null;
  let available = false, lastInk = null, validatedInk = null;
  const status = document.createElement('div');
  status.id = 'canvas-tool-status'; status.className = 'selection-sr-only';
  status.setAttribute('role', 'status'); status.setAttribute('aria-live', 'polite');
  workspace.append(status);
  const say = text => { status.textContent = text; };
  const divider = () => { const el = document.createElement('span'); el.className = 'canvas-tool-divider'; el.setAttribute('role', 'separator'); el.setAttribute('aria-orientation', 'horizontal'); return el; };
  // Match the original canvas: drawing tools stay visible, with no text toggle.
  const group = document.createElement('div'); group.id = 'canvas-mark-tools';
  group.setAttribute('role', 'group'); group.setAttribute('aria-label', '圈画与批注工具');
  group.append(divider());
  for (const mode of [...modes, 'undo']) {
    const b = document.createElement('button');
    b.type = 'button'; b.className = 'icon canvas-mark-tool'; b.id = 'canvas-' + mode + '-tool';
    const name = mode === 'undo' ? '撤销圈画' : labels[mode];
    b.setAttribute('aria-label', mode === 'rectangle' ? '框选画布材料' : mode === 'lasso' ? '套索画布材料' : mode === 'pen' ? '画笔批注' : name);
    if (mode !== 'undo') b.setAttribute('aria-pressed', 'false');
    b.title = name + ({ rectangle: ' M · 提取相交卡片文字', lasso: ' L · 按轮廓提取卡片文字', pen: ' B · 仅保存在此画布，不自动发送', undo: ' · 只撤销圈选或画笔，保留卡片与回答' })[mode];
    b.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true">' + paths[mode] + '</svg>';
    b.onclick = () => mode === 'undo' ? undo() : chooseTool(mode);
    group.append(b);
  }
  group.append(divider()); toolbar.insertBefore(group, $('#add-tool'));
  const inkLayer = document.createElementNS(NS, 'svg');
  inkLayer.id = 'canvas-ink-layer'; inkLayer.setAttribute('aria-label', '当前项目的画笔批注'); inkLayer.setAttribute('role', 'img');
  const inkWorld = document.createElementNS(NS, 'g'); inkLayer.append(inkWorld);
  const previewLayer = document.createElementNS(NS, 'svg');
  previewLayer.id = 'canvas-tool-preview'; previewLayer.setAttribute('aria-hidden', 'true');
  const previewPath = document.createElementNS(NS, 'path'); previewLayer.append(previewPath);
  workspace.insertBefore(inkLayer, $('#marquee-frame')); workspace.insertBefore(previewLayer, $('#marquee-frame'));
  const panel = document.createElement('section');
  panel.id = 'canvas-context-panel'; panel.className = 'floating'; panel.hidden = true;
  panel.setAttribute('aria-label', '圈画材料确认');
  panel.innerHTML = '<header><div><strong>圈画参考</strong><small id="canvas-context-count"></small></div><button type="button" id="canvas-context-close" aria-label="关闭圈画材料预览">×</button></header>' +
    '<p class="canvas-context-scope">按轮廓命中卡片，提取整张卡片的文字与来源。这不是局部截图或 OCR；图片、画笔笔迹不会传给伙伴。</p>' +
    '<div id="canvas-context-cards"></div><details id="canvas-context-details"><summary>查看将加入的文字</summary><textarea id="canvas-context-text" readonly aria-label="将加入伙伴的文字预览"></textarea></details>' +
    '<p id="canvas-context-warning"></p><footer><button type="button" id="canvas-context-add" class="primary">加入伙伴参考</button><button type="button" id="canvas-context-card-actions">卡片操作</button></footer><p id="canvas-context-status" role="status" aria-live="polite"></p>';
  workspace.append(panel);
  const previewToggle = document.createElement('button');
  previewToggle.type = 'button'; previewToggle.id = 'canvas-context-toggle'; previewToggle.className = 'floating'; previewToggle.hidden = true;
  previewToggle.setAttribute('aria-controls', 'canvas-context-panel'); previewToggle.setAttribute('aria-expanded', 'false');
  workspace.append(previewToggle);
  const announcePanel = id => window.dispatchEvent(new CustomEvent('cuppa:auxiliary-open', { detail: { id } }));
  function syncPreviewToggle() {
    previewToggle.hidden = !preview || !panel.hidden;
    previewToggle.textContent = '圈画参考 · ' + (preview?.checked.size || 0);
    previewToggle.setAttribute('aria-expanded', String(!panel.hidden));
  }
  function expandPreview() { if (!preview) return; announcePanel('context'); panel.hidden = false; syncPreviewToggle(); }
  previewToggle.onclick = expandPreview;
  const searchShell = $('#search-shell');
  function showSearch() { announcePanel('search'); searchShell.hidden = false; }
  // The original search input is permanent. Only its source choices collapse.
  function hideSearch() { closeSources(); }
  window.addEventListener('cuppa:auxiliary-open', event => {
    const id = event.detail?.id;
    if (id !== 'context') { panel.hidden = true; syncPreviewToggle(); }
    if (id !== 'search') hideSearch();
    if (id !== 'selection') $('#selection-actions').hidden = true;
  });
  $('#canvas-context-close').onclick = closePreview;
  $('#canvas-context-add').onclick = requestContext;
  $('#canvas-context-card-actions').onclick = () => {
    if (!preview || !preview.checked.size || preview.checked.size > 8 || pending) return;
    applySelection([...preview.checked], null);
    panel.hidden = true; pending = null; syncPreviewToggle();
    if (marqueeIds.size && !globalThis.mouseCompanionMac?.completeSelectionGesture(tool)) { $('#selection-actions').hidden = false; revealSelectionMenu(); }
  };

  function validPoint(p) { return Array.isArray(p) && p.length === 2 && p.every(n => Number.isFinite(n) && Math.abs(n) <= 100000); }
  function ink() {
    const data = state.canvasInk;
    if (data && data === validatedInk) return data;
    if (data === undefined) return { version: 1, strokes: [] };
    if (!data || data.version !== 1 || !Array.isArray(data.strokes) || data.strokes.length > 2000 ||
      data.strokes.some(s => !s || typeof s.id !== 'string' || !Array.isArray(s.points) || s.points.length < 2 || s.points.length > 4096 || !s.points.every(validPoint))) {
      throw Error('画笔数据格式暂不支持，原内容未修改。');
    }
    validatedInk = data; return data;
  }
  function strokeElement(stroke) {
    const line = document.createElementNS(NS, 'polyline');
    line.setAttribute('points', claimStrokePoints(stroke));
    line.setAttribute('data-ink-id', stroke.id);
    line.setAttribute('fill', 'none'); line.setAttribute('stroke', '#2563eb');
    line.setAttribute('stroke-width', '2.5'); line.setAttribute('stroke-linecap', 'round'); line.setAttribute('stroke-linejoin', 'round');
    return line;
  }
  function render() {
    if (gesture && (gesture.state !== state || gesture.pan.x !== pan.x || gesture.pan.y !== pan.y || gesture.zoom !== zoom)) abortGesture();
    inkWorld.setAttribute('transform', 'translate(' + pan.x + ' ' + pan.y + ') scale(' + zoom + ')');
    try {
      const data = ink();
      if (state.canvasInk !== lastInk) {
        inkWorld.replaceChildren(...data.strokes.map(strokeElement)); lastInk = state.canvasInk;
      }
    } catch (_) { /* Keep unknown stored data untouched. Drawing displays its error on use. */ }
    updateUndo();
  }
  function persistInk(strokes) {
    if (globalThis.cuppaBootstrap?.error) throw Error(globalThis.cuppaBootstrap.error);
    ink(); // Reject unknown future data rather than overwriting it.
    if (strokes.length > 2000 || strokes.some(s => !s.id || s.points.length < 2 || s.points.length > 4096 || !s.points.every(validPoint))) throw Error('笔迹超出画布范围，未修改原内容。');
    const next = { ...state, canvasInk: { version: 1, strokes } };
    // Preserve the current snapshot and all native receipts; commit before changing visible state.
    persistCanvasSnapshot(next);
    state.canvasInk = next.canvasInk; state._companionPersistence = next._companionPersistence;
    render();
  }
  function remember(entry) { history.push(entry); if (history.length > 100) history.shift(); updateUndo(); }
  function selectionSnapshot() { return { ids: [...marqueeIds], selected }; }
  function applySelection(ids, single) {
    selected = single && state.cards.some(c => c.id === single) ? single : null;
    clearMarqueeSelection();
    marqueeIds = new Set(ids.filter(id => state.cards.some(c => c.id === id)));
    syncMarqueeSelection();
  }
  function updateUndo() {
    let hasInk = false; try { hasInk = ink().strokes.length > 0; } catch (_) {}
    $('#canvas-undo-tool').disabled = !gesture && !history.length && !hasInk;
  }
  function undo() {
    if (pending) { notify('请先完成或关闭伙伴参考预览。'); return; }
    if (gesture) { abortGesture(); notify('已撤销正在进行的圈画。'); return; }
    const entry = history[history.length - 1];
    if (entry?.kind === 'selection') {
      history.pop();
      const now = selectionSnapshot();
      if (JSON.stringify(now) === JSON.stringify(entry.after)) applySelection(entry.before.ids, entry.before.selected);
      closePreview(); updateUndo(); say('已撤销上一次圈选，卡片内容未改变。'); return;
    }
    try {
      const data = ink(), target = entry?.kind === 'ink' ? data.strokes.find(s => s.id === entry.id) : data.strokes[data.strokes.length - 1];
      if (!target) { if (entry) history.pop(); updateUndo(); notify('该笔迹已变化，未修改其他内容。'); return; }
      persistInk(data.strokes.filter(s => s !== target));
      if (entry) history.pop();
      closePreview(); updateUndo(); say('已撤销最近一笔，卡片和回答仍保留。');
    } catch (error) { notify(error.message || '撤销未保存，原笔迹仍保留。'); }
  }

  function pointInPolygon(point, polygon) {
    let inside = false;
    for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      const a = polygon[i], b = polygon[j];
      if ((a.y > point.y) !== (b.y > point.y) && point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x) inside = !inside;
    }
    return inside;
  }
  function segmentHitsRect(a, b, r) {
    let lo = 0, hi = 1; const dx = b.x - a.x, dy = b.y - a.y;
    for (const [p, q] of [[-dx, a.x - r.x], [dx, r.x + r.width - a.x], [-dy, a.y - r.y], [dy, r.y + r.height - a.y]]) {
      if (p === 0) { if (q < 0) return false; }
      else { const t = q / p; if (p < 0) lo = Math.max(lo, t); else hi = Math.min(hi, t); if (lo > hi) return false; }
    }
    return true;
  }
  function polygonHitsRect(points, r) {
    if (points.length < 3) return false;
    const corners = [{ x: r.x, y: r.y }, { x: r.x + r.width, y: r.y }, { x: r.x + r.width, y: r.y + r.height }, { x: r.x, y: r.y + r.height }];
    return corners.some(p => pointInPolygon(p, points)) || points.some(p => p.x >= r.x && p.x <= r.x + r.width && p.y >= r.y && p.y <= r.y + r.height) ||
      points.some((p, i) => segmentHitsRect(p, points[(i + 1) % points.length], r));
  }
  function hitCards(g) {
    if (g.kind === 'rectangle') {
      const b = normalizedSelection(g.points[0], g.points[g.points.length - 1]);
      return g.rects.filter(v => selectionIntersects(b, v.rect)).map(v => v.id);
    }
    return g.rects.filter(v => g.kind === 'lasso' ? polygonHitsRect(g.points, v.rect) : g.points.slice(1).some((p, i) => segmentHitsRect(g.points[i], p, { x: v.rect.x - 5, y: v.rect.y - 5, width: v.rect.width + 10, height: v.rect.height + 10 }))).map(v => v.id);
  }
  function sameScene(g) {
    return !workspace.hidden && g.state === state && g.zoom === zoom && g.pan.x === pan.x && g.pan.y === pan.y &&
      g.rects.every(v => { const el = cardElement(v.id); if (!el) return false; const r = cardRect(el); return ['x', 'y', 'width', 'height'].every(k => Math.abs(r[k] - v.rect[k]) < .5); });
  }
  function drawGesture(g) {
    g.frame = 0;
    if (!sameScene(g)) { abortGesture(); return; }
    if (g.kind === 'rectangle') {
      const b = normalizedSelection(g.points[0], g.points[g.points.length - 1]);
      previewPath.setAttribute('d', 'M' + b.x + ' ' + b.y + 'h' + b.width + 'v' + b.height + 'h-' + b.width + 'Z');
    } else {
      previewPath.setAttribute('d', g.points.map((p, i) => (i ? 'L' : 'M') + p.x + ' ' + p.y).join(' ') + (g.kind === 'lasso' ? 'Z' : ''));
    }
    previewLayer.dataset.kind = g.kind;
    if (g.kind !== 'pen') {
      const ids = new Set(hitCards(g));
      $$('.card').forEach(el => el.classList.toggle('selected', ids.has(el.dataset.id)));
    }
  }
  function surface(target) {
    if (!(target instanceof Element)) return false;
    return target === workspace || !!target.closest('#world,#region-layer,#connection-layer,#port-layer');
  }
  function begin(e) {
    if (gesture) { if (e.pointerId !== gesture.pointerId) abortGesture(); return; }
    if (!modes.includes(tool) || !surface(e.target) || workspace.hidden || document.querySelector('dialog[open]') || picking || canvasAction ||
      e.button !== 0 || e.isPrimary === false || cardDragActive || globalThis.cuppaCaptureBusy || globalThis.cuppaRelationBusy) return;
    if (pending) { e.preventDefault(); e.stopImmediatePropagation(); notify('请先完成或关闭伙伴参考预览。'); return; }
    if (tool === 'pen') {
      try { if (ink().strokes.length >= 2000) throw Error('此画布已有 2000 笔，请撤销部分笔迹后继续。'); if (globalThis.cuppaBootstrap?.error) throw Error(globalThis.cuppaBootstrap.error); }
      catch (error) { e.preventDefault(); e.stopImmediatePropagation(); notify(error.message); return; }
    }
    e.preventDefault(); e.stopImmediatePropagation();
    const before = selectionSnapshot();
    globalThis.mouseCompanionMac?.beginSelectionGesture();
    document.activeElement?.blur(); globalThis.cuppaCompanion?.cancel();
    globalThis.mouseCompanionActions?.execute({ op: 'cancel' });
    cancelCanvasAction(); hidePort(); if (typeof hideTagTools === 'function') hideTagTools();
    closeSources(); showCreationMenu(null); clearMarqueeSelection(); panel.hidden = true; syncPreviewToggle();
    const first = clientPoint(e);
    gesture = { kind: tool, pointerId: e.pointerId, points: [first], state, pan: { ...pan }, zoom, frame: 0, before, rects: $$('.card').map(el => ({ id: el.dataset.id, rect: cardRect(el) })) };
    marqueeDragging = true; workspace.classList.add('canvas-marking'); updateUndo();
    try { workspace.setPointerCapture(e.pointerId); } catch (_) { abortGesture(); return; }
    drawGesture(gesture);
  }
  function move(e) {
    const g = gesture; if (!g || e.pointerId !== g.pointerId) return;
    e.preventDefault(); e.stopImmediatePropagation();
    const samples = e.getCoalescedEvents?.() || [];
    for (const sample of samples.length ? samples : [e]) {
      const p = clientPoint(sample), last = g.points[g.points.length - 1];
      p.x = Math.max(0, Math.min(workspace.clientWidth, p.x)); p.y = Math.max(0, Math.min(workspace.clientHeight, p.y));
      if (g.kind === 'rectangle') g.points = [g.points[0], p];
      else if (Math.hypot(p.x - last.x, p.y - last.y) >= 1) {
        if (g.points.length >= 4095) g.points = g.points.filter((_, i) => i % 2 === 0);
        g.points.push(p);
      }
    }
    if (!g.frame) g.frame = requestAnimationFrame(() => { if (gesture === g) drawGesture(g); });
  }
  function cleanGesture(g) {
    gesture = null; if (g.frame) cancelAnimationFrame(g.frame);
    previewPath.removeAttribute('d'); marqueeDragging = false; workspace.classList.remove('canvas-marking');
    if (workspace.hasPointerCapture(g.pointerId)) workspace.releasePointerCapture(g.pointerId);
    updateUndo();
  }
  function abortGesture() {
    if (!gesture) return;
    const g = gesture; cleanGesture(g); applySelection(g.before.ids, g.before.selected);
    say('已取消本次圈画，之前的内容仍保留。');
  }
  function finish(e) {
    const g = gesture; if (!g || e.pointerId !== g.pointerId) return;
    e.preventDefault(); e.stopImmediatePropagation();
    move(e); if (!gesture) return;
    const valid = sameScene(g), points = g.points;
    const extent = Math.max(...points.map(p => p.x)) - Math.min(...points.map(p => p.x)) + Math.max(...points.map(p => p.y)) - Math.min(...points.map(p => p.y));
    if (!valid || extent < 6 || (g.kind === 'lasso' && points.length < 3)) { abortGesture(); return; }
    const ids = hitCards(g); cleanGesture(g);
    if (g.kind === 'pen') {
      const stroke = { id: crypto.randomUUID(), createdAt: new Date().toISOString(), points: points.map(p => [(p.x - g.pan.x) / g.zoom, (p.y - g.pan.y) / g.zoom]) };
      try {
        persistInk([...ink().strokes, stroke]); remember({ kind: 'ink', id: stroke.id });
      } catch (error) {
        applySelection(g.before.ids, g.before.selected);
        notify((error.message || '画笔保存失败。') + ' 本笔未写入，请重画；原内容仍保留。'); return;
      }
    }
    applySelection(ids, null);
    if (g.kind !== 'pen') remember({ kind: 'selection', before: g.before, after: selectionSnapshot() });
    if (g.kind !== 'pen' && globalThis.mouseCompanionMac?.completeSelectionGesture(g.kind)) {
      closePreview();
      say(labels[g.kind] + '已选 ' + ids.length + ' 张卡片，可以直接向伙伴提问。');
      return;
    }
    showPreview(ids, g.kind);
    say(g.kind === 'pen' ? '画笔已保存在此项目，未发送给伙伴。' : labels[g.kind] + '命中 ' + ids.length + ' 张卡片，请确认参考文字。');
  }

  function currentName() {
    return document.querySelector('[data-project-name]')?.textContent?.trim() || (projectId ? '当前项目' : 'CUPPA');
  }
  function buildContext() {
    if (!preview) return { cards: [], text: '', truncated: false, visual: false };
    const cards = state.cards.filter(c => preview.checked.has(c.id));
    let truncated = false, visual = preview.kind === 'pen';
    const sections = cards.map((c, i) => {
      visual = visual || !!(c.image || c.preview || globalThis.CuppaTrayImageAssets?.isPrivate(c) || c.blocks?.some(b => b.type === 'doodle'));
      const full = String(c.type === 'claim' ? claimPlainText(c) : c.type === 'design' ? designSearchText(c) : c.text || '');
      const text = full.slice(0, 6000); if (full.length > text.length) truncated = true;
      const url = /^https?:\/\//i.test(c.url || '') ? String(c.url).slice(0, 2000) : '';
      return '材料 ' + (i + 1) + '：' + String(c.title || '未命名卡片').slice(0, 200) + '\n' + (text || '（此卡片没有可提取的文字）') + (url ? '\n来源：' + url : '');
    });
    const whole = sections.join('\n\n'), text = whole.slice(0, 16000);
    if (whole.length > text.length) truncated = true;
    return { cards, text, truncated, visual };
  }
  function refreshPreview(message = '') {
    if (!preview) return;
    const data = buildContext(), count = data.cards.length;
    syncPreviewToggle();
    preview.signature = JSON.stringify([data.cards.map(c => c.id), data.text]);
    $('#canvas-context-count').textContent = labels[preview.kind] + ' · ' + count + ' 张材料' + (preview.kind === 'pen' ? ' · 笔迹已保存' : '');
    $('#canvas-context-text').value = data.text;
    $('#canvas-context-details').hidden = !count;
    const warnings = [];
    if (preview.kind === 'pen') warnings.push('笔迹是此项目的批注，不是截图；加入参考只携带标注命中卡片的文字。');
    if (!count) warnings.push(preview.kind === 'pen' ? '这笔未经过卡片。可继续标注，或框选/套索材料。' : '没有选中卡片。请重新圈选，或在上方勾选材料。');
    if (count > 8) warnings.push('每次最多 8 张，请取消勾选部分材料。');
    if (data.truncated) warnings.push('长材料已截取：单卡最多 6000 字、合计最多 16000 字。请展开预览核对。');
    $('#canvas-context-warning').textContent = warnings.join(' ');
    const add = $('#canvas-context-add');
    add.disabled = !available || !count || count > 8 || !!pending || !!globalThis.cuppaBootstrap?.error;
    add.textContent = pending ? '等待伙伴确认…' : '加入伙伴参考';
    $('#canvas-context-card-actions').disabled = !count || count > 8 || !!pending;
    $('#canvas-context-status').textContent = message || (pending ? '请在伙伴窗口确认，尚未发送模型。' : available ? '加入后仍需在伙伴窗口确认；不会自动发送模型。' : '伙伴参考入口需在鸿蒙应用中使用；这里仍可圈选、批注和操作卡片。');
  }
  function showPreview(ids, kind) {
    pending = null; preview = { ids: [...ids], checked: new Set(ids), kind };
    $('#selection-actions').hidden = true;
    const list = $('#canvas-context-cards'); list.replaceChildren();
    state.cards.filter(c => ids.includes(c.id)).forEach(c => {
      const row = document.createElement('label'), box = document.createElement('input'), title = document.createElement('span');
      box.type = 'checkbox'; box.checked = true; box.value = c.id; title.textContent = c.title || '未命名卡片';
      box.onchange = () => { if (pending) { box.checked = preview.checked.has(c.id); return; } box.checked ? preview.checked.add(c.id) : preview.checked.delete(c.id); refreshPreview(); };
      row.append(box, title); list.append(row);
    });
    expandPreview(); refreshPreview();
  }
  let inspirationSession = false, inspirationMode = 'focus', inspirationCommand = null, inspirationAccepted = '';
  function closePreview() { pending = null; preview = null; panel.hidden = true; syncPreviewToggle(); }
  function requestContext() {
    if (pending || !available || !preview) return;
    const data = buildContext();
    if (!data.cards.length || data.cards.length > 8 || workspace.hidden || globalThis.cuppaBootstrap?.error) { refreshPreview('所选材料已变化，请重新确认。'); return; }
    if (preview.signature !== JSON.stringify([data.cards.map(c => c.id), data.text])) { refreshPreview('材料已更新，请核对新版文字后再加入。'); return; }
    pending = { stage: 'queued', payload: {
      token: crypto.randomUUID(), projectId, projectName: currentName().slice(0, 200),
      title: (currentName() + ' · ' + labels[preview.kind] + ' ' + data.cards.length + ' 张材料').slice(0, 200),
      text: data.text, kind: 'canvas_cards_text', hasVisualContent: data.visual,
      selectionIds: data.cards.map(c => c.id), selectionTool: preview.kind, createdAt: Date.now()
    } };
    refreshPreview('等待伙伴打开本机预览，尚未加入参考或发送模型。');
  }
  function onToolChange(next) {
    abortGesture();
    for (const mode of modes) {
      const b = $('#canvas-' + mode + '-tool'); b.classList.toggle('active', next === mode); b.setAttribute('aria-pressed', String(next === mode));
    }
    workspace.classList.toggle('canvas-mark-tool-active', modes.includes(next));
    if (modes.includes(next)) {
      if (picking) $('#cancel-pick').click();
      closeSources(); showCreationMenu(null); $('#selection-actions').hidden = true;
      say(next === 'pen' ? '画笔：在画布标注，笔迹只保存在当前项目。Esc 返回选择。' : labels[next] + '：圈选卡片后预览完整文字，不是截图。Esc 返回选择。');
    }
    if (preview && next !== preview.kind) closePreview();
  }
  globalThis.cuppaCanvasTools = Object.freeze({ render, onToolChange, cancel: abortGesture, showSearch, resetHistory: () => { history = []; closePreview(); render(); } });
  globalThis.cuppaInspirationV1 = Object.freeze({
    take(mode) { inspirationMode = mode === 'cocreate' ? 'cocreate' : 'focus'; const result = inspirationCommand; inspirationCommand = null; return result; }
  });
  window.addEventListener('keydown', e => {
    if (inspirationMode !== 'cocreate' || workspace.hidden || location.hash !== '#cuppa' || e.isComposing || e.ctrlKey || e.metaKey || e.altKey || e.shiftKey || e.key !== '/' || document.querySelector('dialog[open]') || e.target.closest?.('input,textarea,select,[contenteditable]')) return;
    e.preventDefault();e.stopImmediatePropagation();inspirationCommand={action:'start',at:Date.now()};
  }, true);
  globalThis.cuppaContextCapture = Object.freeze({
    beginInspiration() { if(workspace.hidden || location.hash !== '#cuppa') return false; if(!inspirationSession){inspirationSession=true;inspirationAccepted='';} return true; },
    endInspiration() { inspirationSession=false;inspirationAccepted='';abortGesture();closePreview();if(modes.includes(tool))chooseTool('select');return true; },
    prepareForPrompt() {
      // Only the explicit “加入伙伴参考” button may queue material confirmation.
      if (!pending) return { hasSelection: false };
      return { hasSelection: true, ready: true, token: pending.payload.token };
    },
    configure(options) { const next = options?.available === true; if (available !== next) { available = next; refreshPreview(); } return { available }; },
    peek() {
      if (!pending || workspace.hidden || location.hash !== '#cuppa' || Date.now() - pending.payload.createdAt > 120000) {
        if (pending) { pending = null; refreshPreview('本次参考请求已过期或画布已关闭，未继续加入。'); }
        return null;
      }
      return JSON.parse(JSON.stringify(pending.payload));
    },
    ack(token, result) {
      if (!pending || token !== pending.payload.token || !result || !['reviewing', 'added', 'cancelled', 'error'].includes(result.status)) return false;
      const message = String(result.message || ({ reviewing: '请在伙伴窗口确认参考文字。', added: '已加入伙伴参考，未发送模型。', cancelled: '已取消加入参考。', error: '加入参考失败，请重试。' })[result.status]).slice(0, 500);
      if(result.status==='added' && preview)inspirationAccepted=JSON.stringify([buildContext().cards.map(c=>c.id),buildContext().text]);
      if (result.status === 'reviewing') pending.stage = 'reviewing'; else pending = null;
      refreshPreview(message); say(message); return true;
    }
  });
  window.addEventListener('pointerdown', begin, true);
  window.addEventListener('pointermove', move, { capture: true, passive: false });
  window.addEventListener('pointerup', finish, true);
  const cancelPointer = e => { if (gesture && e.pointerId === gesture.pointerId) abortGesture(); };
  window.addEventListener('pointercancel', cancelPointer, true);
  workspace.addEventListener('lostpointercapture', cancelPointer);
  window.addEventListener('blur', abortGesture);
  window.addEventListener('resize', abortGesture);
  window.addEventListener('pagehide', () => { abortGesture(); closePreview(); hideSearch(); inspirationCommand = null; });
  window.addEventListener('hashchange', () => { abortGesture(); closePreview(); hideSearch();  inspirationCommand = null; if (modes.includes(tool)) chooseTool('select'); });
  document.addEventListener('visibilitychange', () => { if (document.hidden) abortGesture(); });
  window.addEventListener('wheel', e => { if (gesture) { e.preventDefault(); e.stopImmediatePropagation(); } }, { capture: true, passive: false });
  window.addEventListener('click', e => {
    if (modes.includes(tool) && surface(e.target)) { e.preventDefault(); e.stopImmediatePropagation(); }
  }, true);
  window.addEventListener('keydown', e => {
    if (workspace.hidden || document.querySelector('dialog[open]') || e.isComposing) return;
    const editing = e.target instanceof Element && e.target.closest('input,textarea,select,[contenteditable]');
    if (e.key === 'Escape' && (gesture || (!editing && inspirationSession && $('#source-panel').hidden && $('#add-menu').hidden && $('#more-menu').hidden) || ((!editing || e.target.closest('#canvas-context-panel')) && (modes.includes(tool) || !panel.hidden)))) {
      e.preventDefault(); e.stopImmediatePropagation();
      if(inspirationSession){inspirationCommand={action:'end',at:Date.now()};inspirationSession=false;}
      if (gesture) abortGesture(); else { closePreview(); chooseTool('select'); }
      return;
    }
    if (e.key === 'Escape' && !$('#source-panel').hidden && $('#add-menu').hidden && $('#more-menu').hidden && !picking) { e.preventDefault(); e.stopImmediatePropagation(); hideSearch(); $('#query').focus(); return; }
    if (editing) return;
    if (!globalThis.cuppaCanvasHistory && (e.ctrlKey || e.metaKey) && !e.altKey && !e.shiftKey && e.key.toLowerCase() === 'z' && (modes.includes(tool) || history.length || !panel.hidden)) {
      e.preventDefault(); e.stopImmediatePropagation(); undo(); return;
    }
    if (e.ctrlKey || e.metaKey || e.altKey || e.shiftKey) return;
    const mode = { m: 'rectangle', l: 'lasso', b: 'pen' }[e.key.toLowerCase()];
    if (mode) { e.preventDefault(); e.stopImmediatePropagation(); globalThis.mouseCompanionActions?.execute({ op: 'cancel' }); chooseTool(mode); }
  }, true);
  // Arrow navigation stays within the toolbar; Enter/Space use each normal button.
  toolbar.addEventListener('keydown', e => {
    if (e.target.closest('.menu') || !['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(e.key)) return;
    const buttons = [...toolbar.querySelectorAll('button:not(:disabled)')].filter(button => !button.closest('.menu,[hidden]'));
    const i = buttons.indexOf(document.activeElement); if (i < 0) return;
    e.preventDefault(); e.stopPropagation();
    const next = e.key === 'Home' ? 0 : e.key === 'End' ? buttons.length - 1 : (i + (e.key === 'ArrowDown' ? 1 : -1) + buttons.length) % buttons.length;
    buttons[next].focus();
  });
  render(); onToolChange(tool);
})();

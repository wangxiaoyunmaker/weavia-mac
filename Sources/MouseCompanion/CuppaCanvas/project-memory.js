/* Only explicit user saves enter memory; external model requests never read this store. */
(() => {
  const dialog = document.getElementById('memory-dialog');
  const launch = document.getElementById('open-project-memory');
  if (!dialog || !launch) return;
  const store = globalThis.mouseCompanionMac ? mouseCompanionMac.createMemoryStore(projectId) : createDurableProjectMemoryStore(projectId);
  const byId = id => document.getElementById(id);
  const labels = { goal: '项目目标', constraint: '已确认条件', question: '待探索问题' };
  const provenance = { goal: '用户明确填写', constraint: '用户明确确认', question: '尚待探索，不是事实' };
  let snapshot = null, editingId = null, baseline = '', returnFocus = launch, afterDiscard = null, routeDraft = null, busy = false;
  const form = byId('memory-form'), kind = byId('memory-kind'), text = byId('memory-text'), confirm = byId('memory-confirm');
  function status(message, error = false) { byId('memory-status').textContent = message; byId('memory-status').dataset.error = String(error); }
  function draftValue() { return JSON.stringify({ kind: kind.value, text: text.value, confirmed: confirm.checked }); }
  function dirty() { return !form.hidden && draftValue() !== baseline; }
  function controls() { dialog.querySelectorAll('button, input, select, textarea').forEach(node => { if (busy) { node.dataset.wasDisabled = String(node.disabled); node.disabled = true; } else if (node.dataset.wasDisabled !== undefined) { node.disabled = node.dataset.wasDisabled === 'true'; delete node.dataset.wasDisabled; } }); }
  async function operation(action) { if (busy) return; busy = true; controls(); try { await action(); } finally { busy = false; controls(); counts(); updateEditor(); if (form.hidden && dialog.open) byId('memory-add').focus(); } }
  function counts() {
    const entries = snapshot?.document.entries || [];
    byId('memory-count').textContent = entries.length ? entries.length + ' 条' : '手动管理';
    byId('memory-summary').textContent = snapshot ? Object.keys(labels).map(key => labels[key] + ' ' + entries.filter(item => item.kind === key).length).join('  ·  ') : '未能读取项目记忆';
    byId('memory-undo').disabled = busy || !snapshot || !store.canUndo(snapshot.token) || !form.hidden;
    byId('memory-add').disabled = busy || !snapshot || !form.hidden;
  }
  function render() {
    const list = byId('memory-list');
    list.replaceChildren();
    if (!snapshot) { counts(); return; }
    for (const key of Object.keys(labels)) {
      const section = document.createElement('section'); section.className = 'memory-section';
      const heading = document.createElement('h3'); heading.textContent = labels[key]; section.append(heading);
      const entries = snapshot.document.entries.filter(item => item.kind === key);
      if (!entries.length) { const empty = document.createElement('p'); empty.className = 'memory-empty'; empty.textContent = '暂无' + labels[key]; section.append(empty); }
      for (const item of entries) {
        const article = document.createElement('article'); article.className = 'memory-item';
        const body = document.createElement('p'); body.textContent = item.text;
        const footer = document.createElement('footer'), origin = document.createElement('small');
        origin.textContent = provenance[key]; footer.append(origin);
        const edit = document.createElement('button'); edit.type = 'button'; edit.textContent = '编辑'; edit.setAttribute('aria-label', '编辑' + labels[key]);
        edit.onclick = () => guarded(() => startEdit(item.id));
        const remove = document.createElement('button'); remove.type = 'button'; remove.textContent = '移除'; remove.setAttribute('aria-label', '移除' + labels[key]);
        remove.onclick = () => guarded(() => operation(async () => { try { snapshot = await store.remove(snapshot.token, item.id); clearEditor(); render(); status('已移除，可撤销本次修改。'); byId('memory-undo').focus(); } catch (error) { status(error.message, true); } }));
        footer.append(edit, remove); article.append(body, footer); section.append(article);
      }
      list.append(section);
    }
    counts();
  }
  async function load() {
    try { snapshot = await store.read(); render(); status('仅保存在本机当前项目，不会自动发给模型。'); return true; }
    catch (error) { snapshot = null; render(); status(error.message, true); return false; }
  }
  function clearEditor() { form.hidden = true; editingId = null; baseline = ''; byId('memory-discard').hidden = true; afterDiscard = null; counts(); }
  function updateEditor() {
    byId('memory-confirm-row').hidden = kind.value !== 'constraint';
    byId('memory-kind-hint').textContent = kind.value === 'constraint' ? '仅记录你已确认的要求或判断，不把 AI 推测当作事实。' : kind.value === 'question' ? '保留未解决的问题。问题不会被视为已确认结论。' : '记录你明确提出的项目目标，不自动提取卡片或聊天内容。';
    byId('memory-counter').textContent = text.value.length + ' / 1000';
    byId('memory-save').disabled = busy || !snapshot || !text.value.trim() || (kind.value === 'constraint' && !confirm.checked);
  }
  function startEdit(id) {
    const item = id ? snapshot.document.entries.find(value => value.id === id) : null;
    if (id && !item) return;
    editingId = item?.id || null; kind.value = item?.kind || 'goal'; text.value = item?.text || ''; confirm.checked = false;
    form.hidden = false; byId('memory-editor-title').textContent = item ? '编辑记忆' : '新增记忆'; baseline = draftValue();
    byId('memory-discard').hidden = true; afterDiscard = null; updateEditor(); counts(); status('保存前只是草稿，关闭或取消不会改动已存记忆。'); text.focus();
  }
  function guarded(action) {
    if (busy) return;
    if (!dirty()) { action(); return; }
    afterDiscard = action; byId('memory-discard').hidden = false; byId('memory-keep-editing').focus();
  }
  launch.onclick = async () => {
    if (dialog.open || busy) return;
    returnFocus = document.activeElement; clearEditor();
    byId('memory-project-name').textContent = document.querySelector('[data-project-name]')?.textContent || 'CUPPA';
    dialog.showModal(); byId('memory-close').focus();
    await operation(load);
    if (dialog.open && routeDraft) { editingId = routeDraft.editingId; kind.value = routeDraft.kind; text.value = routeDraft.text; confirm.checked = false; baseline = routeDraft.baseline; form.hidden = false; byId('memory-editor-title').textContent = editingId ? '编辑记忆' : '新增记忆'; routeDraft = null; updateEditor(); counts(); status('已恢复切换页面前的草稿，请核对后保存。'); text.focus(); }
  };
  byId('memory-close').onclick = () => guarded(() => dialog.close());
  dialog.addEventListener('cancel', event => { event.preventDefault(); guarded(() => dialog.close()); });
  dialog.addEventListener('close', () => { if (dialog.open) return; clearEditor(); returnFocus?.focus(); });
  // This dialog lives outside the canvas; stop canvas shortcuts in capture phase.
  window.addEventListener('keydown', event => {
    if (!dialog.open) return;
    event.stopPropagation();
    if (event.key === 'Escape') { event.preventDefault(); if (!event.isComposing) guarded(() => dialog.close()); }
  }, true);
  window.addEventListener('hashchange', () => { if (dialog.open) { if (dirty()) routeDraft = { editingId, kind: kind.value, text: text.value, baseline }; dialog.close(); } });
  byId('memory-add').onclick = () => startEdit(null);
  byId('memory-cancel').onclick = () => guarded(() => { clearEditor(); status('未保存的修改已取消。'); byId('memory-add').focus(); });
  byId('memory-reload').onclick = () => operation(async () => {
    // Reload preserves a pending draft while refreshing its optimistic write token.
    const loaded = await load();
    if (loaded && !form.hidden) { counts(); status('已重新读取。编辑草稿仍保留，请核对后再保存。'); }
  });
  byId('memory-undo').onclick = () => operation(async () => {
    try { snapshot = await store.undoLast(snapshot.token); render(); status('已撤销上一次记忆修改。'); byId('memory-add').focus(); }
    catch (error) { status(error.message, true); }
  });
  byId('memory-keep-editing').onclick = () => { afterDiscard = null; byId('memory-discard').hidden = true; text.focus(); };
  byId('memory-discard-edit').onclick = () => { const action = afterDiscard; clearEditor(); action?.(); };
  text.oninput = () => { confirm.checked = false; updateEditor(); };
  kind.onchange = () => { confirm.checked = false; updateEditor(); };
  confirm.onchange = updateEditor;
  form.onsubmit = event => {
    event.preventDefault();
    if (event.isComposing || !snapshot) return;
    operation(async () => { status('正在保存…');
    try { snapshot = await store.put(snapshot.token, { id: editingId, kind: kind.value, text: text.value, source: 'user', confirmed: confirm.checked }); routeDraft = null; clearEditor(); render(); status('已保存到当前项目，可撤销本次修改。'); byId('memory-add').focus(); }
    catch (error) { status(error.message, true); } });
  };
  store.subscribe(() => {
    if (busy || (dialog.open && !form.hidden)) { store.read().catch(() => {}); status('项目记忆在别处有变化。草稿已保留，请重新读取并核对。', true); }
    else { operation(load); }
  });
  window.addEventListener('storage', event => {
    if (event.key !== null && event.key !== 'design-canvas-project-memory-v1:' + encodeURIComponent(projectId)) return;
    if (dialog.open && !form.hidden) { status('项目记忆在别处有变化。草稿已保留，请重新读取并核对。', true); return; }
    load();
  });
  // Read-only access for an explicit local companion request. Never included in model snapshots.
  globalThis.mouseCompanionMemory = Object.freeze({ summary() {
    const entries = store.peek().document.entries;
    const name = document.querySelector('[data-project-name]')?.textContent || 'CUPPA';
    return name + ' · 项目记忆（本机）\n' + (entries.length ? entries.map(item => labels[item.kind] + ' [' + provenance[item.kind] + ']：' + item.text).join('\n') : '暂无。请在画布侧栏「项目记忆」中手动添加。');
  } });
  load();
})();

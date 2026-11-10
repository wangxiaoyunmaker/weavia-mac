/* Explicit, local-only project memory. No inference, card migration or network access. */
(function (root) {
  'use strict';
  const kinds = ['goal', 'constraint', 'question'];
  const statuses = { goal: 'user_stated', constraint: 'user_confirmed', question: 'open' };
  function createProjectMemoryStore(storage, project, options = {}) {
    if (typeof project !== 'string') throw Error('项目标识无效。');
    const key = 'design-canvas-project-memory-v1:' + encodeURIComponent(project);
    const now = options.now || (() => new Date().toISOString());
    const uuid = options.uuid || (() => root.crypto.randomUUID());
    let undo = null;
    const empty = () => ({ version: 1, projectId: project, revision: 0, entries: [] });
    function validate(value) {
      if (!value || value.version !== 1) throw Error('记忆版本暂不支持，原数据未修改。');
      if (value.projectId !== project) throw Error('记忆项目不匹配，原数据未修改。');
      if (!Number.isSafeInteger(value.revision) || value.revision < 0 || !Array.isArray(value.entries) || value.entries.length > 100) throw Error('记忆数据不完整，原数据未修改。');
      const ids = new Set();
      for (const item of value.entries) {
        if (!item || typeof item.id !== 'string' || !item.id || ids.has(item.id) || !kinds.includes(item.kind) || typeof item.text !== 'string' || !item.text.trim() || item.text.length > 1000 || item.source !== 'user' || item.status !== statuses[item.kind] || typeof item.createdAt !== 'string' || typeof item.updatedAt !== 'string') throw Error('记忆数据不完整，原数据未修改。');
        ids.add(item.id);
      }
      return value;
    }
    function read() {
      const token = storage.getItem(key);
      let document;
      try { document = token === null ? empty() : validate(JSON.parse(token)); }
      catch (error) { throw Error(error instanceof SyntaxError ? '记忆内容无法读取，原数据未修改。' : error.message); }
      return { document, token };
    }
    function current(expected) {
      const snapshot = read();
      if (snapshot.token !== expected) throw Error('项目记忆已在别处更新。请重新读取，再保存你的草稿。');
      return snapshot;
    }
    function write(before, next) {
      validate(next);
      const encoded = JSON.stringify(next);
      try { storage.setItem(key, encoded); }
      catch (_) { throw Error('无法保存项目记忆，请检查存储空间后重试。草稿仍保留。'); }
      if (storage.getItem(key) !== encoded) throw Error('未能确认保存结果，请重新读取后核对。草稿仍保留。');
      undo = { before: before.document, after: encoded };
      return { document: next, token: encoded };
    }
    function put(expected, input) {
      const before = current(expected);
      if (!input || !kinds.includes(input.kind) || typeof input.text !== 'string') throw Error('请选择有效的记忆类型。');
      const text = input.text.trim();
      if (!text || text.length > 1000) throw Error('请填写 1–1000 字的记忆。');
      if (input.source && input.source !== 'user') throw Error('AI 建议不能自动成为项目记忆，请由用户明确填写并保存。');
      if (input.kind === 'constraint' && input.confirmed !== true) throw Error('请明确确认这条条件后再保存。');
      const old = input.id ? before.document.entries.find(item => item.id === input.id) : null;
      if (input.id && !old) throw Error('这条记忆已不存在，请重新读取。');
      if (!old && before.document.entries.length >= 100) throw Error('当前项目已有 100 条记忆，请先整理或移除旧条目。');
      const time = now();
      const item = { ...(old || {}), id: old?.id || uuid(), kind: input.kind, text, source: 'user', status: statuses[input.kind], createdAt: old?.createdAt || time, updatedAt: time };
      const entries = old ? before.document.entries.map(value => value.id === old.id ? item : value) : [...before.document.entries, item];
      return write(before, { ...before.document, revision: before.document.revision + 1, entries });
    }
    function remove(expected, id) {
      const before = current(expected);
      if (!before.document.entries.some(item => item.id === id)) throw Error('这条记忆已不存在，请重新读取。');
      return write(before, { ...before.document, revision: before.document.revision + 1, entries: before.document.entries.filter(item => item.id !== id) });
    }
    function undoLast(expected) {
      const before = current(expected);
      if (!undo || undo.after !== before.token) throw Error('没有可安全撤销的修改，或记忆已有新变化。');
      const restore = { ...undo.before, revision: before.document.revision + 1 };
      const result = write(before, restore);
      undo = null;
      return result;
    }
    return Object.freeze({ read, put, remove, undoLast, canUndo: token => !!undo && undo.after === token,
      // Transaction adapter restores this private checkpoint if the durable commit aborts.
      checkpoint: () => undo ? JSON.parse(JSON.stringify(undo)) : null,
      restoreCheckpoint: value => { undo = value; }
    });
  }
  root.createProjectMemoryStore = createProjectMemoryStore;
})(globalThis);

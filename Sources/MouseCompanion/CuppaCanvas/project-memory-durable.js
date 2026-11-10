/* IndexedDB strict-durability commits: a successful UI save means the transaction completed.
 * localStorage is only a read-only migration source for this feature's own earlier key. */
(function (root) {
  'use strict';
  function createDurableProjectMemoryStore(project, options = {}) {
    const key = 'design-canvas-project-memory-v1:' + encodeURIComponent(project);
    let opening = null, queue = Promise.resolve(), raw = null, cache = null, loaded = false;
    const memoryStorage = { getItem: () => raw, setItem: (_key, value) => { raw = value; } };
    let engine = root.createProjectMemoryStore(memoryStorage, project, options);
    const listeners = new Set();
    const channel = typeof root.BroadcastChannel === 'function' ? new root.BroadcastChannel('design-project-memory-updates') : null;
    if (channel) channel.onmessage = event => { if (event.data?.project !== project) return; loaded = false; for (const listener of listeners) listener(); };
    function open() {
      if (opening) return opening;
      opening = new Promise((resolve, reject) => {
        let request, abandoned = false;
        try { request = (options.indexedDB || root.indexedDB).open('design-project-memory', 1); }
        catch (_) { reject(Error('当前环境无法打开本地记忆存储。请检查存储权限后重新读取。')); return; }
        request.onupgradeneeded = () => { request.result.createObjectStore('projects'); };
        request.onerror = () => reject(Error('无法打开本地记忆存储，原数据未修改。'));
        request.onblocked = () => { abandoned = true; reject(Error('记忆存储正在被其他页面使用，请关闭其他项目页面后重试。')); };
        request.onsuccess = () => {
          const db = request.result;
          if (abandoned) { db.close(); return; }
          db.onversionchange = () => { db.close(); opening = null; };
          resolve(db);
        };
      }).catch(error => { opening = null; throw error; });
      return opening;
    }
    async function transact(method, expected, input) {
      const db = await open();
      return new Promise((resolve, reject) => {
        let tx, result, failure;
        const checkpoint = engine.checkpoint();
        try { tx = db.transaction('projects', 'readwrite', { durability: 'strict' }); }
        catch (_) { reject(Error('当前环境无法安全提交记忆，请重新打开项目后重试。')); return; }
        const objects = tx.objectStore('projects');
        const request = objects.get(project);
        request.onsuccess = () => {
          try {
            raw = request.result === undefined ? null : request.result;
            let migrated = false;
            if (raw === null) {
              try { const legacy = options.legacyStorage || root.localStorage; raw = legacy.getItem(key); }
              catch (_) { throw Error('当前环境无法读取本地记忆。原数据未修改，请检查存储权限后重新读取。'); }
              migrated = raw !== null;
            }
            const snapshot = engine.read(); // Validates legacy/corrupt/unknown content before any write.
            if (method === 'read') result = snapshot;
            else if (method === 'put') result = engine.put(expected, input);
            else if (method === 'remove') result = engine.remove(expected, input);
            else if (method === 'undoLast') result = engine.undoLast(expected);
            if (method !== 'read' || migrated) objects.put(result.token, project);
          } catch (error) { failure = error; tx.abort(); }
        };
        tx.oncomplete = () => { cache = result; loaded = true; if (method !== 'read') channel?.postMessage({ project }); resolve(result); };
        tx.onabort = () => {
          // Keep the undo for the last successful commit, never the aborted candidate.
          loaded = false;
          engine.restoreCheckpoint(checkpoint);
          reject(failure || Error('记忆未保存，草稿仍保留。请检查存储空间或权限后重试。'));
        };
        tx.onerror = () => {}; // onabort handles transaction errors once.
      });
    }
    function run(method, expected, input) {
      const pending = queue.then(() => transact(method, expected, input));
      queue = pending.catch(() => {});
      return pending;
    }
    return Object.freeze({
      read: () => run('read'),
      put: (expected, input) => run('put', expected, input),
      remove: (expected, id) => run('remove', expected, id),
      undoLast: expected => run('undoLast', expected),
      canUndo: token => engine.canUndo(token),
      subscribe(listener) { listeners.add(listener); return () => listeners.delete(listener); },
      dispose() { channel?.close(); opening?.then(db => db.close()).catch(() => {}); },
      peek() { if (!loaded) throw Error('项目记忆尚未加载，请先在画布中打开项目记忆。'); return cache; }
    });
  }
  root.createDurableProjectMemoryStore = createDurableProjectMemoryStore;
})(globalThis);

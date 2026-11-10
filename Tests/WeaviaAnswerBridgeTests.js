const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const messages = [], presentations = [];
const env = {URL, URLSearchParams, console, Date, Map, Set, JSON, setTimeout, clearTimeout,
 location: {search: '?project=Reply%20fixture'},
 webkit: {messageHandlers: {mouseCompanion: {postMessage: message => messages.push(message)}}},
 document: {getElementById: () => null},
 panel: (...args) => presentations.push(['panel', ...args]),
 notify: (...args) => presentations.push(['notify', ...args]),
 esc: value => value,
};
vm.createContext(env);
vm.runInContext(fs.readFileSync(require.resolve('../Sources/MouseCompanion/CuppaCanvas/mac-native-bridge.js'), 'utf8'), env);
const bridge = env.mouseCompanionMac;
function begin() { bridge.openAgent('Analyze synthetic reference', []); return messages.at(-1).requestId; }
function event(id, status, extra = {}) { return bridge.receiveAgentResult({requestId: id, projectId: 'Reply fixture', status, text: '**Synthetic answer**\n\n---\n\n' + 'Long answer. '.repeat(1000), ...extra}); }
assert.equal(bridge.receiveAgentResult(null), false);
assert.equal(event('', 'streaming'), false, 'no active request must reject empty callback IDs');
let id = begin();
assert.equal(event('wrong', 'streaming'), false);
assert.equal(event(id, 'streaming', {projectId: 'Other project'}), false);
assert.equal(event(id, 'unknown'), false);
for (let i=0; i<5; i++) assert.equal(event(id, 'streaming'), true);
assert.deepEqual(presentations, [], 'native answer must not also open a canvas dialog');
assert.equal(event(id, 'completed'), true);
assert.equal(event(id, 'streaming'), false, 'late stream cannot reopen a completed answer');
assert.equal(event(id, 'completed'), false, 'duplicate completion is ignored');
for (const terminal of ['success', 'error', 'failed', 'cancelled']) {
 id = begin(); assert.equal(event(id, 'streaming'), true); assert.equal(event(id, terminal), true);
 assert.equal(event(id, 'streaming'), false, terminal + ' ends the active request');
}
const old = begin(); id = begin();
assert.equal(event(old, 'completed'), false, 'older request cannot replace or complete newer answer');
assert.equal(event(id, 'streaming'), true);
assert.equal(event(id, 'completed'), true);
id = begin();
bridge.ack(id, {ok:false, message:'Synthetic rejected request'});
assert.equal(event(id, 'streaming'), false, 'a rejected start cannot accept late callbacks');
assert.equal(presentations.length, 1, 'only a rejected native operation may notify');
assert.equal(presentations[0][0], 'notify');
console.log('PASS: single native answer ownership, long Markdown, repeated streams, terminal cleanup, stale/project isolation, rejected starts');

const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.resolve(__dirname, '../Sources/MouseCompanion/CuppaCanvas');
const context = vm.createContext({window:{addEventListener(){}}, Map, state:{cards:[{id:'a',title:'A'},{id:'b',title:'B'}]}, activeEdge:null, zoom:1, esc:s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;')});
vm.runInContext(fs.readFileSync(path.join(root,'card-relations.js'),'utf8'), context);
context.CardRelations=context.window.CardRelations;
vm.runInContext(fs.readFileSync(path.join(root,'card-relations-ui.js'),'utf8'), context);
const edges = [{id:'legacy',from:'a',to:'b'}, ...['related','similar','different','complementary','conflicting','custom'].map(kind=>({id:kind,from:'a',to:'b',relation:{version:1,source:'user',kind,customLabel:kind==='custom'?'参考':'',evidence:'Synthetic evidence',status:'confirmed',history:[]}})), {id:'future',from:'a',to:'b',relation:{version:999}}];
const original = JSON.stringify(edges);
for (const zoom of [1,.649,.65,.2,.5,1,.649,1]) {
 context.zoom=zoom;
 for(const edge of edges) {
  const html=context.relationEdgeMarkup(edge,{x:0,y:0},{x:200,y:100});
  assert.equal(html.includes('relation-edge-compact'),zoom<.65);
  for(const token of ['edge-hit','edge-visible','relation-edge-label','tabindex="0"','role="button"','aria-label=','<title>']) assert.ok(html.includes(token),token);
  if(edge.id==='custom')assert.ok(html.includes('relation-arrow'));
  if(edge.id==='similar')assert.ok(html.includes('relation-parallel'));
 }
}
assert.equal(JSON.stringify(edges),original,'zoom rendering must not mutate records');
assert.match(context.CardRelations.view(edges[0]).label,/普通连线/,'details retain legacy label');
console.log('PASS: relation zoom threshold, all types, accessibility, arrows, parallel strokes, repeated zoom, immutable data');

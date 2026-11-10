/* Isolated bridge tests: synthetic pixels only, never reads live user storage. */
const assert=require('node:assert/strict');
const fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync(require.resolve('../Sources/MouseCompanion/CuppaCanvas/mac-native-bridge.js'),'utf8');
const {mergeMaterials,imageURL,validateSnapshot}=require('../Sources/MouseCompanion/CuppaCanvas/mac-native-bridge.js');
const asset='weavia-asset://material/12345678-1234-1234-1234-123456789abc.png?project=Project%20A';
const pixels='data:image/png;base64,'+'A'.repeat(4_260_000);
const empty=()=>({cards:[],mode:'personal',drafts:{personal:{text:'keep this draft',sources:[],refs:[]},agent:{text:'agent draft',sources:[],refs:[]}}});
const material={id:'12345678-1234-1234-1234-123456789abc',saved:true,title:'Original',text:'Source excerpt',sourceLabel:'Original source',sourceURL:'https://example.com/source',imageURL:asset,imageDataURL:pixels};
const imported=mergeMaterials(empty(),[material]);
assert.equal(imported.cards[0].image,asset);assert.equal(imported.cards[0].preview,asset);
assert.ok(JSON.stringify(imported).length<2000,'pixels must not enter persisted native cards');
assert.equal(mergeMaterials(empty(),[{...material,imageURL:undefined}]).cards[0].image,'','legacy inline pixels must not enter new native cards');
for(const unsafe of [asset.replace('material/','other/'),asset.replace('material/','material:443/'),asset.replace('material/','user@material/'),asset+'#fragment',asset+'&other=1',asset+'&project=Other',asset.replace('.png','.svg'),asset.replace('12345678-1234-1234-1234-123456789abc','../private'),asset.replace('?project=Project%20A','?project='),'file:///private/image.png','javascript:alert(1)'])assert.equal(imageURL(unsafe),'',unsafe);
assert.equal(imageURL(asset),asset);assert.equal(imageURL('data:image/svg+xml;base64,AAAA'),'');
const legacy=structuredClone(imported);Object.assign(legacy.cards[0],{image:pixels,preview:'https://example.com/user-preview.png',title:'User title',text:'User text',x:83,userNote:'User note'});
const migrated=mergeMaterials(legacy,[material]);
assert.equal(migrated.cards[0].image,asset);assert.equal(migrated.cards[0].preview,'https://example.com/user-preview.png');assert.equal(migrated.cards[0].title,'User title');assert.equal(migrated.cards[0].text,'User text');assert.equal(migrated.cards[0].x,83);assert.equal(migrated.cards[0].userNote,'User note');assert.deepEqual(migrated.cards[0].provenance,legacy.cards[0].provenance);assert.equal(migrated.drafts.personal.text,'keep this draft');
assert.deepEqual(mergeMaterials(migrated,[material]),migrated);migrated.cards=[];assert.equal(mergeMaterials(migrated,[material]).cards.length,0);
assert.throws(()=>validateSnapshot({...empty(),_companionPersistence:{version:2,revision:1}}),/版本/);
function harness(initial=empty(),seed=[]){
 const storage=new Map(seed),messages=[],statusNodes=new Map();let renders=0,updates=0;
 const noop=()=>{};const document={body:{append:el=>statusNodes.set(el.id,el)},querySelector:()=>null,querySelectorAll:()=>[],addEventListener:noop,getElementById:id=>statusNodes.get(id)||null,createElement:()=>({style:{},setAttribute(k,v){this[k]=v;}})};
 const env={URL,URLSearchParams,console,Date,Map,Set,JSON,crypto:require('node:crypto').webcrypto,setTimeout,clearTimeout,setInterval:noop,location:{search:'?project=Project%20A'},localStorage:{getItem:k=>storage.get(k)??null,setItem:()=>{const error=Error('Synthetic quota limit');error.name='QuotaExceededError';throw error;},removeItem:k=>storage.delete(k)},webkit:{messageHandlers:{mouseCompanion:{postMessage:m=>messages.push(m)}}},document,addEventListener:noop,state:initial,canvasStorageKey:'design-canvas-v1:Project A',canvasPersistedToken:null,cuppaBootstrap:{projects:[]},selected:null,marqueeIds:new Set(),prepareResource:noop,prepareCardTags:noop,prepareClaim:noop,renderCards:()=>renders++,renderSide:noop,sync:noop,updateView:noop,notify:noop,persistCanvasSnapshot:()=>{throw Error('Legacy quota-gated writer must not run');},selectionTaskPanel:noop,launchAiConversation:noop,submitSearch:noop,loadResourceFrame:noop,activeAiProvider:()=>false,cuppaContextCapture:{configure:noop},cuppaTrayInbox:{inspect:()=>({page:'page'}),sync:noop},cuppaWorkModeV1:{sync:noop},CuppaRelationStore:{},weaviaProjectDesktop:{update:(projects,id,materials)=>{updates++;assert.equal(id,'Project A');assert.equal(projects[0].id,id);assert.ok(Array.isArray(materials));}}};
 env.window=env;vm.createContext(env);vm.runInContext(source,env);env.mouseCompanionMac.install();
 return {env,messages,storage,statusNodes,renders:()=>renders,updates:()=>updates};
}
const snapshot={version:1,projectId:'Project A',projects:[{id:'Project A',name:'Project A'}],canvasSnapshot:empty(),materials:[material]};
const h=harness();assert.equal(h.env.mouseCompanionMac.receiveSnapshot(snapshot).ok,true);assert.equal(h.renders(),1);assert.equal(h.updates(),1);assert.equal(h.env.state.cards.length,1);assert.equal(h.env.state.drafts.agent.text,'agent draft');
const save=h.messages.find(m=>m.action==='saveCanvas');assert.ok(save,'quota must not prevent native save');assert.ok(JSON.stringify(save.snapshot).length<2000);assert.equal(h.statusNodes.get('mac-save-status')['data-status'],'saving');
const changed=JSON.parse(JSON.stringify(h.env.state));changed.cards[0].title='Edited while saving';const token=h.env.persistCanvasSnapshot(changed);h.env.state=changed;assert.equal(typeof token,'string');const newer=h.messages.at(-1);assert.equal(newer.action,'saveCanvas');
h.env.mouseCompanionMac.ack(save.requestId,{ok:true});assert.equal(h.statusNodes.get('mac-save-status')['data-status'],'saving','older ack cannot mark newer draft saved');h.env.mouseCompanionMac.ack(newer.requestId,{ok:false,message:'Native disk unavailable'});assert.equal(h.statusNodes.get('mac-save-status')['data-status'],'failed');assert.match(h.statusNodes.get('mac-save-status').textContent,/当前窗口/);assert.equal(h.env.mouseCompanionMac.boot('Project A').snapshot.cards[0].title,'Edited while saving','failed quota-backed draft remains in memory');
h.env.persistCanvasSnapshot(changed);h.env.mouseCompanionMac.ack(h.messages.at(-1).requestId,{ok:true});assert.equal(h.statusNodes.get('mac-save-status')['data-status'],'saved');
const authoritative=harness({...empty(),cards:[{id:'stale-cache'}]});assert.equal(authoritative.env.mouseCompanionMac.receiveSnapshot(snapshot).ok,true);assert.equal(authoritative.env.state.cards.some(c=>c.id==='stale-cache'),false,'native disk snapshot replaces ordinary stale cache');
const recovery={...empty(),cards:[{id:'pending-edit'}]};const pending=harness(recovery,[['cuppa-mac-pending:Project A',JSON.stringify(recovery)]]);assert.equal(pending.env.mouseCompanionMac.receiveSnapshot(snapshot).ok,true);assert.ok(pending.env.state.cards.some(c=>c.id==='pending-edit'),'native snapshot does not discard pending draft');
const corrupt=harness();assert.equal(corrupt.env.mouseCompanionMac.receiveSnapshot({...snapshot,canvasSnapshot:{...empty(),_companionPersistence:{version:9,revision:1}}}).ok,false);assert.equal(corrupt.messages.some(m=>m.action==='saveCanvas'),false);assert.throws(()=>corrupt.env.persistCanvasSnapshot(empty()),/版本/);
const invalid=harness(empty(),[['cuppa-mac-pending:Project A','not json']]);assert.throws(()=>invalid.env.mouseCompanionMac.boot('Project A'));assert.equal(invalid.storage.get('cuppa-mac-pending:Project A'),'not json');
console.log('WeaviaLargeImageBridgeTests: synthetic 4.26MB pixels, quota, strict asset URLs, migration, provenance, pending ack/recovery, native authority and schema protection passed');

(async()=>{
 const q=harness();q.env.mouseCompanionMac.receiveSnapshot(snapshot);q.env.mouseCompanionMac.ack(q.messages.at(-1).requestId,{ok:true});
 const edge={id:'quota-edge',from:'a',to:'b'};let completed=false;
 const relation=q.env.CuppaRelationStore.commit('Project A',q.env.state,q.env.canvasPersistedToken,null,edge,0).then(value=>{completed=true;return value;});
 await new Promise(resolve=>setImmediate(resolve));assert.equal(completed,false);assert.equal(q.env.state.connections,undefined);
 q.env.mouseCompanionMac.ack(q.messages.at(-1).requestId,{ok:true});await relation;assert.equal(q.env.state.connections[0].id,'quota-edge');
 vm.runInContext(fs.readFileSync(require.resolve('../Sources/MouseCompanion/CuppaCanvas/project-memory-store.js'),'utf8'),q.env);
 q.env.createDurableProjectMemoryStore=()=>({read:async()=>({document:{version:1,projectId:'Project A',revision:0,entries:[]},token:null}),dispose:()=>{}});
 const memory=q.env.mouseCompanionMac.createMemoryStore('Project A'),current=await memory.read();
 const put=memory.put(current.token,{kind:'goal',text:'Quota-safe native memory'});await new Promise(resolve=>setImmediate(resolve));assert.equal(q.env.state.macProjectMemory,undefined);q.env.mouseCompanionMac.ack(q.messages.at(-1).requestId,{ok:true});await put;assert.equal(q.env.state.macProjectMemory.entries.length,1);
 const failed=q.env.CuppaRelationStore.commit('Project A',q.env.state,q.env.canvasPersistedToken,edge,null,0);await new Promise(resolve=>setImmediate(resolve));q.env.mouseCompanionMac.ack(q.messages.at(-1).requestId,{ok:false,message:'Synthetic native failure'});await assert.rejects(failed,/Synthetic native failure/);assert.equal(q.env.state.connections.length,1);assert.equal(q.env.mouseCompanionMac.boot('Project A').snapshot.connections.length,0,'failed transaction candidate remains recoverable under quota');assert.match(q.statusNodes.get('mac-storage-warning').textContent,/请勿关闭/);
 console.log('WeaviaLargeImageBridgeTests: memory and relation native-ack commits remain durable under cache quota; failed transaction preserves candidate');
})().catch(error=>{console.error(error);process.exitCode=1;});

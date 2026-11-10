const assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const messages=[],nodes=new Map();
function element(){return {dataset:{},handlers:{},children:[],open:false,setAttribute(){},addEventListener(type,fn){this.handlers[type]=fn},append(child){this.children.push(child);if(child.id)nodes.set(child.id,child)},querySelector(){return element()},showModal(){this.open=true},close(){this.open=false},focus(){}}}
const menu=element();menu.hidden=false;nodes.set('selection-actions',menu);
const env={URL,URLSearchParams,Date,Map,Set,JSON,console,location:{search:'?project=fixture'},document:{getElementById:id=>nodes.get(id)||null,createElement:element,body:element(),addEventListener(){}},webkit:{messageHandlers:{mouseCompanion:{postMessage:m=>messages.push(m)}}},state:{drafts:{personal:{text:'Keep personal draft'},agent:{text:'Keep native-context draft'}}}};
vm.createContext(env);
for(const file of ['mac-native-bridge.js','card-details.js'])vm.runInContext(fs.readFileSync(require.resolve('../Sources/MouseCompanion/CuppaCanvas/'+file),'utf8'),env);
const originalDrafts=JSON.stringify(env.state.drafts);
const source={id:'source',type:'source',title:'Synthetic source',text:'Full content',tags:[]};
env.CuppaCardDetails.open(source);
assert.equal(messages.at(-1).action,'selectionEnded','explicit web detail must end native selection first');
assert.equal(nodes.get('card-detail-dialog').open,true);
assert.equal(menu.hidden,true);
nodes.get('card-detail-dialog').close();
messages.length=0;menu.hidden=false;
const card=element(),footer=element();card.querySelector=()=>footer;
env.CuppaCardDetails.bind(card,source);
// Enter/Space activation generates click with detail=0 and no pointerdown.
footer.children[0].handlers.click({detail:0,preventDefault(){},stopImmediatePropagation(){}});
assert.equal(messages[0].action,'selectionEnded','keyboard-triggered detail click ends native input presentation');
assert.equal(nodes.get('card-detail-dialog').open,true);
nodes.get('card-detail-dialog').close();messages.length=0;menu.hidden=false;
env.CuppaCardDetails.open({...source,nativeMaterialId:'native-fixture'});
assert.deepEqual(messages.map(m=>m.action),['selectionEnded','trayCommand'],'native detail dismisses selection before opening original material');
assert.equal(messages[1].command,'open');assert.deepEqual(Array.from(messages[1].ids),['native-fixture']);
assert.equal(JSON.stringify(env.state.drafts),originalDrafts,'all detail entry points preserve input drafts');
console.log('PASS: explicit web/native detail and keyboard click end selection before presentation; drafts preserved');

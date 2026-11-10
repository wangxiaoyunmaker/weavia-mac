const assert=require('node:assert/strict');
const vm=require('node:vm'),fs=require('node:fs');
const messages=[],storage=new Map();let poll,workRequest=null,trayRequest=null,traySnapshot;
const noop=()=>{},node={append:noop};
const env={URL,URLSearchParams,console,Date,Map,Set,JSON,setTimeout,clearTimeout,crypto:require('node:crypto').webcrypto,CuppaRelationStore:{},setInterval:f=>{poll=f},location:{search:'?project=Project%20A'},localStorage:{getItem:k=>storage.get(k)??null,setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)},webkit:{messageHandlers:{mouseCompanion:{postMessage:m=>messages.push(m)}}},document:{querySelector:()=>node,querySelectorAll:()=>[],addEventListener:noop,createElement:()=>({setAttribute:noop}),getElementById:()=>null},addEventListener:noop,state:{cards:[],mode:'personal',drafts:{personal:{text:'',sources:[],refs:[]},agent:{text:'',sources:[],refs:[]}}},canvasStorageKey:'design-canvas-v1:Project A',canvasPersistedToken:null,cuppaBootstrap:{projects:[]},selected:null,marqueeIds:new Set(),prepareResource:noop,prepareCardTags:noop,prepareClaim:noop,renderCards:noop,renderSide:noop,sync:noop,updateView:noop,notify:noop,persistCanvasSnapshot:()=>'',selectionTaskPanel:noop,launchAiConversation:noop,submitSearch:noop,loadResourceFrame:noop,activeAiProvider:()=>false,cuppaContextCapture:{configure:noop,peek:()=>null},cuppaInspirationV1:{take:()=>null},cuppaWorkModeV1:{peek:()=>workRequest,sync:noop,ack:noop},cuppaTrayInbox:{inspect:()=>({page:'page',request:trayRequest}),sync:s=>{traySnapshot=s},ack:noop}};
const handlers={},timers=[];
const menu={hidden:true,style:{},offsetWidth:208,offsetHeight:160};
const workspace={clientWidth:1000,clientHeight:700,getBoundingClientRect:()=>({left:80,top:40})};
const buttons=Object.fromEntries(['selection-count','selection-details','selection-custom-toggle','selection-analyze','selection-similar','selection-close'].map(id=>[id,{}]));
let geometry=[{id:'a',left:200,top:150,right:400,bottom:450,width:200,height:300}];
let editing=false,dialog=false;
env.document.getElementById=id=>id==='selection-actions'?menu:id==='workspace'?workspace:buttons[id]||null;
env.document.querySelector=selector=>selector==='dialog[open]'?(dialog?{}:null):null;
env.document.querySelectorAll=selector=>selector==='.card'?geometry.map(r=>({dataset:{id:r.id},getBoundingClientRect:()=>r})):[];
env.document.activeElement={matches:()=>editing};env.document.hidden=false;
env.document.addEventListener=(type,fn)=>(handlers[type]??=[]).push(fn);
env.addEventListener=(type,fn)=>(handlers[type]??=[]).push(fn);
env.setTimeout=fn=>{timers.push(fn);return timers.length};
env.innerWidth=1100;env.innerHeight=800;env.location.hash='#cuppa';env.tool='select';
env.window=env;vm.createContext(env);vm.runInContext(fs.readFileSync(require.resolve('../Sources/MouseCompanion/CuppaCanvas/mac-native-bridge.js'),'utf8'),env);

const bridge=env.mouseCompanionMac;bridge.install();
bridge.receiveSnapshot({version:1,projectId:'Project A',materials:[],mode:'cocreate'});
env.state.cards=[{id:'a',title:'A'},{id:'b',title:'B'}];env.selected='a';
function flush(){while(timers.length)timers.shift()();}
function emit(type,e={}){for(const fn of handlers[type]||[])fn(e);}
const card={id:'a',closest:s=>s==='.card'?{}:null};
const blank={id:'workspace',closest:()=>null};
function down(target=card,pointerType='mouse'){emit('pointerdown',{isTrusted:true,button:0,pointerId:1,pointerType,clientX:220,clientY:170,target});}
function up(x=220,y=170){emit('pointerup',{isTrusted:true,pointerId:1,clientX:x,clientY:y});}
const completed=()=>messages.filter(m=>m.action==='selectionCompleted');
poll();poll();assert.equal(completed().length,0,'polling cannot open prompt');
down();up();flush();assert.equal(completed().length,1,'completed card click opens once');
let selection=completed().at(-1);assert.equal(selection.cards[0].id,'a');assert.equal(selection.bounds.width,200);
assert.equal(bridge.alignSelection({projectId:'wrong',selectionSession:selection.selectionSession,visible:true}),false);
assert.equal(bridge.alignSelection({projectId:'Project A',selectionSession:'old',visible:true}),false);
assert.equal(bridge.alignSelection({projectId:'Project A',selectionSession:selection.selectionSession,visible:true,x:440,y:400}),true);
assert.equal(buttons['selection-count'].textContent,'已选 1 张卡片');assert.equal(menu.hidden,false);assert.equal(menu.style.left,'382px');assert.equal(menu.style.top,'188px');
geometry[0]={id:'a',left:240,top:130,right:540,bottom:580,width:300,height:450};poll();
assert.equal(messages.at(-1).action,'selectionGeometry');assert.equal(completed().length,1,'zoom geometry never opens/restarts input');
down();up(300,250);flush();assert.equal(completed().length,1,'drag is not selection completion');
const toolbar={id:'hand-tool',closest:s=>s==='button'?{}:null};
const menuButton={id:'selection-custom-toggle',closest:s=>s==='#selection-actions'||s==='button'?{}:null};
down();up();down(toolbar);flush();assert.equal(completed().length,1,'toolbar interaction invalidates pending automatic focus');
down();up();down(menuButton);flush();assert.equal(completed().length,1,'menu interaction invalidates pending automatic focus');
down();up();emit('keydown',{isTrusted:true,key:'h'});flush();assert.equal(completed().length,1,'tool keyboard shortcut invalidates pending completion');
env.tool='hand';down();up();flush();assert.equal(completed().length,1,'Hand click cannot activate old selected card');env.tool='select';
down();up();env.tool='pen';flush();assert.equal(completed().length,1,'tool change during delay cannot open prompt');env.tool='select';
env.canvasAction='connection';down();up();flush();assert.equal(completed().length,1,'connection tool cannot auto-open prompt');env.canvasAction=null;
env.picking=true;down();up();flush();assert.equal(completed().length,1,'reference picking cannot auto-open prompt');env.picking=false;
down();emit('pointermove',{isTrusted:true,pointerId:1,clientX:222,clientY:170});up(222,170);flush();assert.equal(completed().length,1,'two-pixel mouse drag matches real card drag threshold');
down();emit('pointermove',{isTrusted:true,pointerId:1,clientX:221,clientY:170});up();flush();assert.equal(completed().length,1,'one-pixel mouse drag returning home remains a drag');
down(card,'touch');emit('pointermove',{isTrusted:true,pointerId:1,clientX:223,clientY:170});up();flush();assert.equal(completed().length,1,'three-pixel touch drag matches real card drag threshold');

down();emit('pointermove',{isTrusted:true,pointerId:1,clientX:500,clientY:500});emit('pointermove',{isTrusted:true,pointerId:1,clientX:220,clientY:170});up();flush();assert.equal(completed().length,1,'drag out and back must not become a click');
down();emit('pointermove',{isTrusted:true,pointerId:1,clientX:500,clientY:500});emit('pointercancel');up();flush();assert.equal(completed().length,1,'cancelled moved gesture cannot complete');
down();up();emit('pointercancel');flush();assert.equal(completed().length,1,'cancel invalidates delayed selection');
down();up();emit('dblclick',{target:card});flush();assert.equal(completed().length,1,'double-click detail cancels automatic focus');
editing=true;down();up();flush();assert.equal(completed().length,1,'editing never opens input');editing=false;
bridge.receiveSnapshot({version:1,projectId:'Project A',materials:[],mode:'focus'});down();up();flush();assert.equal(completed().length,1,'Focus never participates');
bridge.receiveSnapshot({version:1,projectId:'Project A',materials:[],mode:'cocreate'});
env.marqueeIds=new Set(['a','b']);geometry.push({id:'b',left:600,top:50,right:1200,bottom:900,width:600,height:850});
down(blank);emit('pointermove',{isTrusted:true,pointerId:1,clientX:700,clientY:700});up(700,700);flush();selection=completed().at(-1);assert.equal(selection.cards.length,2);assert.equal(selection.bounds.x,240);assert.equal(selection.bounds.y,50);assert.equal(selection.bounds.width,860);assert.equal(selection.bounds.height,750,'union clipped to visible viewport');
bridge.alignSelection({projectId:'Project A',selectionSession:selection.selectionSession,visible:true,x:440,y:400});assert.equal(buttons['selection-count'].textContent,'已选 2 张卡片');
let detailOpened=null;env.CuppaCardDetails={open:card=>{detailOpened=card.id}};buttons['selection-details'].onclick();assert.equal(detailOpened,null,'multi selection cannot open arbitrary detail');
const priorClick=completed().length;env.marqueeIds.clear();env.selected='a';down();up();flush();assert.equal(completed().length,priorClick+1,'fresh click resets sticky movement');bridge.alignSelection({projectId:'Project A',selectionSession:completed().at(-1).selectionSession,visible:true,x:440,y:400});assert.equal(buttons['selection-count'].textContent,'已选 1 张卡片','multi to single count refreshes');env.marqueeIds=new Set(['a','b']);
const before=completed().length;buttons['selection-custom-toggle'].onclick();assert.equal(completed().length,before+1);assert.equal(completed().at(-1).explicit,true,'custom opens native prompt');
buttons['selection-analyze'].onclick();assert.equal(messages.at(-1).action,'openAgent');assert.equal(messages.at(-1).cards.length,2);
env.marqueeIds.clear();env.selected='a';buttons['selection-details'].onclick();assert.equal(detailOpened,'a','menu opens selected card detail');buttons['selection-similar'].onclick();assert.equal(messages.at(-1).cards.length,1,'single-card actions use selected card');
down();up();env.location.hash='#projects';flush();assert.equal(completed().length,before+1,'navigation rejects delayed selection');
console.log('PASS: completed selection only, drag/cancel/edit/Focus/navigation guards, custom native input, single/multiple actions, zoom/clipped union, anchored options, stale IDs, geometry without reopen');
// Real toolbar modes use the same completion contract, not the click listener.
env.location.hash='#cuppa';bridge.receiveSnapshot({version:1,projectId:'Project A',materials:[],mode:'cocreate'});
env.marqueeIds=new Set(['a','b']);env.selected=null;
for(const kind of ['rectangle','lasso']){
 env.tool=kind;const start=completed().length;
 bridge.beginSelectionGesture();down(blank);up(700,700);flush();assert.equal(completed().length,start,'tool gestures must not use deferred single-click completion');
 assert.equal(bridge.completeSelectionGesture(kind),true);assert.equal(completed().length,start+1);assert.deepEqual([...completed().at(-1).cards.map(c=>c.id)],['a','b']);
 const session=completed().at(-1).selectionSession;bridge.alignSelection({projectId:'Project A',selectionSession:session,visible:true,x:440,y:400});poll();assert.equal(menu.hidden,false,'tool selection retains anchored actions after polling');
 env.tool=kind==='rectangle'?'lasso':'rectangle';poll();assert.equal(menu.hidden,true,'switching selection tools dismisses the old companion session');env.tool=kind;
 bridge.beginSelectionGesture();assert.equal(menu.hidden,true,'new gesture dismisses obsolete actions');assert.equal(completed().length,start+1,'gesture begin/cancel never opens an input');
}
env.tool='select';let start=completed().length;assert.equal(bridge.completeSelectionGesture('select'),true);assert.equal(completed().length,start+1,'legacy marquee has explicit completion');
env.tool='pen';assert.equal(bridge.completeSelectionGesture('pen'),false);env.tool='hand';assert.equal(bridge.completeSelectionGesture('rectangle'),false);
env.tool='rectangle';env.marqueeIds.clear();env.selected=null;assert.equal(bridge.completeSelectionGesture('rectangle'),false,'empty selection never opens input');
env.marqueeIds=new Set(['a','b']);bridge.receiveSnapshot({version:1,projectId:'Project A',materials:[],mode:'focus'});assert.equal(bridge.completeSelectionGesture('rectangle'),false,'Focus never opens input');
console.log('PASS: actual rectangle/lasso completion contract, two-card references, no click duplicate, begin/cancel, retained anchored menu, stale tool, empty and Focus guards');

// Over-limit selections stay explicit instead of silently taking the first eight.
env.tool='rectangle';bridge.receiveSnapshot({version:1,projectId:'Project A',materials:[],mode:'cocreate'});
env.state.cards=Array.from({length:9},(_,i)=>({id:i===0?'a':'many-'+i,title:'Synthetic '+i}));env.marqueeIds=new Set(env.state.cards.map(c=>c.id));
start=completed().length;const prompts=messages.filter(m=>m.action==='openAgent').length;
assert.equal(bridge.completeSelectionGesture('rectangle'),false);assert.equal(completed().length,start);
assert.equal(bridge.openAgent('Synthetic',env.state.cards),false);assert.equal(messages.filter(m=>m.action==='openAgent').length,prompts);
console.log('PASS: nine-card selection and explicit prompts are rejected without partial reference submission');

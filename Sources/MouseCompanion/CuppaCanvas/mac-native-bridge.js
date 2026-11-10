/* Mac adapter for the original CUPPA canvas. No network, model credentials or shell access. */
(function(root){
 'use strict';
 const clone=value=>JSON.parse(JSON.stringify(value));
 const string=value=>typeof value==='string'?value:'';
 function webURL(value){try{const u=new URL(value);return ['https:','http:'].includes(u.protocol)?u.href:'';}catch{return '';}}
 function nativeImageURL(value){
  if(typeof value!=='string'||!/^weavia-asset:\/\/material\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.png\?project=[^#]+$/i.test(value))return '';
  try{const u=new URL(value);return u.protocol==='weavia-asset:'&&u.host==='material'&&!u.username&&!u.password&&!u.hash&&[...u.searchParams.keys()].length===1&&u.searchParams.get('project')?u.href:'';}catch{return '';}
 }
 function inlineImageURL(value){return /^data:image\/(png|jpeg|jpg|gif|webp);base64,[A-Za-z0-9+/=\r\n]+$/.test(string(value))?value:'';}
 function imageURL(value){return nativeImageURL(value)||inlineImageURL(value);}
 function validateSnapshot(value){
  if(!value||!Array.isArray(value.cards)||!value.drafts?.personal||!value.drafts?.agent)throw Error('本地画布格式无效，未覆盖原数据。');
  const m=value._companionPersistence;if(m!==undefined&&(m.version!==1||!Number.isSafeInteger(m.revision)||m.revision<1||(m.captureIds!==undefined&&(!Array.isArray(m.captureIds)||m.captureIds.some(id=>typeof id!=='string')))))throw Error('画布存储版本暂不支持，原数据未修改。');
  return value;
 }
 function mergeMaterials(snapshot,materials){
  const next=clone(snapshot),seen=new Set(next.macNativeMaterialIds||[]);
  for(const m of materials){
   if(!m||m.saved===false||typeof m.id!=='string'||!m.id)continue;
   const existing=next.cards.find(c=>c.nativeMaterialId===m.id),id='native:'+m.id;
   if(existing){
    const asset=nativeImageURL(m.imageURL);
    if(asset)for(const field of ['image','preview'])if(inlineImageURL(existing[field])||nativeImageURL(existing[field]))existing[field]=asset;
    seen.add(m.id);continue;
   } // Preserve edits, and never resurrect a deliberate deletion.
   if(seen.has(m.id))continue;
   const n=next.cards.length,url=webURL(m.sourceURL||m.url),image=nativeImageURL(m.imageURL);
   next.cards.push({id,nativeMaterialId:m.id,type:'source',title:string(m.title)||'收集的素材',text:string(m.text),url,image,preview:image,tags:Array.isArray(m.tags)?m.tags.filter(t=>typeof t==='string'):[],userNote:string(m.note),addedBy:'personal',creator:{kind:'personal'},confirmationStatus:'unconfirmed',x:310+(n%3)*360,y:180+Math.floor(n/3)*300,time:string(m.capturedAt).slice(11,16),provenance:{sourceLabel:string(m.sourceLabel)||'Mac 鼠标伙伴',url,capturedAt:string(m.capturedAt),excerpt:string(m.text),nativeMaterialId:m.id}});
   seen.add(m.id);
  }
  next.macNativeMaterialIds=[...seen];next.resourceSemanticVersion=1;next.aiExcerptExamplesAdded=true;return next;
 }
 if(typeof module!=='undefined'&&module.exports)module.exports={mergeMaterials,webURL,imageURL,nativeImageURL,validateSnapshot};
 const handler=root.webkit?.messageHandlers?.mouseCompanion;if(!handler)return;
 let installed=false,initialized=false,sequence=0,queued=null,lastSelection='',mode='focus';
 const pending=new Map(),placements=new Map(),waiters=new Map(),memoryListeners=new Set();let activeAgent='',protectedError='',transactionBusy=false;
 let pendingRaw=null,lastAcknowledgedRaw=null,cacheWarning=false;
 const smartTagWaiters=new Map();
 const attachmentWaiters=new Map();
 const volatileCache=new Map();
 function cacheRead(key){if(volatileCache.has(key))return volatileCache.get(key);try{return localStorage.getItem(key);}catch{cacheWarning=true;return null;}}
 function cacheWrite(key,raw){volatileCache.set(key,raw);try{localStorage.setItem(key,raw);return true;}catch{cacheWarning=true;return false;}}
 function cacheRemove(key){volatileCache.set(key,null);try{localStorage.removeItem(key);}catch{cacheWarning=true;}}
 function saveStatus(status,message){
  let el=document.getElementById('mac-save-status');
  if(!el&&document.body){el=document.createElement('div');el.id='mac-save-status';el.setAttribute('role','status');Object.assign(el.style||{}, {position:'fixed',bottom:'10px',right:'16px',zIndex:'99998',padding:'6px 10px',background:'#fff',color:'#555',borderRadius:'6px',fontSize:'12px'});document.body.append(el);}
  if(el){el.textContent=message;el.setAttribute('data-status',status);}
 }
 function stage(snapshot){const raw=JSON.stringify(snapshot);pendingRaw=raw;cacheWrite(dirtyKey(),raw);saveStatus('saving','正在保存到本机…');return raw;}
 let readyResolve;const readyPromise=new Promise(resolve=>{readyResolve=resolve;});
 const project=()=>new URLSearchParams(location.search).get('project')||'';
 const dirtyKey=()=> 'cuppa-mac-pending:'+project();
 function post(action,payload={}){const requestId='mac:'+Date.now()+':'+(++sequence);pending.set(requestId,{...payload,action});handler.postMessage({...payload,version:1,action,requestId,projectId:project()});return requestId;}
 function context(cards){return cards.map(c=>({id:c.id,nativeMaterialId:c.nativeMaterialId||'',title:c.title||'',text:c.text||'',url:webURL(c.designObject?.originalUrl||c.url),imageDataURL:inlineImageURL(c.image||c.preview),provenance:c.provenance||{}}));}
 function selectedCards(){const ids=typeof marqueeIds!=='undefined'&&marqueeIds.size?[...marqueeIds]:selected?[selected]:[];return state.cards.filter(c=>ids.includes(c.id));}
 // Selection is initiated only by a finished gesture, never by the polling mirror.
 let selectionDelayMS=500;
 let selectionEpoch=0,selectionSession='',selectionGeometry='',selectionIDs='',selectionTool='',gesture=null,selectionAnchor=null;
 function selectionBounds(){
  const ids=new Set(selectedCards().map(c=>c.id));
  const rects=[...document.querySelectorAll('.card')].filter(el=>ids.has(el.dataset.id)).map(el=>el.getBoundingClientRect()).filter(r=>r.width>0&&r.height>0);
  if(!rects.length)return null;
  const x=Math.max(0,Math.min(...rects.map(r=>r.left))),y=Math.max(0,Math.min(...rects.map(r=>r.top)));
  const right=Math.min(innerWidth,Math.max(...rects.map(r=>r.right))),bottom=Math.min(innerHeight,Math.max(...rects.map(r=>r.bottom)));
  return right>x&&bottom>y?{x,y,width:right-x,height:bottom-y,viewportWidth:innerWidth,viewportHeight:innerHeight}:null;
 }
 function selectionToolActive(){return typeof tool!=='undefined'&&['select','rectangle','lasso'].includes(tool)&&!(typeof canvasAction!=='undefined'&&canvasAction)&&!(typeof picking!=='undefined'&&picking);}
 function selectionBlocked(){return !selectionToolActive()||!initialized||mode!=='cocreate'||transactionBusy||protectedError||document.hidden||location.hash!=='#cuppa'||!!document.querySelector('dialog[open]')||!!document.activeElement?.matches('input,textarea,[contenteditable="true"]')||!!root.cuppaCaptureBusy||!!root.cuppaRelationBusy;}
 function closeNativeSelection(){const menu=document.getElementById('selection-actions');if(menu)menu.hidden=true;selectionEpoch++;selectionSession='';selectionAnchor=null;selectionTool='';post('selectionEnded');}
 function completeSelection(explicit=false){
  if(selectionBlocked())return false;
  const bounds=selectionBounds(),cards=context(selectedCards());if(!bounds||!cards.length)return false;
  if(cards.length>8){notify('每次最多向伙伴提供 8 张卡片，请在参考预览中减少勾选或缩小选区。');return false;}
  selectionSession='selection:'+ (++selectionEpoch);selectionTool=tool;selectionGeometry=JSON.stringify(bounds);selectionIDs=cards.map(c=>c.id).sort().join('\0');selectionAnchor=null;
  post('selectionCompleted',{cards,bounds,selectionSession,explicit});return true;
 }
 // Canvas tools own their pointer capture and stop propagation. Complete at the
 // authoritative gesture boundary instead of hoping a later DOM listener runs.
 function beginSelectionGesture(){gesture=null;closeNativeSelection();}
 function completeSelectionGesture(kind){
  if(!['select','rectangle','lasso'].includes(kind)||typeof tool==='undefined'||tool!==kind)return false;
  gesture=null;return completeSelection();
 }
 function alignSelection(value){
  if(!value||value.projectId!==project()||value.selectionSession!==selectionSession)return false;
  selectionAnchor=value;
  const menu=document.getElementById('selection-actions'),workspace=document.getElementById('workspace');if(!menu||!workspace)return false;
  if(!value.visible){menu.hidden=true;return true;}
  const count=selectedCards().length,countLabel=document.getElementById('selection-count');if(countLabel)countLabel.textContent=`已选 ${count} 张卡片`;
  menu.hidden=false;const detail=document.getElementById('selection-details');if(detail)detail.disabled=count!==1;const r=workspace.getBoundingClientRect();
  // Options above the pointer; the original native prompt stays below/right.
  const preferred=value.x-r.left+22;
  const left=Math.max(8,Math.min(workspace.clientWidth-menu.offsetWidth-8,preferred+menu.offsetWidth+8>workspace.clientWidth?value.x-r.left-menu.offsetWidth-22:preferred));
  const top=Math.max(8,Math.min(workspace.clientHeight-menu.offsetHeight-8,value.y-r.top-menu.offsetHeight-12));
  menu.style.left=left+'px';menu.style.top=top+'px';return true;
 }
 function installSelection(){
  const editable='input,textarea,select,[contenteditable],button,a,.claim-sketch';
  document.addEventListener('pointerdown',e=>{
   if(!e.isTrusted||e.button!==0||e.isPrimary===false)return;
   // Any newer primary interaction owns focus, including toolbar and menu buttons.
   selectionEpoch++;gesture=null;
   if(e.target.closest('#selection-actions'))return;
   const card=e.target.closest('.card'),blank=e.target.id==='workspace'||e.target.id==='world';
   gesture=selectionToolActive()&&tool==='select'&&!e.target.closest(editable)&&(card||blank)?{id:e.pointerId,x:e.clientX,y:e.clientY,moved:false,threshold:e.pointerType==='mouse'?1:3,marquee:blank}:null;
   if(card||blank)closeNativeSelection();
  },true);
  document.addEventListener('pointermove',e=>{
   if(!e.isTrusted||!gesture||gesture.id!==e.pointerId)return;
   // Remember the entire gesture, including a drag that returns to its origin.
   // Match drag-controller.js without changing its drag semantics.
   if(Math.hypot(e.clientX-gesture.x,e.clientY-gesture.y)>=gesture.threshold)gesture.moved=true;
  },true);
  document.addEventListener('pointerup',e=>{
   const g=gesture;gesture=null;if(!e.isTrusted||!g||g.id!==e.pointerId)return;
   if(!g.marquee&&(g.moved||Math.hypot(e.clientX-g.x,e.clientY-g.y)>=g.threshold))return;
   const epoch=selectionEpoch;
   setTimeout(()=>{if(epoch!==selectionEpoch||gesture||typeof cardDragActive!=='undefined'&&cardDragActive||typeof marqueeDragging!=='undefined'&&marqueeDragging)return;completeSelection();},g.marquee?0:selectionDelayMS);
  },true);
  document.addEventListener('dblclick',e=>{if(e.target.closest('.card')){gesture=null;closeNativeSelection();}},true);
  document.addEventListener('pointercancel',()=>{gesture=null;closeNativeSelection();},true);
  document.addEventListener('keydown',e=>{if(e.isTrusted){selectionEpoch++;gesture=null;}if(e.key==='Escape')closeNativeSelection();},true);
  root.addEventListener('hashchange',closeNativeSelection);
  const originalSync=typeof syncMarqueeSelection==='function'?syncMarqueeSelection:null;
  if(originalSync)syncMarqueeSelection=function(){originalSync();if(selectionAnchor)alignSelection(selectionAnchor);};
  // The old reveal helper pans the canvas to fit its detached menu. Native placement does not.
  if(typeof revealSelectionMenu==='function')revealSelectionMenu=function(){syncMarqueeSelection();if(!selectionAnchor)document.getElementById('selection-actions').hidden=true;};
  const detail=document.getElementById('selection-details');
  if(detail)detail.onclick=()=>{const cards=selectedCards();if(cards.length!==1)return;closeNativeSelection();root.CuppaCardDetails?.open(cards[0]);};
  const custom=document.getElementById('selection-custom-toggle');
  if(custom)custom.onclick=()=>completeSelection(true);
  for(const [id,prompt] of [['selection-analyze','请分别单独分析每张卡片，逐一梳理内容要点、设计启发和需要补充的依据，不合并材料。'],['selection-similar','请寻找与所选卡片相关的相似设计案例，并说明相似之处与来源。']]){const button=document.getElementById(id);if(button)button.onclick=()=>{const cards=selectedCards();if(!cards.length)return;closeNativeSelection();document.getElementById('selection-actions').hidden=true;agent(prompt,cards);};}
  const close=document.getElementById('selection-close');if(close)close.onclick=()=>{document.getElementById('selection-actions').hidden=true;closeNativeSelection();};
 }
 function saveNative(){if(!initialized||protectedError||transactionBusy)return;const snapshot=clone(state);if(JSON.stringify(snapshot)===lastAcknowledgedRaw&&!pendingRaw)return;stage(snapshot);post('saveCanvas',{snapshot});}
 function agent(prompt='',cards=selectedCards()){if(cards.length>8){notify('每次最多向伙伴提供 8 张卡片，请减少选择后重试。');return false;}activeAgent=post('openAgent',{prompt,cards:context(cards)});return true;}
 function refresh(restoreGraph=false){
  state.cards.forEach(c=>{if(c.type==='source')prepareResource(c);prepareCardTags(c);if(c.type==='claim')prepareClaim(c);});
  renderCards();renderSide();
  // First native hydration replaces the empty bootstrap after graph initialization.
  // Restore structural UI once, without rebuilding an active region editor on later syncs.
  if(restoreGraph&&typeof renderRegions==='function')renderRegions();
  if(typeof relationButtons==='function')relationButtons();
  sync();updateView();
  // Background WebKit can defer animation frames; restored labels/counts must not wait.
  if(restoreGraph&&typeof drawGraph==='function')drawGraph();
 }
 function receiveSnapshot(value){
  if(!value||value.version!==1||value.projectId!==project())return {ok:false,message:'项目不匹配'};
  if(!installed){queued=value;return {ok:true,pending:true};}
  if(Number.isFinite(value.selectionDelayMS))selectionDelayMS=Math.max(250,Math.min(1500,value.selectionDelayMS));
  if(value.storageError){protect(string(value.storageError)||'原生画布无法安全读取。');readyResolve();return {ok:false,message:protectedError};}
  if(protectedError)return {ok:false,message:protectedError};
  if(transactionBusy){queued=value;return {ok:true,pending:true};}
  if(cuppaBootstrap?.error)return {ok:false,message:cuppaBootstrap.error};
  try{
   if(Array.isArray(value.projects)){const projects=value.projects.filter(p=>p&&typeof p.id==='string'&&p.id&&typeof p.name==='string');cacheWrite('design-canvas-projects',JSON.stringify(projects));cuppaBootstrap.projects=projects;const name=projects.find(p=>p.id===project())?.name||'CUPPA';document.querySelectorAll('[data-project-name]').forEach(el=>{el.textContent=name;el.title=name;});}
   const before=JSON.stringify(state);const first=!initialized;
   const incoming=value.canvasSnapshot;
   if(incoming){try{validateSnapshot(incoming);}catch(error){protect(error.message);readyResolve();return {ok:false,message:protectedError};}}
   if(!initialized&&incoming&&!pendingRaw&&!cacheRead(dirtyKey()))state=clone(incoming);
   validateSnapshot(state);
   // Legacy snapshots may predate graph fields; missing fields mean an empty graph.
   if(state.regions===undefined)state.regions=[];
   if(state.connections===undefined)state.connections=[];
   const materials=Array.isArray(value.materials)?value.materials:[];
   state=mergeMaterials(state,materials);
   for(const [id,point] of placements){const card=state.cards.find(c=>c.nativeMaterialId===id);if(card){card.x=point.x;card.y=point.y;placements.delete(id);}}
   const tray=cuppaTrayInbox.inspect();cuppaTrayInbox.sync({page:tray.page,projectId:project(),items:materials.map(m=>({...m,project:project(),sourceURL:m.sourceURL||m.url||''}))});
   initialized=true;canvasPersistedToken=JSON.stringify(state);cacheWrite(canvasStorageKey,canvasPersistedToken);
   if(value.mode==='focus'||value.mode==='cocreate')mode=value.mode;
   cuppaWorkModeV1.sync({available:true,mode,revision:value.revision||0});
   if(first||before!==JSON.stringify(state)){refresh(first);root.cuppaCanvasHistory?.external(state);saveNative();}
   root.weaviaProjectDesktop?.update?.(cuppaBootstrap.projects||[],project(),materials);if(first){readyResolve();memoryListeners.forEach(f=>f());}return {ok:true,count:state.cards.length};
  }catch(error){notify('Mac 画布同步失败：'+error.message);return {ok:false,message:error.message};}
 }
 function ack(id,result){const request=pending.get(id);if(!request)return false;pending.delete(id);
  if(request.action==='importAttachment'){const waiter=attachmentWaiters.get(id);if(waiter){attachmentWaiters.delete(id);clearTimeout(waiter.timer);if(waiter.project!==project())waiter.reject(Error('项目已切换，未添加卡片。'));else result.ok?waiter.resolve(result):waiter.reject(Error(result.message||'原件导入失败。'));}return true;}
  if(request.action==='setWorkMode'||request.action==='openSettings'){if(result.mode)mode=result.mode;cuppaWorkModeV1.ack(request.token,{...result,mode});}
  if(request.action==='trayCommand'){if(request.token)cuppaTrayInbox.ack(request.token,result);if(!result.ok)(request.ids||[]).forEach(id=>placements.delete(id));}
  if(request.action==='saveCanvas'){
   const raw=JSON.stringify(request.snapshot);
   if(result.ok){lastAcknowledgedRaw=raw;if(pendingRaw===raw||(!pendingRaw&&cacheRead(dirtyKey())===raw)){pendingRaw=null;cacheRemove(dirtyKey());saveStatus('saved',cacheWarning?'已保存到本机 · 网页缓存不可用':'已保存到本机');}}
   else saveStatus('failed',(result.message||'本机保存失败。')+(cacheWarning?' 草稿仅保留在当前窗口，请勿关闭。':' 待保存草稿仍保留。'));
  }
  if(request.action==='generateSmartTags'&&!result.ok){const waiter=smartTagWaiters.get(id);if(waiter){smartTagWaiters.delete(id);clearTimeout(waiter.timer);waiter.reject(Error(result.message||'标签生成未开始。'));}}
  if(request.action==='openAgent'&&!result.ok&&id===activeAgent)activeAgent='';
  if(request.action==='cancelAgent'&&result.ok&&request.agentRequestId===activeAgent)activeAgent='';
  const waiter=waiters.get(id);if(waiter){waiters.delete(id);clearTimeout(waiter.timer);result.ok?waiter.resolve():waiter.reject(Error(result.message||'本机持久保存失败，草稿仍保留。'));}
  if(!result.ok)notify(result.message||(cacheWarning?'原生操作未完成，请保留当前窗口后重试。':'原生操作未完成，画布本地副本仍保留。'));return true;
 }
 function boot(id){
  const key=id?'design-canvas-v1:'+id:'design-canvas-v1',raw=cacheRead(key),draftRaw=cacheRead('cuppa-mac-pending:'+id);
  const snapshot=validateSnapshot((draftRaw||raw)?JSON.parse(draftRaw||raw):{resourceSemanticVersion:1,aiExcerptExamplesAdded:true,cards:[],mode:'personal',drafts:{personal:{text:'',sources:[],refs:[]},agent:{text:'',sources:[],refs:[]}}});
  const projects=JSON.parse(cacheRead('design-canvas-projects')||'[]');if(!Array.isArray(projects))throw Error('项目列表格式无法读取，原数据未修改。');
  if(id===project())pendingRaw=draftRaw;snapshot.aiExcerptExamplesAdded=true;snapshot.resourceSemanticVersion=1;return {snapshot,raw,projects};
 }
 function install(){
  installed=true;
  installSelection();
  for(const type of ['pointerdown','keydown','paste','drop','click'])document.addEventListener(type,event=>{if(transactionBusy||protectedError){event.preventDefault();event.stopImmediatePropagation();}},true);
  if(root.CuppaRelationStore){const original=root.CuppaRelationStore;root.CuppaRelationStore=Object.freeze({...original,commit:commitRelation});}
  persistCanvasSnapshot=function(next){
   if(protectedError||cuppaBootstrap?.error||transactionBusy||root.cuppaCaptureBusy||root.cuppaRelationBusy)throw Error(protectedError||cuppaBootstrap?.error||'本机提交正在完成，请稍候。');
   validateSnapshot(next);validateSnapshot(state);
   const prior=next._companionPersistence,current=state._companionPersistence;
   next._companionPersistence={...prior,version:1,revision:Math.max(prior?.revision||0,current?.revision||0)+1,captureIds:[...new Set([...(current?.captureIds||[]),...(prior?.captureIds||[])])]};
   const raw=stage(next);canvasPersistedToken=raw;cacheWrite(canvasStorageKey,raw);
   if(initialized)post('saveCanvas',{snapshot:clone(next)});root.cuppaCanvasHistory?.record(next);return raw;
  };
  selectionTaskPanel=(cards,prompt)=>agent(prompt,state.cards.filter(c=>cards.some(v=>v.id===c.id)));
  launchAiConversation=()=>agent(draft().text,state.cards.filter(c=>(draft().refs||[]).some(r=>r.id===c.id)));
  const originalSubmit=submitSearch;submitSearch=function(){if(activeAiProvider()){launchAiConversation();return;}if(state.mode==='agent'){const q=draft().text.trim();if(!q){openSources();return;}closeSources();const sources=draft().sources.filter(i=>i<4);const urls=(sources.length?sources:[0]).map(i=>({name:sourceNames[i],url:searchUrl(i,q)}));panel('搜索来源', '<p>打开真实搜索页面查看结果；不会自动生成或收藏搜索结果。</p>'+urls.map(item=>'<p><a href="'+esc(item.url)+'" target="_blank">'+esc(item.name)+' ↗</a></p>').join(''));return;}originalSubmit();};
  loadResourceFrame=(el,c)=>{if(c.url)post('openURL',{url:webURL(c.url)});c.expanded=false;el.classList.remove('web-window');};
  root.open=url=>{const safe=webURL(url);if(safe)post('openURL',{url:safe});return null;};
  document.addEventListener('click',event=>{const a=event.target.closest('a[href]');if(a&&webURL(a.href)){event.preventDefault();event.stopImmediatePropagation();post('openURL',{url:webURL(a.href)});}},true);
  cuppaContextCapture.configure({available:true});
  document.querySelectorAll('#sidebar .project,#collapsed-project').forEach(header=>{
   if(header.querySelector('.history-entry'))return;
   const history=document.createElement('button');history.className='icon history-entry';history.type='button';
   history.id=header.id==='collapsed-project'?'history-collapsed':'history';
   history.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 11a9 9 0 1 1 2.6 7.4M3 5v6h6"/><path d="M12 7v5l3 2"/></svg>';
   history.title='伙伴历史记录';history.setAttribute('aria-label','伙伴历史记录');history.onclick=()=>post('openHistory');
   header.insertBefore(history,header.querySelector('#collapse,#expand'));
  });
  // A wrapped collapsed title must not cover the existing vertically centered tools.
  const collapsedHeader=document.getElementById('collapsed-project'),canvasToolbar=document.getElementById('canvas-toolbar');
  if(collapsedHeader&&canvasToolbar&&root.ResizeObserver){
   const placeHeader=()=>{if(collapsedHeader.hidden)return;const h=collapsedHeader.getBoundingClientRect(),t=canvasToolbar.getBoundingClientRect();document.getElementById('workspace').style.setProperty('--collapsed-toolbar-min-center',(h.bottom+12+t.height/2)+'px');};
   const headerObserver=new ResizeObserver(placeHeader);headerObserver.observe(collapsedHeader);headerObserver.observe(canvasToolbar);
  }
  let workToken='',contextToken='',trayToken='';setInterval(()=>{
   const tray=cuppaTrayInbox.inspect().request;if(tray&&tray.token!==trayToken){trayToken=tray.token;if(tray.placement)tray.ids.forEach((id,i)=>placements.set(id,{x:tray.placement.x+i*28,y:tray.placement.y+i*28}));post('trayCommand',{token:tray.token,command:tray.action,ids:tray.ids,placement:tray.placement});}
   const request=cuppaWorkModeV1.peek();if(request&&request.token!==workToken){workToken=request.token;post(request.action==='settings'?'openSettings':'setWorkMode',request);}
   if(selectionSession){if(!selectionToolActive()||tool!==selectionTool||mode!=='cocreate'||location.hash!=='#cuppa'||selectedCards().map(c=>c.id).sort().join('\0')!==selectionIDs){closeNativeSelection();}else if(!gesture){const bounds=selectionBounds(),raw=JSON.stringify(bounds);if(bounds&&raw!==selectionGeometry){selectionGeometry=raw;post('selectionGeometry',{bounds,selectionSession});}}}
   const selection=context(selectedCards()),signature=JSON.stringify(selection);if(signature!==lastSelection){lastSelection=signature;post('selectCards',{cards:selection,ids:selection.map(c=>c.id)});}
   const capture=cuppaContextCapture.peek();if(capture&&capture.token!==contextToken){contextToken=capture.token;agent('',state.cards.filter(c=>capture.selectionIds.includes(c.id)));cuppaContextCapture.ack(capture.token,{status:'added',message:'已打开伙伴参考，请检查后发送。'});}
   const inspiration=cuppaInspirationV1.take(mode);if(inspiration?.action==='start')agent();
  },250);
  window.addEventListener('pagehide',saveNative);
  if(queued){const value=queued;queued=null;receiveSnapshot(value);}post('ready');
 }
 function receiveAgentResult(result){
  if(!activeAgent||!result||result.requestId!==activeAgent||(result.projectId&&result.projectId!==project()))return false;
  // The native companion owns reply rendering, scrolling, Markdown and Stop.
  // Rebuilding a canvas panel for every stream chunk duplicates that answer,
  // replaces unrelated dialogs and reopens a dialog the user just dismissed.
  if(result.status==='streaming')return true;
  if(['completed','success','error','failed','cancelled'].includes(result.status)){activeAgent='';return true;}
  return false;
 }

 function importAttachment(kind){
  if(!['image','pdf'].includes(kind))return Promise.reject(Error('不支持的原件类型。'));
  const id=post('importAttachment',{kind});
  return new Promise((resolve,reject)=>{const timer=setTimeout(()=>{attachmentWaiters.delete(id);reject(Error('选择文件等待超时，请重新打开卡片编辑。'));},600000);attachmentWaiters.set(id,{resolve,reject,timer,project:project()});});
 }
 async function commitCanvasCard(card,expected,expectedProject){
  if(expectedProject!==project())throw Error('项目已切换，未添加卡片。');
  const next=clone(state),index=next.cards.findIndex(c=>c.id===card.id);
  if(JSON.stringify(index<0?null:next.cards[index])!==(expected===null?'null':expected))throw Error('原卡片已变化，未覆盖原数据。');
  if(index<0)next.cards.push(clone(card));else next.cards[index]=clone(card);
  next._companionPersistence={...next._companionPersistence,version:1,revision:(next._companionPersistence?.revision||0)+1,captureIds:next._companionPersistence?.captureIds||[]};
  return commitNative(next);
 }
 function requestSmartTags(card){
  const id=post('generateSmartTags',{card});let cancel;
  const promise=new Promise((resolve,reject)=>{
   cancel=()=>{const waiter=smartTagWaiters.get(id);if(!waiter)return;smartTagWaiters.delete(id);clearTimeout(waiter.timer);post('cancelSmartTags',{tagRequestId:id});reject(Error('已中止标签生成。'));};
   const timer=setTimeout(()=>{if(!smartTagWaiters.has(id))return;smartTagWaiters.delete(id);post('cancelSmartTags',{tagRequestId:id});reject(Error('等待标签生成超时，请重试。'));},180000);
   smartTagWaiters.set(id,{resolve,reject,timer,project:project()});
  });return {requestId:id,promise,cancel};
 }
 function receiveSmartTagResult(result){
  const waiter=result&&smartTagWaiters.get(result.requestId);if(!waiter||result.projectId!==waiter.project||project()!==waiter.project)return false;
  smartTagWaiters.delete(result.requestId);clearTimeout(waiter.timer);
  if(result.ok)waiter.resolve(result);else waiter.reject(Error(result.message||'标签生成失败，请重试。'));return true;
 }
 async function commitSmartTags(id,expected,rows,metadata){
  const next=clone(state),index=next.cards.findIndex(c=>c.id===id);if(index<0)throw Error('卡片已删除，未保存标签。');
  next.cards[index]=root.WeaviaSmartTags.adopt(next.cards[index],expected,rows,metadata);
  next._companionPersistence={...next._companionPersistence,version:1,revision:(next._companionPersistence?.revision||0)+1,captureIds:next._companionPersistence?.captureIds||[]};
  const result=await commitNative(next);refresh();return result;
 }

 function protect(message){
  protectedError=message;cuppaBootstrap.error=message;root.cuppaCanvasHistory?.update?.();
  let banner=document.getElementById('mac-storage-warning');if(!banner){banner=document.createElement('div');banner.id='mac-storage-warning';banner.setAttribute('role','alert');Object.assign(banner.style,{position:'fixed',top:'8px',left:'18%',right:'18%',zIndex:'99999',padding:'12px',background:'#fff2f0',color:'#a8071a',border:'1px solid #ffccc7',borderRadius:'8px'});document.body.append(banner);}
  banner.textContent=message+' 画布已进入只读保护，原数据未覆盖。'+(cacheWarning&&pendingRaw?' 待保存草稿仅保留在当前窗口，请勿关闭。':' 请修复后重新打开。');
 }
 async function commitNative(next,historyReplay=false,expectedState=null){
  await readyPromise;if(protectedError)throw Error(protectedError);if(transactionBusy)throw Error('另一项本机提交尚未完成，请重试。');
  if(expectedState!==null&&JSON.stringify(state)!==expectedState)throw Error('画布已有新的修改，未覆盖新内容。');
  validateSnapshot(next);transactionBusy=true;const raw=JSON.stringify(next);
  try{
   // Keep a recoverable pending candidate, but do not publish success before native disk acknowledgement.
   stage(next);
   const id=post('saveCanvas',{snapshot:clone(next)});
   await new Promise((resolve,reject)=>{const timer=setTimeout(()=>{waiters.delete(id);protect('尚未确认本机保存结果，待保存副本已保留。');reject(Error(protectedError));},15000);waiters.set(id,{resolve,reject,timer});});
   state=clone(next);canvasPersistedToken=raw;
   if(!historyReplay)root.cuppaCanvasHistory?.record(state);
   cacheWrite(canvasStorageKey,raw);
   return {snapshot:clone(next),cacheRaw:raw,warning:protectedError};
  }catch(error){
   // A rejected transaction is still a recovery draft. Do not let later edits overwrite it.
   if(!protectedError)protect(error.message||'本机保存失败，待保存草稿仍保留。');throw error;
  }
  finally{transactionBusy=false;if(queued&&!protectedError){const value=queued;queued=null;setTimeout(()=>receiveSnapshot(value),0);}}
 }
 async function commitCanvasHistory(next,expected){
  await readyPromise;
  if(JSON.stringify(state)!==expected)throw Error('画布已有新的修改，未覆盖新内容。');
  if(root.cuppaCaptureBusy||root.cuppaRelationBusy)throw Error('另一项画布操作正在保存，请稍后重试。');
  next=clone(next);next._companionPersistence={...state._companionPersistence,version:1,revision:(state._companionPersistence?.revision||0)+1,captureIds:state._companionPersistence?.captureIds||[]};
  return commitNative(next,true,expected);
 }
 async function commitRelation(id,active,expected,before,after,index){
  if(id!==project()||expected!==canvasPersistedToken||JSON.stringify(active)!==JSON.stringify(state))throw Error('画布或项目已变化，未提交旧关系。');
  const next=clone(active),edgeId=(after||before).id,edges=next.connections||[];
  if(JSON.stringify(edges.find(e=>e.id===edgeId)||null)!==JSON.stringify(before))throw Error('原关系已变化，请重新读取。');
  next.connections=edges.filter(e=>e.id!==edgeId);if(after)next.connections.splice(index<0?next.connections.length:Math.min(index,next.connections.length),0,clone(after));
  next._companionPersistence={...next._companionPersistence,version:1,revision:(next._companionPersistence?.revision||0)+1,captureIds:next._companionPersistence?.captureIds||[]};
  return commitNative(next);
 }
 function createMemoryStore(id){
  let raw=null,cache=null,queue=Promise.resolve(),migrated=false;
  const engine=root.createProjectMemoryStore({getItem:()=>raw,setItem:(_key,value)=>{raw=value;}},id);
  const legacy=root.createDurableProjectMemoryStore(id);
  async function read(){
   await readyPromise;if(protectedError)throw Error(protectedError);if(id!==project())throw Error('记忆项目已切换。');
   if(state.macProjectMemory===undefined&&!migrated){
    // Only a validated legacy document is migrated. Corruption is never replaced with an empty record.
    const previous=await legacy.read();migrated=true;
    if(previous.document.entries.length){const next=clone(state);next.macProjectMemory=previous.document;await commitNative(next);}
   }
   raw=state.macProjectMemory===undefined?null:JSON.stringify(state.macProjectMemory);cache=engine.read();return cache;
  }
  function run(method,expected,input){const operation=queue.then(async()=>{
   await read();if(method==='read')return cache;const checkpoint=engine.checkpoint(),prior=raw;
   try{const result=engine[method](expected,input),next=clone(state);next.macProjectMemory=result.document;await commitNative(next);cache=result;return result;}
   catch(error){raw=prior;engine.restoreCheckpoint(checkpoint);throw error;}
  });queue=operation.catch(()=>{});return operation;}
  const listeners=new Set(),changed=()=>listeners.forEach(f=>f());memoryListeners.add(changed);
  return Object.freeze({read:()=>run('read'),put:(token,input)=>run('put',token,input),remove:(token,id)=>run('remove',token,id),undoLast:token=>run('undoLast',token),canUndo:token=>engine.canUndo(token),subscribe:listener=>{listeners.add(listener);return ()=>listeners.delete(listener);},dispose:()=>{memoryListeners.delete(changed);legacy.dispose();},peek:()=>{if(!cache)throw Error('请先打开项目记忆。');return cache;}});
 }

 root.mouseCompanionMac=Object.freeze({beginSelectionGesture,completeSelectionGesture,importAttachment,commitCanvasCard,previewAttachment:(attachmentId,pageNumber)=>post('previewAttachment',{attachmentId,...(Number.isInteger(pageNumber)?{pageNumber}:{})}),dismissSelection:closeNativeSelection,openMaterial:id=>post('trayCommand',{command:'open',ids:[id]}),openExternal:url=>{const safe=webURL(url);if(safe)post('openURL',{url:safe});},alignSelection,createMemoryStore,commitCanvasHistory,receiveAgentResult,requestSmartTags,receiveSmartTagResult,commitSmartTags,boot,install,receiveSnapshot,ack,openAgent:agent,switchProject:targetProjectId=>post('switchProject',{targetProjectId}),createProject:name=>post('createProject',{name})});
})(globalThis);

/* Pollable one-way bridge. No credentials, filesystem, network, or native proxy. */
(()=>{
 const jobs=new Map();let busy=false;
 for(const type of ['pointerdown','click','keydown','paste','drop'])document.addEventListener(type,event=>{if(busy){event.preventDefault();event.stopImmediatePropagation();}},true);
 function createCard(payload,snapshot,options={}){const m=payload.material,offset=snapshot.cards.length%5*28;const card={id:crypto.randomUUID(),type:'source',title:m.title,text:m.text,addedBy:'personal',x:options.placement?.x??(options.quiet?(Math.max(285,innerWidth/2-160)+offset-pan.x)/zoom:285+offset),y:options.placement?.y??(options.quiet?(200+offset-pan.y)/zoom:165+offset),time:new Date().toLocaleTimeString('zh-CN',{hour:'2-digit',minute:'2-digit'}),url:m.sourceURL||'',tags:[m.area,...(Array.isArray(m.tags)?m.tags:[])].filter(tag=>typeof tag==='string'&&tag.trim()),creator:{kind:'personal'},confirmationStatus:'unconfirmed',provenance:{sourceLabel:m.sourceLabel||'手动粘贴',url:m.sourceURL||'',capturedAt:m.capturedAt||new Date().toISOString(),excerpt:m.text},userNote:m.note||'',companionCapture:payload};prepareResource(card);prepareCardTags(card);return card;}
 function begin(payload,attempt,options={}){if(options.expectedPage!==undefined&&globalThis.cuppaTrayInbox?.inspect().page!==options.expectedPage)return {error:'画布页面已更新，未提交旧页面请求；素材仍在托盘。'};if(options.expectedProjectId!==undefined&&options.expectedProjectId!==projectId)return {error:'当前画布项目已变化，剩余素材仍在托盘。'};if(options.placement&&(!Number.isFinite(options.placement.x)||!Number.isFinite(options.placement.y)||Math.abs(options.placement.x)>1000000||Math.abs(options.placement.y)>1000000))return {error:'放置位置无效，素材仍在托盘。'};const identity=CuppaCaptureStore.fingerprint(payload),prior=jobs.get(attempt);if(prior){if(prior.identity!==identity)return {error:'保存请求内容变化，请重试。'};return prior.result;}if(busy||globalThis.cuppaRelationBusy)return {pending:true};if(globalThis.cuppaBootstrap?.error)return {error:globalThis.cuppaBootstrap.error};
 document.activeElement?.blur();
 const job={identity,result:{pending:true}};jobs.set(attempt,job);busy=true;globalThis.cuppaCaptureBusy=true;
 let release;globalThis.cuppaCaptureFinished=new Promise(resolve=>release=resolve);
 const nodes=[...document.body.children].filter(n=>n.tagName!=='SCRIPT'),inert=nodes.map(n=>n.inert);nodes.forEach(n=>n.inert=true);
 const activeState=JSON.parse(JSON.stringify(state)),expectedRaw=canvasPersistedToken;
 CuppaCaptureStore.commit(payload,{activeProjectId:projectId,activeState,expectedRaw,createCard:(payload,snapshot)=>createCard(payload,snapshot,options)}).then(result=>{
  globalThis.cuppaBootstrap.projects=result.projects;
  if(result.project.id===projectId){if(!result.duplicate){state=result.snapshot;canvasPersistedToken=result.cacheRaw;}try{renderCards();renderSide();if(!options.quiet){locate(result.cardId);location.hash='cuppa';}}catch{}}
  const url=new URL(location.href);url.searchParams.set('project',result.project.id);url.hash='cuppa';job.result={done:true,cardId:result.cardId,warning:result.warning,navigate:options.quiet||result.project.id===projectId?'':url.href};
  try{notify(result.warning||'材料已持久保存为资源卡')}catch{}
 }).catch(error=>{job.result={error:error.message||'保存失败，材料仍在托盘。'};}).finally(()=>{busy=false;globalThis.cuppaCaptureBusy=false;nodes.forEach((n,i)=>n.inert=inert[i]);globalThis.cuppaCaptureFinished=null;release();});
 return job.result;
 }
 const locations=new Map();
 function locateBegin(id,attempt,expectedPage){
  if(expectedPage!==undefined&&globalThis.cuppaTrayInbox?.inspect().page!==expectedPage)return {error:'画布页面已更新，请重新点击定位。'};
  const prior=locations.get(attempt);if(prior)return prior.id===id?prior.result:{error:'定位请求变化，请重新点击。'};
  if(busy||globalThis.cuppaRelationBusy)return {pending:true};if(globalThis.cuppaBootstrap?.error)return {error:cuppaBootstrap.error};
  const job={id,result:{pending:true}},page=location.href;locations.set(attempt,job);
  CuppaCaptureStore.lookup(id).then(result=>{
   if(location.href!==page)throw Error('页面已变化，请重新点击定位。');
   if(result.project.id===projectId){const card=state.cards.find(c=>c.id===result.cardId&&c.companionCapture?.material?.id===id);if(!card)throw Error('原卡片已被移除，未重新创建。');location.hash='cuppa';locate(card.id);job.result={done:true,cardId:card.id};}
   else{const url=new URL(location.href);url.searchParams.set('project',result.project.id);url.searchParams.set('focusCapture',id);url.hash='cuppa';job.result={done:true,cardId:result.cardId,navigate:url.href};}
  }).catch(error=>{job.result={error:error.message||'定位失败，原素材仍保留。'};});
  if(locations.size>64)locations.delete(locations.keys().next().value);return job.result;
 }
 globalThis.mouseCompanionCapture=Object.freeze({begin,locateBegin});
 const focus=new URL(location.href).searchParams.get('focusCapture');
 if(focus){requestAnimationFrame(()=>{const card=state.cards.find(c=>c.companionCapture?.material?.id===focus);if(card){locate(card.id);notify('已定位原素材卡片');}else notify('原卡片已被移除，托盘素材仍保留；未重新创建。');const url=new URL(location.href);url.searchParams.delete('focusCapture');history.replaceState(null,'',url.href);});}
})();

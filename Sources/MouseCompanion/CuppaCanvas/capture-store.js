/* Native capture commits are atomic and strictly durable. localStorage remains a
 * compatibility cache for the existing editor, never a capture success receipt. */
(function(root){
 'use strict';
 const DB='cuppa-capture-transactions',VERSION=1,LIST='design-canvas-projects';
 let opening;
 const key=id=>id?'design-canvas-v1:'+id:'design-canvas-v1';
 const empty=id=>({resourceSemanticVersion:id?1:0,mode:'personal',cards:[],drafts:{personal:{text:'',sources:[],refs:[]},agent:{text:'',sources:[],refs:[]}}});
 const clone=value=>JSON.parse(JSON.stringify(value));
 function revision(value){const meta=value?._companionPersistence;if(meta===undefined)return 0;if(meta.version!==1||!Number.isSafeInteger(meta.revision)||meta.revision<1||(meta.captureIds!==undefined&&(!Array.isArray(meta.captureIds)||meta.captureIds.some(id=>typeof id!=='string'))))throw Error('画布存储版本暂不支持，原数据未修改。');return meta.revision;}
 function parse(raw,id){if(raw===null||raw===undefined)return empty(id);let value;try{value=JSON.parse(raw)}catch{throw Error('原画布数据无法读取，未覆盖原数据。');}if(!value||!Array.isArray(value.cards)||!value.drafts||!value.drafts.personal||!value.drafts.agent)throw Error('原画布格式无法读取，未覆盖原数据。');revision(value);return value;}
 function projects(raw){if(raw===null||raw===undefined)return [];let value;try{value=typeof raw==='string'?JSON.parse(raw):raw}catch{throw Error('项目列表无法读取，原数据未修改。');}if(!Array.isArray(value)||value.some(p=>!p||typeof p.id!=='string'||!p.id||typeof p.name!=='string')||new Set(value.map(p=>p.id)).size!==value.length)throw Error('项目列表格式无法读取，原数据未修改。');return value;}
 function mergeProjects(local,durable){const result=clone(local);for(const p of durable)if(!result.some(x=>x.id===p.id))result.push(clone(p));return result;}
 function newest(raw,record,id){const local=parse(raw,id);if(!record)return local;if(record.version!==VERSION||typeof record.snapshot!=='string')throw Error('持久画布版本暂不支持，原数据未修改。');const stored=parse(record.snapshot,id),a=revision(local),b=revision(stored);if(raw===null||raw===record.snapshot||(b>a&&raw===record.baseRaw))return stored;
 // Revision alone is not ordering: another page can edit an older cache while
 // durable-only captures advance this record. If raw changed from baseRaw, merge
 // only unseen receipts. A seen ID with no card is a deliberate later deletion.
 const seen=new Set(local._companionPersistence?.captureIds||[]),known=stored._companionPersistence?.captureIds||[];
 const missing=stored.cards.filter(c=>known.includes(c.companionCapture?.material?.id)&&!seen.has(c.companionCapture.material.id)&&!local.cards.some(x=>x.companionCapture?.material?.id===c.companionCapture.material.id));
 if(missing.length||known.some(id=>!seen.has(id))){local.cards.push(...clone(missing));local._companionPersistence={version:1,revision:Math.max(a,b)+1,captureIds:[...new Set([...seen,...known])]};}
 else if(a===b&&raw!==null&&JSON.stringify(local)!==JSON.stringify(stored))throw Error('画布有冲突版本，请重新打开项目后重试，原数据未覆盖。');
 return local;}
 function open(){if(opening)return opening;opening=new Promise((resolve,reject)=>{let r,abandoned=false;try{r=root.indexedDB.open(DB,VERSION)}catch{reject(Error('无法打开持久存储，材料仍在托盘。'));return;}r.onupgradeneeded=()=>{for(const name of ['canvases','receipts','catalog'])if(!r.result.objectStoreNames.contains(name))r.result.createObjectStore(name);};r.onerror=()=>reject(Error('无法打开持久存储，请检查空间或权限后重试。'));r.onblocked=()=>{abandoned=true;reject(Error('持久存储被另一页面占用，请关闭旧页面后重试。'));};r.onsuccess=()=>{const db=r.result;if(abandoned){db.close();return;}db.onversionchange=()=>{db.close();opening=null;};resolve(db);};}).catch(e=>{opening=null;throw e});return opening;}
 async function imageRecord(key){const db=await open();return new Promise((resolve,reject)=>{const tx=db.transaction('canvases','readonly'),r=tx.objectStore('canvases').get(key);let record;r.onsuccess=()=>record=r.result;tx.oncomplete=()=>resolve(record);tx.onabort=()=>reject(Error('无法读取本机图片预览。'));tx.onerror=()=>{};});}
 async function hydrate(snapshot){if(root.CuppaTrayImageAssets)await root.CuppaTrayImageAssets.hydrate(snapshot,imageRecord);return snapshot;}
 async function boot(id){const db=await open();return new Promise((resolve,reject)=>{const tx=db.transaction(['canvases','catalog'],'readonly');let record,list,failure;const a=tx.objectStore('canvases').get(id),b=tx.objectStore('catalog').get('projects');a.onsuccess=()=>record=a.result;b.onsuccess=()=>list=b.result;tx.oncomplete=async()=>{try{const raw=root.localStorage.getItem(key(id)),snapshot=await hydrate(newest(raw,record,id));resolve({snapshot,projects:mergeProjects(projects(root.localStorage.getItem(LIST)),projects(list)),raw});}catch(e){reject(e)}};tx.onabort=()=>reject(failure||Error('读取持久画布失败，原数据未修改。'));tx.onerror=()=>{};});}
 async function lookup(id){
  if(typeof id!=='string'||!id)throw Error('素材编号无效。');const db=await open();
  return new Promise((resolve,reject)=>{const tx=db.transaction(['receipts','canvases','catalog'],'readonly');let result,failure,imageMeta;const fail=e=>{failure=e;try{tx.abort()}catch{}};
   const r=tx.objectStore('receipts').get(id);r.onsuccess=()=>{try{const receipt=r.result;if(!receipt)throw Error('尚未找到已提交回执，请在托盘核对并重试原提交。');if(receipt.version!==1||typeof receipt.projectId!=='string'||typeof receipt.cardId!=='string')throw Error('原提交回执版本暂不支持，未修改任何数据。');
    const c=tx.objectStore('catalog').get('projects');c.onsuccess=()=>{try{const list=mergeProjects(projects(root.localStorage.getItem(LIST)),projects(c.result));const project=receipt.projectId===''?{id:'',name:'CUPPA'}:list.find(p=>p.id===receipt.projectId);if(!project)throw Error('原画布项目已不存在，托盘素材仍保留。');
     const a=tx.objectStore('canvases').get(project.id);a.onsuccess=()=>{try{const snapshot=newest(root.localStorage.getItem(key(project.id)),a.result,project.id);const card=snapshot.cards.find(card=>card.id===receipt.cardId&&card.companionCapture?.material?.id===id);if(!card)throw Error('原画布卡片已被移除，未重新创建；托盘原素材仍保留。');imageMeta=card.companionCapture?.material?.image;result={project,cardId:card.id};}catch(e){fail(e)}};
    }catch(e){fail(e)}};
   }catch(e){fail(e)}};
   tx.oncomplete=async()=>{try{if(imageMeta){if(!root.CuppaTrayImageAssets)throw Error('图片模块未就绪。');const assets=root.CuppaTrayImageAssets;assets.metadata(imageMeta);assets.install(await assets.stored(await imageRecord(assets.key(imageMeta.preview.id)),imageMeta));}resolve(result)}catch(e){reject(e)}};tx.onabort=()=>reject(failure||Error('无法读取原画布位置，请稍后重试。'));tx.onerror=()=>{};
  });
 }
 function fingerprint(payload){const m=clone(payload.material);delete m.saved;return JSON.stringify({material:m,acceptedSuggestions:payload.acceptedSuggestions||[]});}
 async function commit(payload,options){
 // Freeze the caller-owned object before asynchronous validation. Transfer bytes
 // are deliberately not copied into the fingerprint, card, receipt, or cache.
 const clean={material:clone(payload?.material),acceptedSuggestions:clone(payload?.acceptedSuggestions||[])};
 const m=clean.material;if(!m||typeof m.id!=='string'||!m.id||typeof m.project!=='string'||!m.project.trim()||typeof m.text!=='string'||(!m.text.trim()&&m.image===undefined))throw Error('材料或项目不能为空。');
 if(m.image!==undefined&&!root.CuppaTrayImageAssets)throw Error('图片模块未就绪，素材仍在托盘。');
 const prepared=root.CuppaTrayImageAssets?await root.CuppaTrayImageAssets.prepare({...clean,imagePreview:payload.imagePreview}):null;
 payload=clean;const identity=fingerprint(clean),db=await open();return new Promise((resolve,reject)=>{let tx,result,failure;try{tx=db.transaction(['canvases','receipts','catalog'],'readwrite',{durability:'strict'});if(tx.durability!=='strict')throw Error('当前环境不支持可靠提交。');}catch(e){reject(e);return;}
 const canvases=tx.objectStore('canvases'),receipts=tx.objectStore('receipts'),catalog=tx.objectStore('catalog');
 const fail=e=>{failure=e;try{tx.abort()}catch{}};
 const r=receipts.get(m.id);r.onsuccess=()=>{try{const prior=r.result;if(prior&&(prior.version!==1||prior.fingerprint!==identity))throw Error('这条材料已有另一份提交，请保留当前草稿并检查原项目，避免重复保存。');const c=catalog.get('projects');c.onsuccess=()=>{try{const list=mergeProjects(projects(root.localStorage.getItem(LIST)),projects(c.result));let target;const explicit=typeof m.canvasProjectId==='string';if(prior){target=prior.projectId===''?{id:'',name:'CUPPA'}:list.find(p=>p.id===prior.projectId);if(!target)throw Error('原提交的项目已变化，请重新打开项目。');}else if(explicit){target=m.canvasProjectId===''?{id:'',name:'CUPPA'}:list.find(p=>p.id===m.canvasProjectId);if(!target)throw Error('材料绑定的项目已不存在，未改存到其他项目。');}else{const matches=list.filter(p=>p.name===m.project);if(matches.length>1)throw Error('有多个同名项目，请回到目标画布重新收集，未猜测保存位置。');target=matches[0];}if(!target){target={id:root.crypto.randomUUID(),name:m.project};list.push(target);}const request=canvases.get(target.id);request.onsuccess=()=>{try{const raw=root.localStorage.getItem(key(target.id));let snapshot=newest(raw,request.result,target.id);if(options.activeProjectId===target.id){if(raw!==options.expectedRaw||revision(snapshot)>revision(options.activeState))throw Error('画布已在别处更新，材料仍在托盘，请重新打开项目后重试。');snapshot=clone(options.activeState);revision(snapshot);}
 let card=snapshot.cards.find(x=>x.companionCapture?.material?.id===m.id);
 if(prior){if(!card)throw Error('这条材料已保存后被移除，未重复添加。请检查原项目。');result={project:target,snapshot,cardId:card.id,duplicate:true,projects:list};return;}
 if(card&&fingerprint(card.companionCapture)!==identity)throw Error('同一材料编号已有不同内容，未覆盖原卡片。');
 if(!card){card=options.createCard(clone(payload),snapshot);snapshot.cards.push(card);}
 snapshot._companionPersistence={version:1,revision:Math.max(revision(snapshot),request.result?revision(parse(request.result.snapshot,target.id)):0)+1,captureIds:[...new Set([...(snapshot._companionPersistence?.captureIds||[]),m.id])]};
 if(prepared)canvases.put(prepared,root.CuppaTrayImageAssets.key(prepared.id));
 canvases.put({version:1,snapshot:JSON.stringify(snapshot),baseRaw:raw},target.id);receipts.put({version:1,fingerprint:identity,projectId:target.id,cardId:card.id},m.id);catalog.put(list,'projects');result={project:target,snapshot,cardId:card.id,duplicate:false,projects:list,baseRaw:raw};
 }catch(e){fail(e)}};}catch(e){fail(e)}};}catch(e){fail(e)}};
 tx.oncomplete=async()=>{if(result.duplicate){try{await hydrate(result.snapshot);resolve({...result,warning:root.CuppaTrayImageAssets?.warning(result.snapshot)||''});}catch(e){reject(e)}return;}let warning='',cacheRaw=result.baseRaw;try{if(prepared)root.CuppaTrayImageAssets.install(prepared)}catch{warning='图片已持久保存；预览未能显示，请重新打开画布。';}// No UI, in-memory state, or success callback is changed before this event.
 try{const current=root.localStorage.getItem(key(result.project.id));parse(current,result.project.id);if(current===result.baseRaw){const encoded=JSON.stringify(result.snapshot);root.localStorage.setItem(key(result.project.id),encoded);cacheRaw=encoded;}else warning='画布有更新，已保留较新的本地版本。';root.localStorage.setItem(LIST,JSON.stringify(mergeProjects(projects(root.localStorage.getItem(LIST)),result.projects)));}catch{warning='材料已持久保存；兼容缓存未更新，将在重新打开时恢复。';}
 resolve({...result,warning,cacheRaw});};tx.onabort=()=>reject(failure||Error('材料未保存，草稿仍在托盘。请检查存储空间或权限后重试。'));tx.onerror=()=>{};
 });}
 root.CuppaCaptureStore=Object.freeze({boot,commit,lookup,revision,key,parse,fingerprint,mergeProjects,projects,hydrate});
})(globalThis);

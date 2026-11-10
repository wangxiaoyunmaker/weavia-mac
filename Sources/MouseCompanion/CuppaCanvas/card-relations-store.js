/* A strict, per-project operation journal. Recovery changes only the named edge,
 * preserving card edits and respecting operations already seen by later saves. */
(function(root){
 'use strict';
 const DB='cuppa-card-relations',VERSION=1;
 const clone=x=>JSON.parse(JSON.stringify(x)),object=x=>!!x&&typeof x==='object'&&!Array.isArray(x);
 let opening;
 function known(snapshot){const m=snapshot._relationPersistence;if(m===undefined)return [];if(!object(m)||m.version!==1||!Array.isArray(m.operations)||m.operations.some(x=>typeof x!=='string'||!x)||new Set(m.operations).size!==m.operations.length)throw Error('关系保存版本暂不支持，原数据未覆盖。');return m.operations;}
 function operations(record){
  if(record===undefined)return [];
  if(!object(record)||record.version!==VERSION||!Array.isArray(record.operations))throw Error('关系日志版本或格式暂不支持，原数据未覆盖。');
  const ids=new Set();
  for(const op of record.operations){
   if(!object(op)||typeof op.id!=='string'||!op.id||ids.has(op.id)||typeof op.edgeId!=='string'||!op.edgeId||!Number.isSafeInteger(op.index)||op.index<0||(!op.before&&!op.after)||[op.before,op.after].some(edge=>edge!==null&&(!object(edge)||edge.id!==op.edgeId||typeof edge.from!=='string'||typeof edge.to!=='string')))throw Error('关系日志版本或格式暂不支持，原数据未覆盖。');
   ids.add(op.id);
  }
  return record.operations;
 }
 function open(){if(opening)return opening;opening=new Promise((resolve,reject)=>{let request,abandoned=false;try{request=root.indexedDB.open(DB,VERSION);}catch{reject(Error('无法打开关系持久存储。'));return;}request.onupgradeneeded=()=>request.result.createObjectStore('projects');request.onerror=()=>reject(Error('无法读取关系持久存储，请检查空间或权限。'));request.onblocked=()=>{abandoned=true;reject(Error('关系持久存储被占用，请关闭旧页面。'));};request.onsuccess=()=>{const db=request.result;if(abandoned){db.close();return;}db.onversionchange=()=>{db.close();opening=null;};resolve(db);};}).catch(e=>{opening=null;throw e;});return opening;}
 function reconcile(snapshot,record){
  const next=clone(snapshot),seen=new Set(known(next)),ops=operations(record);if(next.connections!==undefined&&(!Array.isArray(next.connections)||next.connections.some(e=>!object(e)||typeof e.id!=='string')||new Set(next.connections.map(e=>e.id)).size!==next.connections.length))throw Error('原关系格式无法读取，原数据未覆盖。');next.connections=next.connections||[];
  for(const op of ops){if(seen.has(op.id))continue;const current=next.connections.find(e=>e.id===op.edgeId)||null;
   if(JSON.stringify(current)!==JSON.stringify(op.before)&&JSON.stringify(current)!==JSON.stringify(op.after))throw Error('关系存在另一份修改，未覆盖原数据，请保留当前画布后检查。');
   if(JSON.stringify(current)!==JSON.stringify(op.after)){
    if(op.after&&next.connections.some(e=>e.id!==op.edgeId&&((e.from===op.after.from&&e.to===op.after.to)||(e.from===op.after.to&&e.to===op.after.from))))throw Error('关系存在重复版本，未覆盖原数据。');
    const index=next.connections.findIndex(e=>e.id===op.edgeId);if(index>=0)next.connections.splice(index,1);
    if(op.after)next.connections.splice(Math.max(0,Math.min(op.index,next.connections.length)),0,clone(op.after));
   }
   seen.add(op.id);
  }
  if(ops.length||snapshot._relationPersistence)next._relationPersistence={...snapshot._relationPersistence,version:1,operations:[...seen]};
  return next;
 }
 async function recover(projectId,snapshot){const db=await open();return new Promise((resolve,reject)=>{const tx=db.transaction('projects','readonly'),request=tx.objectStore('projects').get(projectId);let record;request.onsuccess=()=>record=request.result;tx.oncomplete=()=>{try{resolve(reconcile(snapshot,record));}catch(e){reject(e);}};tx.onabort=()=>reject(Error('关系持久记录读取失败，原数据未覆盖。'));tx.onerror=()=>{};});}
 async function commit(projectId,activeState,expectedRaw,before,after,index){
  const db=await open(),storageKey=root.CuppaCaptureStore.key(projectId),snapshot=clone(activeState),knownIds=new Set(known(snapshot)),edgeId=(after||before).id;
  return new Promise((resolve,reject)=>{
   let tx,failure,result;try{tx=db.transaction('projects','readwrite',{durability:'strict'});if(tx.durability!=='strict')throw Error('当前环境不支持可靠关系提交。');}catch(e){reject(e);return;}
   const fail=e=>{failure=e;try{tx.abort();}catch{}};
   const request=tx.objectStore('projects').get(projectId);request.onsuccess=()=>{try{
    const previous=operations(request.result),raw=root.localStorage.getItem(storageKey);
    if(raw!==expectedRaw||previous.some(op=>!knownIds.has(op.id)))throw Error('关系或画布已在别处更新，未覆盖原数据，请重新打开。');
    const current=snapshot.connections.find(e=>e.id===edgeId)||null;if(JSON.stringify(current)!==JSON.stringify(before))throw Error('原关系已变化，未覆盖新数据。');
    const op={id:root.crypto.randomUUID(),edgeId,before:clone(before),after:clone(after),index:index<0?snapshot.connections.length:index};
    const next=reconcile(snapshot,{version:1,operations:[op]});
    next._companionPersistence={...snapshot._companionPersistence,version:1,revision:root.CuppaCaptureStore.revision(snapshot)+1,captureIds:snapshot._companionPersistence?.captureIds||[]};
    tx.objectStore('projects').put({version:1,operations:[...previous,op]},projectId);result={snapshot:next,baseRaw:raw};
   }catch(e){fail(e);}};
   tx.oncomplete=()=>{
    let cacheRaw=result.baseRaw,warning='';
    try{if(root.localStorage.getItem(storageKey)!==result.baseRaw)throw Error('newer cache');const encoded=JSON.stringify(result.snapshot);root.localStorage.setItem(storageKey,encoded);if(root.localStorage.getItem(storageKey)!==encoded)throw Error('cache unconfirmed');cacheRaw=encoded;}
    catch{warning='关系已可靠保存；兼容缓存未更新，重新打开时会恢复。';}
    resolve({...result,cacheRaw,warning});
   };
   tx.onabort=()=>reject(failure||Error('关系未保存，草稿仍保留。请检查存储空间后重试。'));tx.onerror=()=>{};
  });
 }
 root.CuppaRelationStore=Object.freeze({recover,commit,reconcile,known});
 if(typeof module==='object')module.exports=root.CuppaRelationStore;
})(globalThis);

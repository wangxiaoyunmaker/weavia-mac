/* Restricted local-canvas tool boundary. Never evaluate model-generated code. */
(()=>{
 if(globalThis.mouseCompanionActions)return;
 let revision=0, snapshots=new Map(), undo=null, pending=null;
 const serial=()=>JSON.stringify(state);
 const ok=(extra={})=>({ok:true,project:projectId,...extra});
 const fail=message=>({ok:false,message});
 const render=()=>{renderCards();if(typeof renderRegions==='function')renderRegions();if(typeof refreshGraph==='function')refreshGraph();};
 const cancel=()=>{snapshots.clear();if(pending){clearTimeout(pending.timer);pending=null;}return ok({message:'已停止，未提交的整理已取消。'});};
 const events=globalThis.addEventListener?globalThis:document;
 events.addEventListener('pointerdown',cancel,true);
 events.addEventListener('keydown',cancel,true);
 function snapshot(){const version=String(++revision);snapshots.clear();snapshots.set(version,serial());return ok({version,selectedIds:typeof marqueeIds!=='undefined'&&marqueeIds.size?[...marqueeIds]:(typeof selected!=='undefined'&&selected?[selected]:[]),cards:state.cards.slice(0,200).map(c=>({id:c.id,type:c.type,title:String(c.title||'').slice(0,200),text:String(c.text||'').slice(0,1000),x:c.x,y:c.y})),truncated:state.cards.length>200});}
 function check(p){if(p.project!==projectId)throw Error('项目已变化，请重试。');if(!snapshots.has(p.version)||snapshots.get(p.version)!==serial())throw Error('画布已被修改，本次操作未执行。');if((typeof canvasAction!=='undefined'&&canvasAction)||(typeof marqueeDragging!=='undefined'&&marqueeDragging))throw Error('请先完成当前画布手势。');if(typeof cardDragActive!=='undefined'&&cardDragActive)throw Error('请先完成拖动。');if(document.activeElement?.matches('input,textarea,[contenteditable="true"]'))throw Error('正在编辑内容，请先结束编辑。');}
 function commit(before,next){if(globalThis.cuppaCaptureBusy)throw Error('材料正在提交，请稍候。');let encoded;if(typeof persistCanvasSnapshot==='function')encoded=persistCanvasSnapshot(next);else{encoded=JSON.stringify(next);localStorage.setItem(canvasStorageKey,encoded);if(localStorage.getItem(canvasStorageKey)!==encoded)throw Error('保存未得到确认。');}state=next;undo={before,after:encoded};snapshots.clear();render();if(!globalThis.matchMedia?.('(prefers-reduced-motion: reduce)').matches){const previous=JSON.parse(before);for(const c of next.cards){const old=previous.cards.find(v=>v.id===c.id),el=document.querySelector(`[data-id="${CSS.escape(c.id)}"]`);if(old&&el&&el.animate&&(old.x!==c.x||old.y!==c.y))el.animate([{transform:`translate(${old.x-c.x}px,${old.y-c.y}px)`},{transform:'translate(0,0)'}],{duration:260,easing:'cubic-bezier(.2,.7,.2,1)'});}}}
 function execute(p){try{
  if(!p||typeof p.op!=='string')throw Error('无效动作。');
  if(p.op==='memory'){if(!globalThis.mouseCompanionMemory)throw Error('项目记忆尚未加载，请先打开画布。');return ok({message:globalThis.mouseCompanionMemory.summary()});}
  if(p.op==='snapshot')return snapshot();
  if(p.op==='cancel')return cancel();
  if(p.op==='status')return ok({pending:!!pending,canUndo:!!undo&&undo.after===serial()});
  if(p.op==='undo'){cancel();if(!undo||undo.after!==serial())throw Error('没有可安全撤销的操作，或画布已有新的修改。');const previous=undo;commit(previous.after,JSON.parse(previous.before));undo=null;return ok({message:'已撤销上一次伙伴整理，恢复原位置。'});}
  check(p);
  if(p.op==='search'){const query=String(p.query||'').trim().toLocaleLowerCase();if(!query||query.length>200)throw Error('请输入简短搜索词。');const hits=state.cards.filter(c=>[c.title,c.text,c.url,...(c.tags||[])].join(' ').toLocaleLowerCase().includes(query));if(hits[0])locate(hits[0].id);return ok({hits:hits.map(c=>({id:c.id,title:c.title})),message:hits.length?'画布内找到 '+hits.length+' 张卡片，已定位第一张。':'画布内没有匹配卡片。'});}
  if(p.op!=='arrange'&&p.op!=='move')throw Error('不支持的工具。');
  if(pending)throw Error('已有待执行操作，请先停止。');
  const before=serial(),next=JSON.parse(before);let moves=[];
  if(p.op==='arrange'){
   const ids=p.ids||next.cards.map(c=>c.id);if(!Array.isArray(ids)||ids.length>200||new Set(ids).size!==ids.length)throw Error('整理范围无效或超过200张。');
   const cards=ids.map(id=>{const c=next.cards.find(c=>c.id===id);if(!c)throw Error('卡片不存在。');return c;});
   if(!cards.length)return ok({message:'当前画布没有可整理的卡片。'});
   const cols=Math.ceil(Math.sqrt(cards.length));const width=Math.max(320,...cards.map(c=>document.querySelector(`[data-id="${CSS.escape(c.id)}"]`)?.offsetWidth||320))+40;
   const height=Math.max(240,...cards.map(c=>document.querySelector(`[data-id="${CSS.escape(c.id)}"]`)?.offsetHeight||240))+40;
   const x=Math.min(...cards.map(c=>c.x)),y=Math.min(...cards.map(c=>c.y));moves=cards.map((c,i)=>({id:c.id,x:x+i%cols*width,y:y+Math.floor(i/cols)*height}));
  }else{moves=p.moves;if(!Array.isArray(moves)||!moves.length||moves.length>200||new Set(moves.map(m=>m.id)).size!==moves.length)throw Error('移动列表无效。');}
  for(const m of moves){const c=next.cards.find(c=>c.id===m.id);if(!c||![m.x,m.y].every(v=>Number.isFinite(v)&&Math.abs(v)<=100000))throw Error('卡片或目标位置无效。');c.x=m.x;c.y=m.y;}
  // Existing semantic region memberships are preserved; enlarge their bounds to contain moved members.
  for(const r of next.regions||[]){const members=next.cards.filter(c=>(r.members||[]).includes(c.id));if(members.length){r.x=Math.min(r.x,...members.map(c=>c.x-24));r.y=Math.min(r.y,...members.map(c=>c.y-48));r.width=Math.max(r.width,...members.map(c=>c.x+400-r.x));r.height=Math.max(r.height,...members.map(c=>c.y+400-r.y));}}
  pending={before,next,timer:null};return ok({prepared:true,count:moves.length,message:'准备整理 '+moves.length+' 张卡片；操作画布会自动中止。'});
 }catch(e){return fail(e.message);}}
 function apply(){try{if(!pending)throw Error('操作已停止。');const p=pending;pending=null;if(p.before!==serial())throw Error('画布已变化，本次整理未执行。');commit(p.before,p.next);return ok({message:'已整理画布卡片，位置已保存，可撤销。'});}catch(e){return fail(e.message);}}
 globalThis.mouseCompanionActions={execute,apply};
})();

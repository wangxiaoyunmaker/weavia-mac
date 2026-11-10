/* Strict relationship transactions publish only after durable completion. */
for(const type of ['pointerdown','click','keydown','paste','drop'])window.addEventListener(type,event=>{if(globalThis.cuppaRelationBusy){event.preventDefault();event.stopImmediatePropagation();}},true);
let relationUndoRecord=null;
const relationEditorDrafts=new Map();
function relationError(error){return error.name==='QuotaExceededError'?'本机存储空间不足，修改未保存，草稿仍保留。':error.name==='SecurityError'?'本机存储不可用，修改未保存，草稿仍保留。':error.message||'保存失败，草稿仍保留。'}
function relationCardName(id){const card=state.cards.find(c=>c.id===id);return card?(card.title||'未命名卡片'):'卡片已不在画布';}
function relationButtons(){
 const count=$('#relation-count');if(count){const examples=(state.connections||[]).filter(e=>e.relation?.source==='assistant').length;count.textContent=`${state.connections?.length||0} 条`+(examples?` · ${examples} 条助手示例`:' · 手动标注');}
 const undo=$('#relations-undo');if(undo)undo.disabled=!relationUndoRecord;
}
async function relationCommit(before,after,restoreIndex=-1){
 const index=before?state.connections.findIndex(e=>e.id===before.id):restoreIndex;
 if(before&&(index<0||JSON.stringify(state.connections[index])!==JSON.stringify(before)))throw Error('原关系已变化，未覆盖新数据。请关闭后重新打开。');
 if(globalThis.cuppaCaptureBusy||globalThis.cuppaRelationBusy)throw Error('正在保存，请稍候。');
 const nodes=[...document.body.children].filter(n=>n.tagName!=='SCRIPT'),inert=nodes.map(n=>n.inert);let release;globalThis.cuppaRelationFinished=new Promise(resolve=>release=resolve);globalThis.cuppaRelationBusy=true;nodes.forEach(n=>n.inert=true);
 try{const result=await CuppaRelationStore.commit(projectId,state,canvasPersistedToken,before,after,index);state=result.snapshot;canvasPersistedToken=result.cacheRaw;if(result.warning)notify(result.warning);}
 finally{globalThis.cuppaRelationBusy=false;nodes.forEach((n,i)=>n.inert=inert[i]);globalThis.cuppaRelationFinished=null;release();}
 relationUndoRecord={before:before?JSON.parse(JSON.stringify(before)):null,after:after?JSON.parse(JSON.stringify(after)):null,index};
 relationButtons();refreshGraph();
}
async function relationUndo(){
 if(!relationUndoRecord)return;
 const {before,after,index}=relationUndoRecord,id=(after||before).id,current=state.connections.find(e=>e.id===id);
 if(JSON.stringify(current||null)!==JSON.stringify(after))throw Error('关系已在之后修改，不能覆盖新内容。');
 if(before&&CardRelations.pairExists(state.connections,before.from,before.to,id))throw Error('两张卡片已有另一条关系，无法恢复重复连线。');
 await relationCommit(after,before,index);relationUndoRecord=null;activeEdge=null;refreshGraph();relationButtons();notify('已撤销上次关系操作');
}
async function relationRemove(id){
 const edge=state.connections.find(e=>e.id===id);if(!edge)return;
 try{await relationCommit(edge,null);activeEdge=null;notify('已移除关系，可在「卡片关系」撤销');return true;}
 catch(error){notify(relationError(error));return false;}
}
function relationDialogCleanup(dialog,restore){
 dialog.classList.add('relations-dialog');
 const keyboard=e=>{if(e.key!=='Escape')e.stopPropagation();};
 const route=()=>{if(location.hash!=='#cuppa')dialog.close();};
 dialog.addEventListener('keydown',keyboard);window.addEventListener('hashchange',route);
 dialog.addEventListener('close',()=>{dialog.classList.remove('relations-dialog');dialog.removeEventListener('keydown',keyboard);window.removeEventListener('hashchange',route);if(location.hash==='#cuppa')restore?.();},{once:true});
}
function relationCloseThen(dialog,next){
 // ArkWeb may dispatch close after a zero-delay timer. Wait for that event so
 // the old dialog cleanup cannot remove the new dialog's classes/listeners.
 dialog.addEventListener('close',()=>queueMicrotask(next),{once:true});dialog.close();
}
function relationList(){
 cancelCanvasAction();hideTagTools();showCreationMenu(null);
 modal('卡片关系',`<section class="relations-panel"><p class="relation-intro">记录材料、想法和设计对象之间的联系。助手示例会单独标明，未经你确认不会成为已确认判断，也不会写入项目记忆。</p><div class="relation-toolbar"><button id="relation-new" class="primary">新建关系</button><button id="relations-undo" ${relationUndoRecord?'':'disabled'}>撤销上次操作</button></div><p id="relation-list-error" role="alert"></p><div class="relation-list">${state.connections.length?state.connections.map(edge=>{const v=CardRelations.view(edge);return `<button class="relation-list-item" data-relation="${esc(edge.id)}"><span class="relation-list-heading"><strong>${esc(v.label)}</strong><span class="relation-status ${v.status}">${esc(v.statusLabel)}</span></span><span class="relation-endpoints">${esc(relationCardName(edge.from))} ↔ ${esc(relationCardName(edge.to))}</span><span class="relation-evidence-preview">${esc(CardRelations.supported(edge)&&edge.relation?.evidence||'尚未记录依据')}</span></button>`;}).join(''):'<p class="relation-empty">还没有关系。选择两张卡片，记录你的比较和观察。<br>也可以用「＋ → 创建连线」从画布开始。</p>'}</div><p class="relation-footnote">普通连线保留原样，标注后才有关系类型。撤销适用于本次打开页面后的最后一次关系操作。</p></section>`);
 const dialog=$('#dialog');relationDialogCleanup(dialog,()=>$('#open-card-relations').focus());
 $('#relation-new').disabled=state.cards.length<2;
 if(state.cards.length<2)$('#relation-new').title='请先在画布添加至少两张卡片';
 $('#relation-new').onclick=()=>relationCloseThen(dialog,()=>relationEditor());
 $$('[data-relation]').forEach(b=>b.onclick=()=>relationCloseThen(dialog,()=>relationEditor(b.dataset.relation)));
 $('#relations-undo').onclick=async()=>{try{await relationUndo();relationCloseThen(dialog,relationList);}catch(error){$('#relation-list-error').textContent=relationError(error);}};
}
function relationEditor(id=null,pair=null){
 const cardIds=new Set(state.cards.map(c=>c.id)),edge=id?state.connections.find(e=>e.id===id):null;
 if(id&&!edge)return;
 if(!edge&&state.cards.length<2){notify('请先添加至少两张卡片');return;}
 cancelCanvasAction();hideTagTools();showCreationMenu(null);clearMarqueeSelection();
 const supported=!edge||CardRelations.supported(edge),missing=edge&&(!cardIds.has(edge.from)||!cardIds.has(edge.to));
 const key=edge?.id||'new',cached=relationEditorDrafts.get(key),original={from:edge?.from||pair?.from||state.cards[0]?.id,to:edge?.to||pair?.to||state.cards[1]?.id,...CardRelations.fields(edge||{}),confirm:false};
 const values=cached?.values||original,snapshot=cached?.snapshot??JSON.stringify(edge);
 let storageAtOpen;try{storageAtOpen=cached?cached.storageAtOpen:localStorage.getItem(canvasStorageKey);}catch{}
 const view=edge?CardRelations.view(edge):{label:'新关系',status:'pending',statusLabel:'待确认'};
 const options=selectedId=>state.cards.map(c=>`<option value="${esc(c.id)}" ${c.id===selectedId?'selected':''}>${esc(c.title||'未命名卡片')} · ${esc(({source:'材料',claim:'想法',design:'设计对象'})[c.type]||'卡片')}</option>`).join('');
 const history=supported&&edge?.relation?.history||[];
 modal(edge?'查看与编辑关系':'添加卡片关系',`<form id="relation-form" novalidate><div class="relation-review-heading"><span>${edge?.relation&&supported?(edge.relation.source==='assistant'?'助手示例（尚非你的判断）':edge.relation.originSource==='assistant'?'由助手示例编辑 · 用户标注':'用户手动标注'):edge?'已有连线':'手动标注'}</span><strong class="relation-status ${view.status}">${esc(view.statusLabel)}</strong></div><p class="relation-intro">写下你看到的联系和依据。保存不代表确认；明确确认只表示你的当前判断，不等于客观事实。</p>
 ${edge?`<div class="relation-pair"><span>${esc(relationCardName(edge.from))}</span><b>↔</b><span>${esc(relationCardName(edge.to))}</span></div>`:`<div class="relation-pair-fields"><label>第一张卡片<select id="relation-from">${options(values.from)}</select></label><span aria-hidden="true">↔</span><label>第二张卡片<select id="relation-to">${options(values.to)}</select></label></div>`}
 ${supported&&!missing?`<label>关系类型<select id="relation-kind">${Object.entries(CardRelations.kinds).map(([k,n])=>`<option value="${k}" ${values.kind===k?'selected':''}>${n}</option>`).join('')}</select></label><label id="relation-custom-row" ${values.kind==='custom'?'':'hidden'}>自定义关系名称<input id="relation-custom" maxlength="40" value="${esc(values.customLabel)}" placeholder="例如：构图参考"></label><label>依据与观察 <small>可先留空，明确确认前需补充</small><textarea id="relation-evidence" maxlength="4000" placeholder="例如：两张海报都使用大字号与斜向构图；具体参考材料中的哪一部分？">${esc(values.evidence)}</textarea></label><p id="relation-edit-note" class="relation-footnote">修改类型或依据后，原确认不再适用。可以保留为待确认，或重新勾选确认。</p><label class="relation-confirm"><input id="relation-confirm" type="checkbox" ${values.confirm?'checked':''}><span>我已检查依据，确认当前关系判断</span></label><div class="relation-form-actions"><button id="relation-save" class="primary" type="submit">${edge?'保存修改':'保存关系'}</button><button id="relation-cancel" type="button">取消</button>${edge?.relation?.status==='confirmed'?'<button id="relation-withdraw" type="button">撤回确认</button>':''}</div>`:`<p class="relation-warning">${missing?'关联卡片已不在画布。关系记录保留，暂不能编辑。':'关系记录的版本或格式暂不支持编辑，原数据已保留。'}</p><button id="relation-cancel" type="button">关闭</button>`}
 <p id="relation-error" role="alert"></p>${edge?'<div class="relation-remove-row"><button id="relation-remove" type="button">移除此关系</button><span>保留两张卡片，可撤销。</span></div>':''}
 <div id="relation-discard" hidden role="alert"><p>还有未保存的修改，是否放弃？</p><button id="relation-keep" type="button">继续编辑</button><button id="relation-drop" type="button">放弃修改</button></div>
 ${history.length?`<details class="relation-history"><summary>标注与确认记录 · ${history.length}</summary>${history.slice().reverse().map(h=>`<article><strong>${esc(({annotated:'手动标注',edited:'修改判断',confirmed:'明确确认',withdrawn:'撤回确认'})[h.action]||'历史记录')} · ${h.status==='confirmed'?'已确认':'待确认'}</strong><time>${esc(typeof h.at==='string'?new Date(h.at).toLocaleString('zh-CN',{hour12:false}):'时间未记录')}</time><p>${esc(h.kind==='custom'?h.customLabel:CardRelations.kinds[h.kind]||'关系')} · ${esc(h.evidence||'尚无依据')}</p></article>`).join('')}</details>`:''}</form>`);
 const dialog=$('#dialog'),editable=supported&&!missing;
 const read=()=>editable?{from:edge?.from||$('#relation-from').value,to:edge?.to||$('#relation-to').value,kind:$('#relation-kind').value,customLabel:$('#relation-custom').value,evidence:$('#relation-evidence').value,confirm:$('#relation-confirm').checked}:original;
 const dirty=()=>JSON.stringify(read())!==JSON.stringify(original);
 let acceptedClose=false,submitting=false;
 const finish=()=>{acceptedClose=true;relationEditorDrafts.delete(key);dialog.close();};
 const requestClose=e=>{if(acceptedClose)return;if(submitting){e?.preventDefault();e?.stopImmediatePropagation();return;}e?.preventDefault();e?.stopImmediatePropagation();if(dirty()){$('#relation-discard').hidden=false;$('#relation-keep').focus();}else finish();};
 const closeButton=e=>requestClose(e);
 const route=()=>{if(location.hash==='#cuppa'||submitting)return;if(dirty())relationEditorDrafts.set(key,{values:read(),storageAtOpen,snapshot});acceptedClose=true;dialog.close();};
 const keyboard=e=>{if(e.key==='Escape')requestClose(e);else e.stopPropagation();};
 dialog.classList.add('relations-dialog');dialog.addEventListener('cancel',requestClose);dialog.addEventListener('keydown',keyboard);$('#dialog-close').addEventListener('click',closeButton,true);window.addEventListener('hashchange',route);
 dialog.addEventListener('close',()=>{dialog.classList.remove('relations-dialog');dialog.removeEventListener('cancel',requestClose);dialog.removeEventListener('keydown',keyboard);$('#dialog-close').removeEventListener('click',closeButton,true);window.removeEventListener('hashchange',route);if(location.hash==='#cuppa')$('#open-card-relations').focus();},{once:true});
 $('#relation-cancel').onclick=requestClose;$('#relation-keep').onclick=()=>{$('#relation-discard').hidden=true;$('#relation-evidence')?.focus();};$('#relation-drop').onclick=finish;
 function checkBaseline(){
  if(storageAtOpen===undefined)throw Error('无法读取本机存储，草稿仍保留。');
  if(localStorage.getItem(canvasStorageKey)!==canvasPersistedToken)throw Error('画布已在别处更新，未覆盖原数据。请保留草稿并重新打开画布。');
  if(edge&&JSON.stringify(state.connections.find(e=>e.id===edge.id))!==snapshot)throw Error('原关系已变化，未覆盖新内容。请重新打开。');
 }
 $('#relation-remove')?.addEventListener('click',async()=>{if(dirty()){$('#relation-error').textContent='请先保存或取消当前修改，再移除关系。';return;}try{checkBaseline();await relationCommit(edge,null);activeEdge=null;finish();notify('已移除关系，可在「卡片关系」撤销');}catch(error){$('#relation-error').textContent=relationError(error);}});
 if(!editable)return;
 const invalidate=()=>{$('#relation-confirm').checked=false;$('#relation-custom-row').hidden=$('#relation-kind').value!=='custom';};
 ['relation-kind','relation-custom','relation-evidence','relation-from','relation-to'].forEach(id=>$('#'+id)?.addEventListener('input',invalidate));
 const submit=async decision=>{
  if(submitting)return;submitting=true;$('#relation-save').disabled=true;$('#relation-error').textContent='正在可靠保存…';
  try{
   checkBaseline();const values=read(),ids=new Set(state.cards.map(c=>c.id));
   if(values.from===values.to)throw Error('请选择两张不同的卡片。');
   if(!ids.has(values.from)||!ids.has(values.to))throw Error('卡片已变化，请重新选择。');
   if(CardRelations.pairExists(state.connections,values.from,values.to,edge?.id))throw Error('这两张卡片已有关系，请从「卡片关系」查看或编辑，未创建重复连线。');
   const base=edge||{id:crypto.randomUUID(),from:values.from,to:values.to,fromSide:pair?.fromSide||'right',toSide:pair?.toSide||'left'};
   const updated=CardRelations.update(base,values,decision|| (values.confirm?'confirm':'keep'),new Date().toISOString());
   if(updated!==edge)await relationCommit(edge,updated);
   activeEdge=updated.id;finish();refreshGraph();notify(updated.relation.status==='confirmed'?'关系判断已确认，未自动写入项目记忆':'关系已保存，当前待确认');
  }catch(error){$('#relation-error').textContent=relationError(error);}
  finally{submitting=false;if($('#relation-save'))$('#relation-save').disabled=false;}
 };
 $('#relation-form').onsubmit=e=>{e.preventDefault();if(!e.isComposing)submit();};
 $('#relation-withdraw')?.addEventListener('click',()=>{if(dirty()){$('#relation-error').textContent='请先保存或取消当前修改，再撤回确认。';return;}submit('withdraw');});
 $('#relation-kind').focus();
}
function relationEdgeMarkup(edge,p,q){
 const v=CardRelations.view(edge),r=CardRelations.supported(edge)&&edge.relation;
 const label=`${v.label} · ${v.statusLabel}`,width=Math.max(110,Math.min(420,Array.from(label).length*12+24)),x=(p.x+q.x)/2,y=(p.y+q.y)/2;
 const kind=r?.kind||'related',custom=r?.customLabel||'',directional=kind==='custom'&&/借鉴|参考|派生|验证|启发|延伸/.test(custom);
 const dx=q.x-p.x,dy=q.y-p.y,length=Math.max(1,Math.hypot(dx,dy)),ux=dx/length,uy=dy/length;
 const arrow=directional?`<path class="relation-arrow" d="M${q.x-ux*13-uy*5},${q.y-uy*13+ux*5} L${q.x},${q.y} L${q.x-ux*13+uy*5},${q.y-uy*13-ux*5}"/>`:'';
 const doubled=kind==='similar'?`<path class="edge-visible relation-parallel" d="M${p.x-uy*3},${p.y+ux*3} L${q.x-uy*3},${q.y+ux*3}"/>`:'';
 const subtype=kind==='custom'&&/暂不|废弃|舍弃/.test(custom)?'rejected':kind;
 return `<g class="canvas-edge relation-edge ${zoom<.65?'relation-edge-compact':''} ${v.status} relation-kind-${subtype} ${activeEdge===edge.id?'edge-selected':''}" data-edge="${esc(edge.id)}" tabindex="0" role="button" aria-label="${esc(label)}，${esc(relationCardName(edge.from))}与${esc(relationCardName(edge.to))}，按 Enter 查看"><path class="edge-hit" d="M${p.x},${p.y} L${q.x},${q.y}"/><path class="edge-visible" d="M${p.x},${p.y} L${q.x},${q.y}"/>${doubled}${arrow}<circle cx="${p.x}" cy="${p.y}" r="4.5"/><circle cx="${q.x}" cy="${q.y}" r="4.5"/><g class="relation-edge-label" transform="translate(${x},${y})"><rect x="${-width/2}" y="-14" width="${width}" height="28" rx="14"/><text text-anchor="middle" dominant-baseline="central">${esc(Array.from(label).length>32?Array.from(label).slice(0,31).join('')+'…':label)}</text></g><title>${esc(label)}${r?.evidence?'\n'+esc(r.evidence):''}${directional?'\n箭头从第一张卡片指向第二张卡片':''}</title></g>`;
}
function initCardRelations(){
 $('#open-card-relations').onclick=relationList;relationButtons();
 window.addEventListener('beforeunload',e=>{if(globalThis.cuppaRelationBusy||relationEditorDrafts.size||($('#relation-form')&&$('#dialog').open)){e.preventDefault();e.returnValue='';}});
}

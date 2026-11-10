/* Real model suggestions are temporary. Only explicit adoption mutates a card. */
(function(root){
 'use strict';
 const clean=value=>String(value??'').trim().replace(/^#+/,'').trim().slice(0,40);
 const clone=value=>JSON.parse(JSON.stringify(value));
 function input(card){
  const blocks=Array.isArray(card.blocks)?card.blocks.flatMap(b=>b.type==='text'?[b.text||'']:b.type==='table'?[].concat(...(b.cells||[])).map(v=>String(v||'')):[]):[];
  return {id:String(card.id||''),nativeMaterialId:String(card.nativeMaterialId||''),title:String(card.title||'').slice(0,500),text:String(blocks.length?blocks.join('\n'):card.text||card.description||'').slice(0,16000),note:String(card.userNote||'').slice(0,2000),existingTags:(card.tags||[]).map(clean).filter(Boolean),imageDataURL:/^data:image\/(png|jpeg|jpg|webp);base64,[A-Za-z0-9+/=\r\n]+$/.test(card.image||card.preview||'')?(card.image||card.preview):''};
 }
 function fingerprint(card){const value=input(card);delete value.existingTags;return JSON.stringify(value);}
 function normalize(rows,existing=[]){
  if(!Array.isArray(rows)||rows.length>8)throw Error('标签返回格式无效，请重新生成。');
  const seen=new Set(existing.map(v=>clean(v).toLowerCase())),result=[];
  for(const row of rows){if(typeof row?.label!=='string'||typeof row?.reason!=='string'||!row.label.trim()||row.label.length>40||!row.reason.trim()||row.reason.length>240||/[\r\n]/.test(row.label))throw Error('模型返回了无效标签，原标签未改变。');const label=clean(row.label);if(!label)throw Error('标签名称为空。');if(!seen.has(label.toLowerCase())){seen.add(label.toLowerCase());result.push({label,reason:row.reason.trim()});}}
  return result.slice(0,5);
 }
 function adopt(card,expected,rows,metadata={}){
  if(fingerprint(card)!==expected)throw Error('卡片内容已变化，请重新生成标签。');
  const chosen=normalize(rows,card.tags||[]);if(!chosen.length)throw Error('这些标签已存在，请选择其他标签。');
  const next=clone(card);next.tags=[...(next.tags||[]),...chosen.map(row=>row.label)];
  next.smartTagHistory=[...(next.smartTagHistory||[]),{source:'ai_suggestion',status:'accepted_by_user',acceptedAt:new Date().toISOString(),provider:String(metadata.provider||''),inputMode:metadata.inputMode==='image_and_text'?'image_and_text':'text_only',tags:chosen.map(row=>{const source=rows.find(v=>clean(v.label)===row.label);return {...row,originalLabel:clean(source?.originalLabel||row.label),editedByUser:!!source?.originalLabel&&clean(source.originalLabel)!==row.label};})}].slice(-30);
  return next;
 }
 function createController(deps){
  let epoch=0,job=null,view={status:'idle',suggestions:[]};
  const emit=()=>deps.changed?.(clone(view));
  function close(){epoch++;job?.cancel?.();job=null;view={status:'idle',suggestions:[]};emit();}
  async function begin(card){
   close();const token=epoch,project=deps.project(),expected=fingerprint(card),id=card.id;
   view={status:'loading',cardId:id,project,expected,suggestions:[],message:'正在生成候选标签…'};emit();
   try{job=deps.generate(input(card));const result=await job.promise;if(token!==epoch)return;const current=deps.card(id);if(project!==deps.project()||!current||fingerprint(current)!==expected)throw Error('卡片内容或项目已变化，请重新生成标签。');const suggestions=normalize(result.suggestions,current.tags||[]);view={...view,status:'ready',suggestions,provider:result.provider||'',inputMode:result.inputMode||'text_only',message:suggestions.length?'AI 建议，采纳后才会保存。':'没有新的可靠标签，可补充卡片内容或手动添加。'};}
   catch(error){if(token!==epoch)return;view={...view,status:'error',message:error.message||'生成失败，请重试。'};}
   finally{if(token===epoch){job=null;emit();}}
  }
  async function accept(rows){
   if(view.status!=='ready')return false;const token=epoch,previous=clone(view);view={...view,status:'saving',message:'正在保存到本机…'};emit();
   try{const current=deps.card(view.cardId);if(deps.project()!==view.project||!current)throw Error('项目或卡片已变化，未保存标签。');adopt(current,view.expected,rows,view);await deps.commit(view.cardId,view.expected,rows,{provider:view.provider,inputMode:view.inputMode});if(token!==epoch)return true;const labels=new Set(rows.map(v=>clean(v.originalLabel||v.label).toLowerCase()));view={...previous,status:'ready',suggestions:previous.suggestions.filter(v=>!labels.has(v.label.toLowerCase())),message:'已采纳并保存到本机。'};emit();return true;}
   catch(error){if(token===epoch){view={...previous,status:'ready',message:error.message||'保存失败，未确认保存。'};emit();}return false;}
  }
  return {begin,accept,close,inspect:()=>clone(view)};
 }
 root.WeaviaSmartTags={input,fingerprint,normalize,adopt,createController};
 if(typeof module!=='undefined'&&module.exports)module.exports=root.WeaviaSmartTags;
})(globalThis);

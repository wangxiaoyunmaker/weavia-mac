/* Local provenance of ideas. A canvas save is not an endorsement or a project-memory write. */
(function(root){
 'use strict';
 const copy=value=>JSON.parse(JSON.stringify(value));
 const kinds=['user','ai','unknown'],statuses=['pending','confirmed','rejected'];
 function content(card){return {title:String(card.title||''),blocks:copy(Array.isArray(card.blocks)?card.blocks:[])}}
 function same(a,b){return JSON.stringify(a)===JSON.stringify(b)}
 function supported(card){
  const p=card.ideaProvenance;if(p===undefined)return true;
  return !!p&&p.version===1&&kinds.includes(p.origin?.kind)&&Array.isArray(p.revisions)&&p.revisions.length>0&&p.revisions.every((r,i)=>r.number===i+1&&Array.isArray(r.content?.blocks)&&typeof r.content?.title==='string')&&Array.isArray(p.events)&&statuses.includes(p.confirmation?.status)&&p.confirmation.revision===p.revisions.length;
 }
 function source(card,isNew){
  const raw=card.creator,kind=typeof raw==='string'?raw.toLowerCase():String(raw?.kind||'').toLowerCase();
  const ai=['agent','ai'].includes(kind),user=['personal','user','human'].includes(kind);
  return {kind:ai?'ai':user?'user':card.addedBy==='agent'?'ai':card.addedBy==='personal'||isNew?'user':'unknown',name:typeof raw==='string'?raw:String(raw?.name||''),createdAt:card.createdAt||null,basis:isNew?'creation':'legacy-metadata'};
 }
 function initialize(card,isNew=false,now=new Date().toISOString()){
  if(card.ideaProvenance!==undefined)return card;
  const origin=source(card,isNew);
  card.ideaProvenance={version:1,origin,revisions:[{number:1,action:isNew?'created':'legacy',author:origin.kind,at:isNew?now:null,content:content(card)}],confirmation:{status:'pending',revision:1,at:null},events:[]};
  return card;
 }
 function edit(card,now,session){
  initialize(card);if(!supported(card))throw Error('此想法的来源记录版本或格式暂不支持修改，原记录未改动。');
  const p=card.ideaProvenance,latest=p.revisions.at(-1),next=content(card);
  if(same(latest.content,next))return false;
  // One focused editing session is one revision. Creation, imported baseline and
  // any explicitly reviewed version are never overwritten by coalescing.
  if(latest.action==='edited'&&latest.session===session&&p.confirmation.status==='pending'&&!p.events.some(e=>e.revision===latest.number)){
   latest.content=next;latest.at=now;
  }else p.revisions.push({number:p.revisions.length+1,action:'edited',author:'user',at:now,session,content:next});
  if(p.confirmation.status!=='pending')p.events.push({action:'invalidated',revision:p.confirmation.revision,at:now,author:'user'});
  p.confirmation={status:'pending',revision:p.revisions.length,at:null};return true;
 }
 function view(card){
  if(!supported(card))return {source:'来源记录待兼容',status:'pending',label:'未确认',supported:false};
  const p=card.ideaProvenance;
  if(!p)return {source:source(card,false).kind==='ai'?'AI 想法':'来源待记录',status:'pending',label:'未确认',supported:true};
  const edited=p.revisions.some(r=>r.author==='user'&&r.action==='edited');
  const label=p.origin.kind==='ai'?(edited?'AI 想法 · 用户已修改':'AI 想法'):p.origin.kind==='user'?'用户想法':edited?'用户修改 · 原来源未记录':'原来源未记录';
  const status=same(p.revisions.at(-1).content,content(card))?p.confirmation.status:'pending';
  return {source:label,status,label:({pending:'未确认',confirmed:'已确认',rejected:'不采纳'})[status],supported:true};
 }
 function decide(card,status,now){
  if(!statuses.includes(status))throw Error('确认状态无效。');
  const next=copy(card);initialize(next);if(!supported(next))throw Error('此想法的来源记录暂不支持修改。');
  const p=next.ideaProvenance;
  if(!same(p.revisions.at(-1).content,content(next)))throw Error('内容已变化，请先保存修改，再确认当前版本。');
  if(status==='confirmed'&&!p.revisions.at(-1).content.blocks.some(b=>b.type==='text'?String(b.text||'').trim():b.type==='table'?b.cells?.some(row=>row.some(v=>String(v).trim())):b.strokes?.length))throw Error('请先写下想法，再确认。');
  if(status===p.confirmation.status)return next;
  p.confirmation={status,revision:p.revisions.length,at:now};
  p.events.push({action:status==='confirmed'?'confirmed':status==='rejected'?'rejected':'withdrawn',revision:p.revisions.length,at:now,author:'user'});return next;
 }
 function plain(snapshot){return snapshot.blocks.map(b=>b.type==='text'?String(b.text||''):b.type==='table'?(b.cells||[]).map(row=>row.join(' · ')).join('\n'):b.type==='doodle'?'[涂鸦 · '+(b.strokes?.length||0)+' 笔]':'[其他内容]').join('\n')}
 root.IdeaProvenance={initialize,edit,decide,view,supported,content,plain};
 if(typeof module==='object')module.exports=root.IdeaProvenance;
})(typeof window==='object'?window:globalThis);

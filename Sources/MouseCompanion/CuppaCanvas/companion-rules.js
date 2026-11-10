/* Local, evidence-bound suggestions. No model, network, storage or user-intent inference. */
(function(root){
 'use strict';
 const text=value=>typeof value==='string'?value.trim():'';
 const title=c=>text(c.title).slice(0,80)||'未命名卡片';
 const tags=c=>Array.isArray(c.tags)?c.tags.filter(v=>typeof v==='string'&&v.trim()).map(v=>v.trim()).slice(0,16):[];
 const source=c=>text(c.provenance?.url)||text(c.url)||text(c.sourceURL);
 function candidates(cards,edges=[]){
  const usable=cards.filter(c=>c&&typeof c.id==='string').slice(0,200),out=[];
  for(const e of edges){
   const a=usable.find(c=>c.id===e.from),b=usable.find(c=>c.id===e.to),r=e.relation;
   if(!a||!b||!r||r.version!==1||r.source!=='user'||!['pending','confirmed'].includes(r.status))continue;
   const names={related:'关联',similar:'相似',different:'差异',complementary:'互补',conflicting:'冲突',custom:text(r.customLabel)};
   const name=names[r.kind];if(!name)continue;
   out.push({key:JSON.stringify(['relation',a.id,b.id,r.kind,r.customLabel,r.evidence,r.status]),ids:[a.id,b.id],title:'回看这组材料的关系',text:'你曾将这两张标为“'+name+'”'+(r.status==='confirmed'?'。':'，目前仍待确认。'),basis:'依据：你保存的关系标注'+(text(r.evidence)?' · '+text(r.evidence).slice(0,140):'；尚未填写关系依据'),cards:[{id:a.id,title:title(a),source:source(a)},{id:b.id,title:title(b),source:source(b)}]});
  }
  for(let i=0;i<usable.length;i++)for(let j=i+1;j<usable.length;j++){
   const a=usable[i],b=usable[j],common=tags(a).filter(t=>tags(b).includes(t));if(!common.length)continue;
   out.push({key:JSON.stringify(['tags',a.id,b.id,common]),ids:[a.id,b.id],title:'这两张可以一起看看',text:'两张卡片都带有“'+common[0].slice(0,35)+'”标签，可以对照已有备注。',basis:'依据：卡片中保存的相同标签。标签不等于已验证的视觉相似性。',cards:[{id:a.id,title:title(a),source:source(a)},{id:b.id,title:title(b),source:source(b)}]});
  }
  for(const c of usable){
   if(c.type!=='source'||source(c)||c.subtype==='ai-excerpt'||c.subtype==='ai-conversation')continue;
   out.push({key:JSON.stringify(['source',c.id,title(c)]),ids:[c.id],title:'为这张材料留一个出处',text:'“'+title(c)+'”还没有来源链接，之后回看时可以补充。',basis:'依据：这张材料当前保存的来源链接为空；本机文件也可以保留文件名作为出处。',cards:[{id:c.id,title:title(c),source:''}]});
  }
  return out;
 }
 root.CompanionRules={candidates};
 if(typeof module==='object')module.exports=root.CompanionRules;
})(typeof window==='object'?window:globalThis);

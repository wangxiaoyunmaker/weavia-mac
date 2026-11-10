/* A one-way native -> local canvas receiver. Never installed in external pages. */
(()=>{
 const cap=600000;
 let domDrop=null;
 const clean=value=>String(value||'').slice(0,cap);
 function web(value,base){if(typeof value!=='string'||!value.trim())return '';try{const u=new URL(value.trim(),base||undefined);return /^https?:$/.test(u.protocol)&&!u.username&&!u.password?u.href:''}catch{return ''}}
 function bitmap(value){return /^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$/.test(value)&&value.length<=2800000?value:''}
 function parse(input){
  const source=web(input.sourceUrl), title=clean(input.title).slice(0,300), text=clean(input.text).trim();
  const template=document.createElement('template');template.innerHTML=clean(input.html);
  const img=template.content.querySelector('img'),link=template.content.querySelector('a[href]');
  const image=bitmap(input.image||'')||web(input.image,source)||bitmap(img?.getAttribute('src')||'')||web(img?.getAttribute('src'),source);
  const url=web(input.url,source)||web(link?.getAttribute('href'),source)||web(text);
  if(image)return {title:(title||img?.getAttribute('alt')||'网页图片').slice(0,300),text:source||url||image,url:source||url||image,image,kind:'image'};
  if(url)return {title:(title||link?.textContent||text||url).slice(0,300),text:url,url,image:'',kind:'link'};
  if(text)return {title:title||text.slice(0,50),text:text.slice(0,20000),url:source,image:'',kind:'text'};
  throw Error('该内容没有提供可用图片或链接。可拖动网页里的原图/链接，或保存当前来源链接。');
 }
 function project(){return canvasStorageKey;}
 function geometry(){
  const shell=$('#search-shell'),workspace=$('#workspace');
  const visible=!!shell&&!workspace.hidden&&getComputedStyle(workspace).display!=='none';
  if(!visible)return {visible:false,project:project()};
  const r=shell.getBoundingClientRect(),w=innerWidth,h=innerHeight;
  const width=Math.min(640,Math.max(280,w-32)),top=r.bottom+10;
  const left=Math.max(16,Math.min(w-width-16,r.left+r.width/2-width/2));
  return {visible:true,obscured:!!document.querySelector('dialog[open]'),project:project(),x:left/w,y:top/h,width:width/w,height:Math.max(0,Math.min(470,h*.58,h-top-90))/h};
 }
 function prepare(){closeSources();$('#result-panel').hidden=true;$('#query').blur();return geometry()}
 function receive(input){
  try{
   if($('#workspace').hidden||input.project!==project())throw Error('项目已经切换，未加入其他画布。请在当前项目重新拖入。');
   if(document.querySelector('dialog[open]'))throw Error('请先关闭编辑窗口，再拖入画布。');
   const x=Number(input.x),y=Number(input.y),positioned=Number.isFinite(x)&&Number.isFinite(y);
   if(positioned){const target=document.elementFromPoint(x*innerWidth,y*innerHeight);if(!target||target.closest('#sidebar,.top-controls,.toolbar,.zoom,dialog,#result-panel,#collapsed-project'))throw Error('请放到画布空白处或卡片之间。');}
   const value=parse(input);
   if(input.requireImage&&value.kind!=='image')throw Error('图片文件不可读取，且没有可用原图链接。未用网页链接代替图片；可拖上方来源卡。');
   const existing=state.cards.find(c=>value.kind==='image'?c.image===value.image&&c.url===value.url:value.kind==='link'?c.url===value.url&&!c.image:false);
   if(existing){selected=existing.id;renderCards();notify('画布中已有这份材料，未重复添加');return {ok:true,duplicate:true,cardId:existing.id};}
   const old=state.cards;
   const card={id:crypto.randomUUID(),type:'source',title:value.title,text:value.text,url:value.url,image:value.image,preview:value.image,tags:[],addedBy:'personal',
    x:((positioned?x*innerWidth:300)-pan.x)/zoom,y:((positioned?y*innerHeight:innerHeight*.72)-pan.y)/zoom,
    time:new Date().toLocaleTimeString('zh-CN',{hour:'2-digit',minute:'2-digit'}),
    provenance:{kind:'manual_web_drop',sourceLabel:value.kind==='image'?'网页图片':value.kind==='link'?'网页链接':'网页摘录',url:web(input.sourceUrl)||value.url,capturedAt:new Date().toISOString(),excerpt:value.text,imageUrl:web(value.image),imageStorage:value.image.startsWith('data:')?'local':value.image?'remote-reference':'none'}};
   prepareResource(card);prepareCardTags(card);state.cards=old.concat([card]);
   try{persistCanvasSnapshot(state)}catch(error){state.cards=old;throw error}
   selected=card.id;renderCards();renderSide();notify(value.kind==='image'?'图片已放入画布'+(card.provenance.imageStorage==='remote-reference'?'，保留来源；显示需要原站图片可访问':'，仅保存在本机'):'材料已放入画布，来源已保留');
   return {ok:true,cardId:card.id};
  }catch(error){notify(error.message||'拖入失败，原画布未改变');return {ok:false,error:error.message||'拖入失败'};}
 }
 // Prevent browser default drop navigation. Native ArkUI reads the user's drop only.
 document.addEventListener('dragover',e=>{if(globalThis.cuppaNativeDrop){e.preventDefault();if(e.dataTransfer)e.dataTransfer.dropEffect='copy';}},true);
 document.addEventListener('drop',e=>{if(globalThis.cuppaNativeDrop){e.preventDefault();e.stopPropagation();const d=e.dataTransfer;if(d)domDrop={at:Date.now(),project:project(),html:clean(d.getData('text/html')),text:clean(d.getData('text/plain')),url:clean(d.getData('text/uri-list')).split(/\r?\n/).find(x=>x.trim()&&!x.startsWith('#'))||''};}},true);
 function beginDrag(){domDrop=null}
 function receiveDOM(input){if(!domDrop||Date.now()-domDrop.at>3000)return {pending:true,ok:false};const data=domDrop;domDrop=null;if(data.project!==input.project)return {ok:false,error:'项目已切换，未加入其他画布。'};return receive({...input,html:data.html,text:data.text,url:data.url});}
 globalThis.cuppaEmbeddedSearch={geometry,prepare,receive,parse,beginDrag,receiveDOM};
})();

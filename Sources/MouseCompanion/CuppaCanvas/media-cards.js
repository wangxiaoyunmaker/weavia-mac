/* Local originals are copied by the Mac picker. The page only receives IDs and thumbnails. */
(function(root){
 'use strict';
 const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
 function webURL(value){if(typeof value!=='string'||/[\s\u0000-\u001f\u007f]/.test(value.trim()))return '';try{const u=new URL(value.trim());return ['https:','http:'].includes(u.protocol)&&u.hostname&&!u.username&&!u.password?value.trim():''}catch{return ''}}
 function thumbnailURL(value){try{const u=new URL(value);return u.protocol==='weavia-file:'&&u.host==='preview'&&!u.username&&!u.password&&!u.hash&&u.pathname.endsWith('.png')&&uuid.test(u.pathname.slice(1,-4))&&[...u.searchParams.keys()].length===1&&!!u.searchParams.get('project')?u.href:''}catch{return ''}}
 function supported(c){return ['image','pdf'].includes(c?.type)&&c.attachment?.version===1&&c.attachment.kind===c.type&&uuid.test(c.attachment.id)}
 function label(c){return c.type==='pdf'?'PDF · 论文':'图片'}
 function size(bytes){return Number.isFinite(bytes)?bytes>=1048576?(bytes/1048576).toFixed(1)+' MB':Math.ceil(bytes/1024)+' KB':''}
 function validate(input,kind,attachment){
  if(!['image','pdf'].includes(kind)||!supported({type:kind,attachment}))throw Error('请先选择有效的本机原件。');
  for(const [key,max] of Object.entries({title:160,sourceURL:4096,note:20000}))if(typeof input[key]!=='string'||input[key].length>max)throw Error('字段过长，请检查后重试。');
  if(!input.title.trim())throw Error('请填写卡片标题。');
  if(input.sourceURL.trim()&&!webURL(input.sourceURL))throw Error('来源链接需要完整的 http:// 或 https:// 地址。');
  const page=String(input.page??'').trim();if(kind==='pdf'&&page&&(!/^\d+$/.test(page)||Number(page)<1||Number(page)>(attachment.pageCount||0)))throw Error('页码需要在 PDF 的实际页数范围内。');
  return {title:input.title.trim(),url:input.sourceURL.trim(),text:input.note,attachment:{...attachment},...(kind==='pdf'?{pageNumber:page?Number(page):1}:{})};
 }
 function markup(c){
  const a=c.attachment||{},thumb=thumbnailURL(a.previewURL),source=webURL(c.url||c.provenance?.url);
  return `<article class="card media-card ${c.type==='pdf'?'pdf-card':'image-card'} ${typeof selected!=='undefined'&&selected===c.id?'selected':''}" data-id="${esc(c.id)}" data-type="${esc(c.type)}" style="left:${c.x}px;top:${c.y}px"><header><span>${label(c)}</span><button data-delete="${esc(c.id)}" aria-label="删除卡片">×</button></header><div class="media-preview resource-drag" title="拖动卡片；双击查看详情">${thumb?`<img src="${esc(thumb)}" alt="${esc(c.title)}" draggable="false">`:`<div class="media-placeholder">${c.type==='pdf'?'PDF':'图片'}<small>原件预览暂不可用</small></div>`}</div><h3 class="resource-drag">${esc(c.title)}</h3><p class="media-metadata resource-drag">${esc([a.filename,size(a.byteCount),a.pageCount?a.pageCount+' 页':'',c.pageNumber?'定位第 '+c.pageNumber+' 页':''].filter(Boolean).join(' · '))}</p>${c.text?`<p class="media-note resource-drag">${esc(c.text)}</p>`:''}<div class="media-tags" data-card-tags>${typeof cardTagsMarkup==='function'?cardTagsMarkup(c,true):''}</div><footer class="media-actions"><button data-media-preview ${supported(c)?'':'disabled'}>${c.type==='pdf'?'阅读 PDF':'查看原图'}</button>${source?`<a href="${esc(source)}" target="_blank" rel="noopener noreferrer">来源 ↗</a>`:''}<button data-media-edit ${supported(c)?'':'disabled'}>编辑信息</button></footer></article>`;
 }
 function preview(c){if(!supported(c)){notify('此原件数据暂不支持，未修改原数据。');return}root.mouseCompanionMac?.dismissSelection?.();if(root.mouseCompanionMac?.previewAttachment)root.mouseCompanionMac.previewAttachment(c.attachment.id,c.type==='pdf'?c.pageNumber||1:undefined);else notify('本机原件需要在 WEAVIA Mac 中打开。')}
 function bind(el,c){el.onclick=e=>{if(e.target.closest('button,a,[data-card-tag]'))return;if(picking){useCard(c);return}selected=c.id;document.querySelectorAll('.card').forEach(x=>x.classList.toggle('selected',x===el))};el.querySelector('[data-media-preview]').onclick=e=>{e.stopPropagation();if(!picking&&!canvasAction&&!cardDragActive)preview(c)};el.querySelector('[data-media-edit]').onclick=()=>editor(c.type,c);el.querySelectorAll('a').forEach(a=>a.addEventListener('click',e=>{if(picking||canvasAction||cardDragActive)e.preventDefault()}))}
 function choose(){modal('添加本机原件','<p>原件只复制到当前项目的本机目录，不上传。支持 50 MB 以内的图片和 PDF。</p><div class="media-choose"><button id="choose-image-card">图片</button><button id="choose-pdf-card">PDF · 论文</button><button id="choose-text-file">文字等其他文件</button></div>');for(const kind of ['image','pdf'])document.getElementById('choose-'+kind+'-card').onclick=()=>{document.getElementById('dialog').close();editor(kind)};document.getElementById('choose-text-file').onclick=()=>{document.getElementById('dialog').close();const input=document.getElementById('file-input');input.dataset.legacyPicker='1';input.click();delete input.dataset.legacyPicker}}
 function editor(kind,card=null){
  if(card&&!supported(card)){notify('此原件版本暂不支持编辑，原数据未修改。');return}
  $('#add-menu').hidden=true;cancelCanvasAction();hideTagTools();root.mouseCompanionMac?.dismissSelection?.();
  const project=new URLSearchParams(location.search).get('project')||'',snapshot=card?JSON.stringify(card):null,dialog=$('#dialog');
  let attachment=card?.attachment||null,closed=false,busy=false,accepted=false;
  const original={title:card?.title||'',sourceURL:card?.url||card?.provenance?.url||'',note:card?.text||'',page:kind==='pdf'?String(card?.pageNumber||1):''},originalAttachment=attachment?.id;
  modal(card?'编辑'+label({type:kind}):'添加'+label({type:kind}),`<form id="media-form" novalidate><p>保存本机原件，不上传、不自动分析。PDF 可本地阅读，图片保留原始像素。</p><button type="button" id="media-pick">${attachment?'重新选择原件':'选择本机'+(kind==='pdf'?' PDF':'图片')}</button><p id="media-file" role="status">${esc(attachment?.filename||'尚未选择文件')}</p><label>标题<input id="media-title" maxlength="160" required value="${esc(original.title)}"></label><label>来源链接 <span>可选</span><input id="media-source" type="url" maxlength="4096" placeholder="论文网页、DOI 链接或图片来源网页" value="${esc(original.sourceURL)}"></label>${kind==='pdf'?`<label>打开页码 <span>可选，默认第 1 页</span><input id="media-page" type="number" min="1" step="1" value="${esc(original.page)}"></label>`:''}<label>我的备注<textarea id="media-note" maxlength="20000">${esc(original.note)}</textarea></label><p id="media-error" role="alert"></p><div class="media-choose"><button type="submit" id="media-save" class="primary">${card?'保存修改':'加入画布'}</button><button type="button" id="media-cancel">取消</button></div></form>`);
  const read=()=>({title:$('#media-title').value,sourceURL:$('#media-source').value,note:$('#media-note').value,page:$('#media-page')?.value||''});
  const dirty=()=>JSON.stringify(read())!==JSON.stringify(original)||attachment?.id!==originalAttachment;
  const requestClose=e=>{if(accepted)return;if(busy||dirty()){e.preventDefault();e.stopImmediatePropagation();if(busy){$('#media-error').textContent='正在处理，请稍后关闭。';return}if(!confirm('放弃尚未保存的卡片修改？'))return}accepted=true;dialog.close()};
  dialog.addEventListener('cancel',requestClose);$('#dialog-close').addEventListener('click',requestClose,true);$('#media-cancel').onclick=requestClose;
  const onRoute=()=>{if(location.hash!=='#cuppa'){accepted=true;dialog.close()}};window.addEventListener('hashchange',onRoute);
  dialog.addEventListener('close',()=>{closed=true;dialog.removeEventListener('cancel',requestClose);$('#dialog-close').removeEventListener('click',requestClose,true);window.removeEventListener('hashchange',onRoute)},{once:true});
  $('#media-pick').onclick=async()=>{
   if(busy)return;if(!root.mouseCompanionMac?.importAttachment){$('#media-error').textContent='请在 WEAVIA Mac 中选择本机原件。';return}
   busy=true;$('#media-pick').disabled=true;$('#media-save').disabled=true;$('#media-error').textContent='';
   try{const result=await root.mouseCompanionMac.importAttachment(kind);if(closed||project!==(new URLSearchParams(location.search).get('project')||''))return;if(!result.cancelled){attachment=result.attachment;if(!supported({type:kind,attachment}))throw Error('本机原件返回数据无效。');$('#media-file').textContent=attachment.filename+' · '+size(attachment.byteCount);if(!$('#media-title').value.trim())$('#media-title').value=attachment.filename;}}
   catch(error){if(!closed)$('#media-error').textContent=error.message}
   finally{busy=false;if(!closed){$('#media-pick').disabled=false;$('#media-save').disabled=false}}
  };
  $('#media-form').onsubmit=async e=>{
   e.preventDefault();if(busy||e.isComposing)return;busy=true;$('#media-save').disabled=true;$('#media-error').textContent='';
   try{
    const values=validate(read(),kind,attachment),existing=card?state.cards.find(c=>c.id===card.id):null;
    if(project!==(new URLSearchParams(location.search).get('project')||'')||card&&JSON.stringify(existing)!==snapshot)throw Error('项目或原卡片已变化，未覆盖原数据。');
    const offset=state.cards.length%5*28,base=existing||{id:crypto.randomUUID(),type:kind,addedBy:'personal',tags:[],x:(($('#sidebar').hidden?100:285)+offset-pan.x)/zoom,y:(165+offset-pan.y)/zoom,time:new Date().toLocaleTimeString('zh-CN',{hour:'2-digit',minute:'2-digit'})};
    const updated={...base,...values,preview:thumbnailURL(attachment.previewURL),provenance:{...base.provenance,sourceLabel:'本机'+(kind==='pdf'?' PDF':'图片'),url:values.url,originalFilename:attachment.filename,importedAt:attachment.importedAt}};
    if(root.mouseCompanionMac?.commitCanvasCard)await root.mouseCompanionMac.commitCanvasCard(updated,snapshot,project);
    else {const next={...state,cards:card?state.cards.map(c=>c.id===card.id?updated:c):[...state.cards,updated]};persistCanvasSnapshot(next);state=next}
    selected=updated.id;renderCards();renderSide();accepted=true;dialog.close();notify(card?'原件卡片信息已保存':'原件卡片已加入画布');
   }catch(error){if(!closed)$('#media-error').textContent=error.message||'保存失败，草稿仍保留。'}
   finally{busy=false;if(!closed)$('#media-save').disabled=false}
  };
  $('#media-title').focus();
 }
 root.CanvasMediaCards=Object.freeze({webURL,thumbnailURL,supported,label,size,validate,markup,bind,preview,editor,choose});
 if(typeof module==='object')module.exports=root.CanvasMediaCards;
})(globalThis);

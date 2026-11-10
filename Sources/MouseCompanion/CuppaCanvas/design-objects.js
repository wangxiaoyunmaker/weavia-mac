/* Manual references, not a design-tool integration. No fetching, embeds or automatic opening. */
(function(root){
 'use strict';
 const limits={title:160,sourceApp:100,originalUrl:4096,location:1000,note:20000};
 function webUrl(value){
  if(typeof value!=='string')return '';
  const raw=value.trim();
  if(!/^https?:\/\//i.test(raw)||/[\s\u0000-\u001f\u007f]/.test(raw))return '';
  try{const u=new URL(raw);return u.hostname&&!u.username&&!u.password?raw:''}catch{return ''}
 }
 function fields(card={}){
  const d=card.designObject&&typeof card.designObject==='object'&&!Array.isArray(card.designObject)?card.designObject:{};
  const str=x=>typeof x==='string'?x:'';
  return {title:str(card.title),sourceApp:str(d.sourceApp??card.sourceApp),originalUrl:typeof d.originalUrl==='string'?d.originalUrl:(str(card.url)||(webUrl(card.text)||'')),location:str(d.location??card.objectLocation),note:str(card.text)};
 }
 function supported(card){return !card.designObject||(typeof card.designObject==='object'&&!Array.isArray(card.designObject)&&card.designObject.version===1)}
 function validate(input){
  for(const key of Object.keys(limits))if(typeof input[key]!=='string'||input[key].length>limits[key])throw Error('字段过长或格式不正确，请检查后重试。');
  if(!input.title.trim())throw Error('请填写对象名称。');
  if(!input.sourceApp.trim())throw Error('请填写来源应用。');
  if(input.originalUrl.trim()&&!webUrl(input.originalUrl))throw Error('请填写完整的 http:// 或 https:// 链接，不支持本地路径、自定义协议或带账号密码的链接。');
  return {...input,title:input.title.trim(),sourceApp:input.sourceApp.trim(),originalUrl:input.originalUrl.trim(),location:input.location.trim()};
 }
 function update(card,input,now){
  if(!supported(card))throw Error('此设计对象的数据版本暂不支持编辑，原数据未修改。');
  const f=validate(input),old=card.designObject||{};
  return {...card,title:f.title,text:f.note,designObject:{...old,version:1,sourceApp:f.sourceApp,originalUrl:f.originalUrl,location:f.location,createdAt:old.createdAt||now,updatedAt:now}};
 }
 root.DesignObjects={webUrl,fields,supported,validate,update,limits};
 if(typeof module==='object')module.exports=root.DesignObjects;
})(typeof window==='object'?window:globalThis);

function designSearchText(c){const f=DesignObjects.fields(c);return [f.sourceApp,f.originalUrl,f.location].join(' ')}
function designMarkup(c){
 const f=DesignObjects.fields(c),url=DesignObjects.webUrl(f.originalUrl),supported=DesignObjects.supported(c);
 const host=url?new URL(url).host:'';
 return `<article class="card design-object-card ${selected===c.id?'selected':''} ${zoom<.65?'compact':''}" data-id="${esc(c.id)}" data-type="design" style="left:${c.x}px;top:${c.y}px">
 <header><span>◇ 设计对象</span><button data-delete="${esc(c.id)}" title="删除卡片" aria-label="删除设计对象卡片">×</button></header>
 <div class="design-object-heading"><span class="design-app">${esc(f.sourceApp||'来源应用未填写')}</span><h3>${esc(f.title||'未命名设计对象')}</h3></div>
 ${c.image?`<img class="file-preview" src="${esc(c.image)}" alt="${esc(f.title)}">`:''}
 <div class="design-object-details"><div class="design-location"><span>对象位置</span><p>${esc(f.location||'未填写，可补充页面 / Frame / 图层位置')}</p></div>
 ${f.note?`<div class="body">${esc(f.note)}</div>`:''}
 <p class="design-link-label" title="${esc(f.originalUrl)}">${esc(url?host:f.originalUrl?'链接格式暂不支持打开':'尚未添加原对象链接')}</p></div>
 <div class="design-reference-tags" data-card-tags ${c.tags?.length?'':'hidden'}>${cardTagsMarkup(c,true)}</div>
 <footer class="design-object-actions">${url?`<a class="design-open" href="${esc(url)}" target="_blank" rel="noopener noreferrer" aria-label="打开原对象 ${esc(f.title)}">打开原对象 ↗</a>`:'<span class="design-unlinked">待补充链接</span>'}<button data-design-edit ${supported?'':'disabled'}>${supported?'编辑信息':'暂不支持编辑'}</button></footer></article>`;
}
function bindDesign(el,c){
 el.onclick=e=>{if(e.target.closest('button,a,[data-card-tag]'))return;if(picking){useCard(c);return}selected=c.id;$$('.card').forEach(x=>x.classList.toggle('selected',x===el))};
 el.querySelector('[data-design-edit]').onclick=()=>designEditor(c);
 el.querySelector('.design-open')?.addEventListener('click',e=>{if(picking||canvasAction){e.preventDefault();return}if(!DesignObjects.webUrl(e.currentTarget.getAttribute('href')))e.preventDefault()});
}
const designEditorDrafts=new Map();
function designEditor(card=null){
 if(card&&!DesignObjects.supported(card)){notify('此设计对象的数据版本暂不支持编辑，原数据未修改。');return}
 $('#add-menu').hidden=true;cancelCanvasAction();hideTagTools();
 const key=card?.id||'new',cached=designEditorDrafts.get(key),original=DesignObjects.fields(card||{}),values=cached?.values||original;
 let storageAtOpen;try{storageAtOpen=cached?cached.storageAtOpen:localStorage.getItem(canvasStorageKey)}catch{storageAtOpen=undefined}
 const snapshot=cached?.snapshot??JSON.stringify(card),dialog=$('#dialog');
 modal(card?'编辑设计对象':'添加设计对象',`<form id="design-object-form" novalidate>
 <p class="design-editor-intro">将原设计文件留在当前项目。只记录你填写的信息，不会读取或同步设计软件。</p>
 <label>对象名称<input id="design-title" maxlength="160" required placeholder="例如：文化节主视觉" value="${esc(values.title)}"></label>
 <div class="design-editor-row"><label>来源应用<input id="design-app" maxlength="100" required placeholder="例如：Figma、即时设计" value="${esc(values.sourceApp)}"></label><label>对象位置 <span>可选</span><input id="design-location" maxlength="1000" placeholder="页面 / Frame / 图层名称" value="${esc(values.location)}"></label></div>
 <label>原对象链接 <span>可稍后添加</span><input id="design-url" type="url" maxlength="4096" placeholder="https://…" value="${esc(values.originalUrl)}" autocomplete="off" spellcheck="false"></label>
 <p class="design-field-hint">使用设计软件的「复制对象链接」保留定位参数。位置文字仅作记录，不会自动转换为跳转位置。鸿蒙内先打开探索面板，可再选择「外部打开」。</p>
 <label>设计说明 <span>可选</span><textarea id="design-note" maxlength="20000" placeholder="当前问题、设计说明或下一步想法">${esc(values.note)}</textarea></label>
 <p id="design-error" role="alert"></p><div class="design-form-actions"><button id="design-save" class="primary" type="submit">${card?'保存修改':'加入画布'}</button><button id="design-cancel" type="button">取消</button></div>
 <div id="design-discard" hidden role="alert"><p>还有未保存的修改，是否放弃？</p><button id="design-keep" type="button">继续编辑</button><button id="design-drop" type="button">放弃修改</button></div></form>`);
 dialog.classList.add('design-editor-dialog');
 const read=()=>({title:$('#design-title').value,sourceApp:$('#design-app').value,originalUrl:$('#design-url').value,location:$('#design-location').value,note:$('#design-note').value});
 const dirty=()=>JSON.stringify(read())!==JSON.stringify(original);
 let acceptedClose=false,submitting=false;
 const finish=()=>{acceptedClose=true;designEditorDrafts.delete(key);dialog.close()};
 const requestClose=e=>{if(acceptedClose)return;e?.preventDefault();e?.stopImmediatePropagation();if(dirty()){$('#design-discard').hidden=false;$('#design-keep').focus()}else finish()};
 const closeButton=e=>requestClose(e);
 const preserve=()=>{if(location.hash==='#cuppa')return;designEditorDrafts.set(key,{values:read(),storageAtOpen,snapshot});acceptedClose=true;dialog.close()};
 const keyboard=e=>{if(!dialog.open)return;if(e.key==='Escape'){requestClose(e);return}e.stopPropagation()};
 dialog.addEventListener('cancel',requestClose);dialog.addEventListener('keydown',keyboard);$('#dialog-close').addEventListener('click',closeButton,true);window.addEventListener('hashchange',preserve);
 dialog.addEventListener('close',()=>{dialog.classList.remove('design-editor-dialog');dialog.removeEventListener('cancel',requestClose);dialog.removeEventListener('keydown',keyboard);$('#dialog-close').removeEventListener('click',closeButton,true);window.removeEventListener('hashchange',preserve);if(location.hash==='#cuppa'){if(card)cardElement(card.id)?.querySelector('[data-design-edit]')?.focus();else $('#add-tool').focus()}},{once:true});
 $('#design-cancel').onclick=requestClose;$('#design-keep').onclick=()=>{$('#design-discard').hidden=true;$('#design-note').focus()};$('#design-drop').onclick=finish;
 $('#design-object-form').onsubmit=e=>{
  e.preventDefault();if(submitting||e.isComposing)return;submitting=true;$('#design-save').disabled=true;$('#design-error').textContent='';
  try{
   const input=DesignObjects.validate(read());
   if(storageAtOpen===undefined)throw Error('无法读取本机画布存储。草稿仍保留，请检查存储权限。');
   if(localStorage.getItem(canvasStorageKey)!==storageAtOpen)throw Error('画布已在别处更新，未覆盖原数据。请保留草稿并重新打开画布。');
   const existing=card?state.cards.find(c=>c.id===card.id):null;
   if(card&&JSON.stringify(existing)!==snapshot)throw Error('原卡片已变化，未覆盖原数据。请重新打开编辑。');
   const offset=state.cards.length%5*28;
   const base=existing||{id:crypto.randomUUID(),type:'design',addedBy:'personal',tags:[],x:(($('#sidebar').hidden?100:285)+offset-pan.x)/zoom,y:(165+offset-pan.y)/zoom,time:new Date().toLocaleTimeString('zh-CN',{hour:'2-digit',minute:'2-digit'})};
   const updated=DesignObjects.update(base,input,new Date().toISOString());
   const next={...state,cards:card?state.cards.map(c=>c.id===card.id?updated:c):[...state.cards,updated]};
   persistCanvasSnapshot(next);
   state=next;selected=updated.id;renderCards();renderSide();finish();notify(card?'设计对象信息已保存':'设计对象已加入当前画布');
  }catch(error){$('#design-error').textContent=(error.name==='QuotaExceededError'?'本机存储空间不足，草稿仍保留。':error.name==='SecurityError'?'本机存储不可用，草稿仍保留。':error.message)||'保存失败，草稿仍保留。'}
  finally{submitting=false;if($('#design-save'))$('#design-save').disabled=false}
 };
 $('#design-title').focus();
}

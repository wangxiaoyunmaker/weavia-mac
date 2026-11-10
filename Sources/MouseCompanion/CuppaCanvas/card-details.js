/* Read-only card inspection. Opening and closing never write the canvas snapshot. */
(function(root){
 'use strict';
 const escape=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 function webURL(value){try{const u=new URL(value);return ['http:','https:'].includes(u.protocol)&&!u.username&&!u.password?u.href:''}catch{return ''}}
 function imageURL(value){
  if(typeof value!=='string')return '';
  if(webURL(value)||/^data:image\/(png|jpeg|jpg|gif|webp);base64,[A-Za-z0-9+/=\r\n]+$/.test(value)||/^blob:/.test(value)||/^assets\/[\w./-]+$/.test(value))return value;
  try{const u=new URL(value);return u.protocol==='weavia-asset:'&&u.host==='material'&&!u.username&&!u.password&&!u.hash&&/^\/[0-9a-f-]{36}\.png$/i.test(u.pathname)&&u.searchParams.get('project')?u.href:''}catch{return ''}
 }
 const section=(label,text)=>text?`<section><h3>${escape(label)}</h3><div class="card-detail-text">${escape(text)}</div></section>`:'';
 function blockMarkup(b){
  if(b.type==='table')return `<div class="card-detail-table"><table><tbody>${(b.cells||[]).map(row=>`<tr>${row.map(cell=>`<td>${escape(cell)}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;
  if(b.type==='doodle')return `<svg viewBox="0 0 216 120" role="img" aria-label="已保存涂鸦">${(b.strokes||[]).map(s=>`<polyline points="${(s.points||[]).filter(p=>Array.isArray(p)&&p.length===2&&p.every(Number.isFinite)).map(p=>p.join(',')).join(' ')}" fill="none" stroke="currentColor" stroke-width="1.25" stroke-linecap="round" stroke-linejoin="round"/>`).join('')}</svg>`;
  return section('文字',b.text);
 }
 function markup(c){
  const design=c.type==='design'?(c.designObject||{}):{},url=webURL(design.originalUrl||c.url||c.provenance?.url);
  const privateImage=root.CuppaTrayImageAssets?.isPrivate(c),image=imageURL(privateImage?root.CuppaTrayImageAssets.source(c):c.image||c.preview);
  const fullText=c.ai?.originalText||c.provenance?.excerpt||c.text||'';
  const body=c.type==='claim'&&Array.isArray(c.blocks)?c.blocks.map(blockMarkup).join(''):section(c.ai?'已保存对话原文':'完整内容',fullText)+(c.text&&c.text!==fullText?section('卡片文字',c.text):'');
  return `<h2>${escape(c.title||'未命名卡片')}</h2>${image?`<img class="card-detail-image" src="${escape(image)}" alt="${escape(c.title||'素材图片')}" draggable="false">`:privateImage?section('图片',root.CuppaTrayImageAssets.error(c)):''}${section('原问题',c.ai?.question)}${body}${section('来源',design.sourceApp||c.provenance?.sourceLabel||c.ai?.provider)}${section('对象位置',design.location)}${section('标签',(c.tags||[]).map(t=>typeof t==='string'?t:t.label||'').filter(Boolean).join(' · '))}${section('我的备注',c.userNote)}${section('采集时间',c.provenance?.capturedAt)}${url?`<p><a href="${escape(url)}" target="_blank" rel="noopener noreferrer">打开原来源 ↗</a></p>`:''}${(c.companionCapture?.acceptedSuggestions||[]).map(s=>section('已采纳建议（不是来源事实）',[s.label,s.reason].filter(Boolean).join('\n'))).join('')}`;
 }
 function open(c){
  if(!c)return false;
  const nativeId=c.nativeMaterialId||c.provenance?.nativeMaterialId;
  if(nativeId&&root.mouseCompanionMac?.openMaterial){root.mouseCompanionMac.openMaterial(nativeId);return true}
  let dialog=document.getElementById('card-detail-dialog');
  if(!dialog){dialog=document.createElement('dialog');dialog.id='card-detail-dialog';dialog.setAttribute('aria-label','卡片详情');document.body.append(dialog);dialog.addEventListener('click',e=>{if(e.target===dialog)dialog.close()});}
  if(dialog.open)dialog.close();
  dialog.innerHTML=`<header><strong>卡片详情</strong><button type="button" data-detail-close aria-label="关闭卡片详情">关闭</button></header><div class="card-detail-body">${markup(c)}</div><footer><button type="button" data-detail-edit>${c.type==='claim'?'返回编辑想法':'编辑卡片信息'}</button></footer>`;
  dialog.querySelector('[data-detail-close]').onclick=()=>dialog.close();
  dialog.querySelector('[data-detail-edit]').onclick=()=>{dialog.close();if(c.type==='source')resourceEditor(c);else if(c.type==='design')designEditor(c);else if(c.type==='claim')cardElement(c.id)?.querySelector('[contenteditable]')?.focus()};
  dialog.showModal();dialog.querySelector('[data-detail-close]').focus();return true;
 }
 function bind(el,c){
  if(el.dataset.detailBound)return;el.dataset.detailBound='1';
  const button=document.createElement('button');button.type='button';button.className='card-detail-open';button.textContent='查看详情';button.setAttribute('aria-label','查看卡片详情：'+(c.title||'未命名卡片'));
  (el.querySelector('.resource-footer,.ai-excerpt-footer,.claim-meta,.design-object-actions')||el).append(button);
  const unavailable=()=>typeof picking!=='undefined'&&picking||typeof canvasAction!=='undefined'&&canvasAction||typeof cardDragActive!=='undefined'&&cardDragActive;
  button.addEventListener('click',e=>{e.preventDefault();e.stopImmediatePropagation();if(!unavailable())open(c)});
  let gesture=null,dragged=false;
  el.addEventListener('pointerdown',e=>{gesture={x:e.clientX,y:e.clientY};dragged=false},true);
  el.addEventListener('pointermove',e=>{if(gesture&&Math.hypot(e.clientX-gesture.x,e.clientY-gesture.y)>=1)dragged=true},true);
  el.addEventListener('pointercancel',()=>{dragged=true;gesture=null},true);
  el.addEventListener('dblclick',e=>{if(e.target.closest('button,a,input,textarea,select,[contenteditable],svg,[data-card-tag]'))return;e.preventDefault();e.stopImmediatePropagation();if(!unavailable()&&!dragged)open(c)},true);
 }
 // Capture Escape before canvas shortcuts can clear the selected cards instead.
 root.document?.addEventListener('keydown',e=>{const dialog=document.getElementById('card-detail-dialog');if(dialog?.open&&e.key==='Escape'){e.preventDefault();e.stopImmediatePropagation();dialog.close()}},true);
 root.CuppaCardDetails=Object.freeze({open,bind,markup,webURL,imageURL});
 if(typeof module==='object')module.exports=root.CuppaCardDetails;
})(globalThis);

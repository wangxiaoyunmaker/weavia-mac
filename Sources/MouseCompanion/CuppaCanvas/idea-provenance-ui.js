/* No model calls, file access or project-memory writes. */
const ideaEditSessions=new WeakMap(),ideaWriteErrors=new Map();
function ideaSession(c){if(!ideaEditSessions.has(c))ideaEditSessions.set(c,crypto.randomUUID());return ideaEditSessions.get(c)}
function ideaEndEdit(c){ideaEditSessions.delete(c)}
function ideaBadgeMarkup(c){const v=IdeaProvenance.view(c),error=ideaWriteErrors.get(c.id);return `<div class="idea-origin"><span>${esc(v.source)}</span><span class="idea-status ${v.status}">${esc(v.label)}</span></div><div class="idea-review-actions"><button type="button" data-idea-review>来源与确认</button>${error?'<button type="button" data-idea-retry>重试保存</button>':''}</div>${error?'<p class="idea-write-error" role="alert">修改尚未保存，请重试。离开页面可能丢失。</p>':''}`}
function ideaRefresh(c){const el=cardElement(c.id)?.querySelector('.idea-provenance');if(!el)return;el.innerHTML=ideaBadgeMarkup(c);el.querySelector('[data-idea-review]').onclick=()=>ideaReview(c.id);el.querySelector('[data-idea-retry]')?.addEventListener('click',()=>persistClaim(c));}
function ideaBind(el,c){ideaRefresh(c);el.addEventListener('focusout',()=>ideaEndEdit(c));if(!IdeaProvenance.supported(c)){el.querySelectorAll('[contenteditable]').forEach(x=>x.setAttribute('contenteditable','false'));el.querySelectorAll('.claim-insert button,.claim-block-tools button').forEach(x=>x.disabled=true);el.querySelectorAll('.claim-sketch').forEach(x=>x.style.pointerEvents='none')}}
function ideaSaveInline(c){
 try{persistCanvasSnapshot(state);ideaWriteErrors.delete(c.id);return true}
 catch(error){ideaWriteErrors.set(c.id,error.message||'保存失败');return false}
}
function ideaDate(value){if(!value)return '旧记录，时间未记录';const d=new Date(value);return Number.isNaN(d.getTime())?'时间未记录':d.toLocaleString('zh-CN',{timeZone:'Asia/Shanghai',hour12:false})}
function ideaReview(id){
 const card=state.cards.find(c=>c.id===id);if(!card)return;
 ideaEndEdit(card);cancelCanvasAction();hideTagTools();
 const view=IdeaProvenance.view(card),p=card.ideaProvenance,dialog=$('#dialog');
 let storageAtOpen;try{storageAtOpen=localStorage.getItem(canvasStorageKey)}catch{}
 const snapshot=JSON.stringify(card);
 const history=view.supported?p.revisions.slice().reverse().map(r=>`<details class="idea-revision"><summary>版本 ${r.number} · ${esc(({created:r.author==='ai'?'AI 来源导入 / 创建':'用户创建',legacy:'旧卡基线',edited:'用户修改'})[r.action]||'记录')}<time>${esc(ideaDate(r.at))}</time></summary><pre>${esc(IdeaProvenance.plain(r.content)||'（空白想法）')}</pre>${r.content.blocks.filter(b=>b.type==='doodle').map(b=>`<svg class="idea-history-sketch" viewBox="0 0 216 120" role="img" aria-label="此版本涂鸦">${claimSketchMarkup(b)}</svg>`).join('')}</details>`).join(''):'';
 const events=view.supported?p.events.slice().reverse().map(e=>`<li>版本 ${e.revision} · ${esc(({confirmed:'用户明确确认',rejected:'用户选择不采纳',withdrawn:'用户撤回确认 / 不采纳',invalidated:'内容已修改，原确认不再适用'})[e.action]||'状态变化')}<time>${esc(ideaDate(e.at))}</time></li>`).join(''):'';
 modal('想法来源与确认',`<div class="idea-review-panel"><div class="idea-review-heading"><span>${esc(view.source)}</span><strong class="idea-status ${view.status}">${esc(view.label)}</strong></div><h3>${esc(card.title||'未命名想法')}</h3><p class="idea-review-note">确认只表示你认可当前版本，不等于客观事实，也不会自动写入项目记忆。修改文字、表格或涂鸦后，需要重新确认。</p>
 ${view.supported?`<dl class="idea-origin-details"><dt>最初来源</dt><dd>${esc(p.origin.kind==='ai'?'AI':p.origin.kind==='user'?'用户':'未记录')}${p.origin.name?' · '+esc(p.origin.name):''}</dd><dt>卡片创建</dt><dd>${esc(ideaDate(p.origin.createdAt))}</dd><dt>当前版本</dt><dd>${p.revisions.length}</dd></dl>${p.origin.basis==='legacy-metadata'?'<p class="idea-review-note">旧卡只沿用已有作者字段。此前修改与确认没有记录，不作推断；从本次起保留历史。</p>':''}${card.ideaImport?`<p class="idea-review-note">${esc(card.ideaImport.example?'导入的是原型示例，不是真实模型分析。':'由用户从已保存的 AI 回答摘录中提取。')} 来源卡片 ID：${esc(card.ideaImport.cardId||'')}</p>`:''}
 <section class="idea-current"><h4>正在确认的内容</h4><pre>${esc(IdeaProvenance.plain(IdeaProvenance.content(card))||'（空白想法）')}</pre></section>
 <label class="idea-confirm-check"><input id="idea-confirm-check" type="checkbox">我已阅读并认可当前版本</label><div class="idea-decision-actions"><button id="idea-confirm" class="primary" disabled>确认当前版本</button><button id="idea-reject">不采纳</button><button id="idea-withdraw" ${view.status==='pending'?'disabled':''}>撤回标记</button></div>
 <p id="idea-review-error" role="alert">${ideaWriteErrors.has(id)?'当前修改尚未保存，请先关闭并重试保存。':''}</p><h4>内容历史</h4><p class="idea-review-note">同一次连续编辑合并为一个版本；已确认版本和最初内容保持不变。历史只读。</p><div class="idea-history">${history}</div><h4>确认记录</h4>${events?`<ul class="idea-events">${events}</ul>`:'<p class="idea-review-note">尚无明确确认记录。</p>'}`:'<p class="idea-review-note">此卡的来源记录版本或格式暂不支持，已保留原数据。当前不作已确认判断。</p>'}</div>`);
 dialog.classList.add('idea-review-dialog');
 const keydown=e=>{if(e.key!=='Escape')e.stopPropagation()};dialog.addEventListener('keydown',keydown);
 const route=()=>{if(location.hash!=='#cuppa')dialog.close()};window.addEventListener('hashchange',route);
 dialog.addEventListener('close',()=>{dialog.classList.remove('idea-review-dialog');dialog.removeEventListener('keydown',keydown);window.removeEventListener('hashchange',route);if(location.hash==='#cuppa')cardElement(id)?.querySelector('[data-idea-review]')?.focus()},{once:true});
 if(!view.supported)return;
 $('#idea-confirm-check').onchange=()=>$('#idea-confirm').disabled=!$('#idea-confirm-check').checked||ideaWriteErrors.has(id);
 const decide=status=>{
  try{
   if(ideaWriteErrors.has(id))throw Error('当前修改尚未保存，请先关闭并重试保存。');
   if(status==='confirmed'&&!$('#idea-confirm-check').checked)return;
   if(storageAtOpen===undefined)throw Error('无法读取本机存储，未修改确认状态。');
   if(localStorage.getItem(canvasStorageKey)!==storageAtOpen||JSON.stringify(state.cards.find(c=>c.id===id))!==snapshot)throw Error('画布或卡片已变化，未覆盖原数据。请关闭后重新打开；其他窗口有更新时请重新加载画布。');
   const nextCard=IdeaProvenance.decide(card,status,new Date().toISOString()),next={...state,cards:state.cards.map(c=>c.id===id?nextCard:c)};
   persistCanvasSnapshot(next);
   state=next;dialog.close();renderCards();renderSide();notify(status==='confirmed'?'已确认当前版本，未自动写入项目记忆':status==='rejected'?'已标记不采纳，内容与历史仍保留':'已撤回标记，当前版本未确认');
  }catch(error){$('#idea-review-error').textContent=error.name==='QuotaExceededError'?'本机存储空间不足，确认状态未保存。':error.message||'保存失败，确认状态未修改。'}
 };
 $('#idea-confirm').onclick=()=>decide('confirmed');$('#idea-reject').onclick=()=>decide('rejected');$('#idea-withdraw').onclick=()=>decide('pending');
}
window.addEventListener('beforeunload',e=>{if(ideaWriteErrors.size){e.preventDefault();e.returnValue=''}});
function ideaFromExcerpt(source){
 if(source.ai?.mode==='full'){notify('完整对话包含不同作者，请先摘取 AI 回答片段。');return}
 const text=(source.ai?.blocks||[]).map(b=>(b.gapBefore?'［中间内容未选入］\n':'')+String(b.text||'')).join('\n\n');
 if(!text.trim()){notify('此摘录没有可提取的 AI 回答。');return}
 const name=aiProvider(source.ai.provider).name+(source.ai.example?'（原型示例）':'');
 const sourceWidth=cardElement(source.id)?.offsetWidth||260;
 const c=addCard('claim',source.title||'AI 想法',text,{creator:{kind:'agent',name},addedBy:'personal',referenceIds:[source.id],ideaImport:{cardId:source.id,provider:source.ai.provider,url:source.url||'',example:!!source.ai.example},x:source.x+sourceWidth+30,y:source.y});
 locate(c.id);if(!ideaWriteErrors.has(c.id))notify('已提取 AI 想法，当前未确认；原摘录保持不变');
}

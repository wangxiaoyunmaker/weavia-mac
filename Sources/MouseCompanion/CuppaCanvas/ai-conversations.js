const AI_PROVIDERS={chatgpt:{name:'ChatGPT',icon:'assets/ai-providers/chatgpt.svg',url:'https://chatgpt.com/'},doubao:{name:'豆包',icon:'assets/ai-providers/doubao.png',url:'https://www.doubao.com/chat/'},deepseek:{name:'DeepSeek',icon:'assets/ai-providers/deepseek.svg',url:'https://chat.deepseek.com/'},unknown:{name:'来源未填写',badge:'AI',url:''}};
const AI_EXAMPLE_LINKS={chatgpt:'chatgpt.com/c/demo',doubao:'doubao.com/chat/demo',deepseek:'chat.deepseek.com/a/chat/s/demo'};
let aiImportSelection=new Set(),aiImportBlocks=[],aiImportEditing=null,aiPastePosition=null,aiLastPointer=null,aiImportCommitted=false;
function isAiExcerpt(c){return c?.type==='source'&&c.subtype==='ai-excerpt'}
function aiProvider(key){
 if(Object.hasOwn(AI_PROVIDERS,key))return AI_PROVIDERS[key];
 return (state.customAiProviders||[]).find(provider=>provider.id===key)||AI_PROVIDERS.unknown
}
function aiProviderEntries(){
 return [...Object.entries(AI_PROVIDERS),...(state.customAiProviders||[]).map(provider=>[provider.id,provider])]
}
function activeAiProvider(){
 const key=draft().aiProvider;
 return state.mode==='personal'&&!personalImage()&&aiProvider(key).url?key:null
}
function aiProviderBadge(key){const provider=aiProvider(key);return `<span class="ai-provider-badge ${provider.icon?'ai-provider-logo':''}" aria-hidden="true">${provider.icon?`<img src="${provider.icon}" alt="" draggable="false">`:esc(provider.badge)}</span>`}
function aiProviderOptions(key){return aiProviderEntries().map(([id,p])=>`<option value="${esc(id)}" ${id===key?'selected':''}>${esc(p.name)}</option>`).join('')}
function aiClipboardText(plain,html){
 // Inspect HTML in an inert template and emit Markdown. The untrusted fragment
 // is never attached to the live document, executed, or inserted into a card.
 if(!html||html.length>500000||!/<(?:pre|table|ul|ol|h[1-6])\b/i.test(html))return plain;
 const template=document.createElement('template');template.innerHTML=html;
 const convert=node=>{if(node.nodeType===3)return node.nodeValue||'';if(node.nodeType!==1&&node.nodeType!==11)return '';const tag=node.tagName?.toLowerCase();if(['script','style','iframe','object','embed','svg','math','template'].includes(tag))return '';const children=()=>[...node.childNodes].map(convert).join('');
  if(tag==='br')return '\n';if(tag==='pre'){const content=node.textContent||'',length=Math.max(3,...(content.match(/`+/g)||[]).map(run=>run.length+1)),fence='`'.repeat(length);return '\n\n'+fence+'\n'+content+'\n'+fence+'\n\n'}
  if(tag==='table'){const rows=[...node.querySelectorAll('tr')].map(tr=>[...tr.children].filter(cell=>['TD','TH'].includes(cell.tagName)).map(cell=>(cell.textContent||'').trim().replace(/\|/g,'\\|').replace(/\s*\n\s*/g,' ')));if(!rows.length)return '';const columns=Math.max(...rows.map(row=>row.length)),line=row=>'| '+Array.from({length:columns},(_,i)=>row[i]||'').join(' | ')+' |';return '\n\n'+[line(rows[0]),line(Array(columns).fill('---')),...rows.slice(1).map(line)].join('\n')+'\n\n'}
  if(tag==='ul'||tag==='ol')return '\n\n'+[...node.children].filter(child=>child.tagName==='LI').map((child,i)=>(tag==='ol'?(i+1)+'. ':'- ')+convert(child).trim()).join('\n')+'\n\n';
  if(tag==='a'){const url=validWebUrl(node.getAttribute('href')||'');return url?'['+children()+']('+url+')':children()}if(tag==='code')return '`'+children()+'`';if(tag==='strong'||tag==='b')return '**'+children()+'**';if(tag==='img')return node.getAttribute('alt')?'［图片：'+node.getAttribute('alt')+'］':'';if(/^h[1-6]$/.test(tag||''))return '\n\n'+children()+'\n\n';return ['p','div','section','article','blockquote'].includes(tag)?children()+'\n\n':children()};
 return [...template.content.childNodes].map(convert).join('').trim()||plain
}
function personalSearchSources(){
 const builtins=sourceNames.map((name,id)=>({id,name}));
 const sources=[...builtins,...(state.customSearchSources||[])];
 const recent=state.recentSearchSources||[];
 const byId=new Map(sources.map(source=>[source.id,source]));
 return [...new Set([...recent,...byId.keys()])].filter(id=>byId.has(id)).map(id=>byId.get(id))
}
function renderPersonalAiSources(){
 const active=activeAiProvider();
 const collapsed=!!state.externalAiCollapsed;
 const searchRows=personalSearchSources().map(source=>{
  const icon=typeof source.id==='number'?iconSource(source.id):'<span class="ai-provider-badge" aria-hidden="true">⌕</span>';
  const hint=!active&&draft().sources[0]===source.id?'回车直达':'';
  return `<button class="source-row" data-personal-source="${esc(source.id)}">${icon}<span>${esc(source.name)}</span><span class="hint">${hint}</span></button>`
 }).join('');
 const aiRows=aiProviderEntries().filter(([,provider])=>provider.url).map(([id,provider])=>
  `<button class="source-row ${active===id?'chosen':''}" data-ai-provider="${esc(id)}" aria-pressed="${active===id}">${aiProviderBadge(id)}<span>${esc(provider.name)}</span><span class="hint">${active===id?'已选择':'打开对话 ↗'}</span></button>`
 ).join('');
 $('#sources').innerHTML=`
  <div class="source-group-label source-group-header"><span>搜索</span>
   <button id="add-personal-source" type="button" aria-label="添加搜索来源" title="添加搜索来源">＋</button>
  </div>
  <div class="personal-search-list" aria-label="搜索来源">${searchRows}</div>
  <div class="source-group-label source-group-header"><span>外部 AI 对话</span>
   <button id="toggle-external-ai" type="button" aria-controls="external-ai-sources" aria-expanded="${!collapsed}" aria-label="${collapsed?'展开':'收起'}外部 AI 对话" title="${collapsed?'展开':'收起'}外部 AI 对话">${collapsed?'▸':'▾'}</button>
   <button id="add-external-ai" type="button" aria-label="添加外部 AI" title="添加外部 AI">＋</button>
  </div>
  <div id="external-ai-sources" ${collapsed?'hidden':''}>${aiRows}</div>`;
 $('#agent-scope').hidden=true;
 $('#scope-footer').hidden=true;
 $('#add-personal-source').onclick=()=>openSourceEditor(false);
 $('#add-external-ai').onclick=()=>openSourceEditor(true);
 $('#toggle-external-ai').onclick=()=>{
  state.externalAiCollapsed=!collapsed;
  save();
  renderPersonalAiSources();
  $('#toggle-external-ai').focus()
 };
 $$('[data-personal-source]').forEach(button=>{
  button.onclick=()=>{
   const id=button.dataset.personalSource;
   chooseSource(id.startsWith('search-')?id:Number(id))
  }
 });
 $$('[data-ai-provider]').forEach(button=>button.onclick=()=>chooseAiProvider(button.dataset.aiProvider))
}
function openSourceEditor(externalAi){
 const title=externalAi?'添加外部 AI':'添加搜索来源';
 const addressLabel=externalAi?'对话网址':'搜索网址模板';
 const placeholder=externalAi?'https://example.com/chat':'https://example.com/search?q={query}';
 modal(title,`<form id="add-source-form">
  <label>名称<input name="name" required maxlength="40"></label>
  <label>${addressLabel}<input name="address" required maxlength="2048" placeholder="${placeholder}"></label>
  ${externalAi?'':'<p class="source-editor-hint">在搜索词的位置填入 {query}。</p>'}
  <p class="source-editor-error" role="alert"></p>
  <button class="primary" type="submit">添加</button>
 </form>`);
 const form=$('#add-source-form');
 form.onsubmit=event=>{
  event.preventDefault();
  const name=form.elements.name.value.trim();
  const address=form.elements.address.value.trim();
  const url=validWebUrl(externalAi?address:address.replaceAll('{query}','sample'));
  const error=form.querySelector('.source-editor-error');
  if(!name||!url||!/^https?:\/\//i.test(address)){
   error.textContent='请输入名称和有效的 HTTP 或 HTTPS 网址。';
   return
  }
  if(!externalAi&&(!address.includes('{query}')||/^https?:\/\/[^/?#]*\{query\}/i.test(address))){
   error.textContent='请把 {query} 放在网址的搜索词位置。';
   return
  }
  const id=(externalAi?'ai-':'search-')+crypto.randomUUID();
  if(externalAi){
   state.customAiProviders=[...(state.customAiProviders||[]),{id,name,url,badge:'AI'}];
   state.externalAiCollapsed=false
  }else{
   state.customSearchSources=[...(state.customSearchSources||[]),{id,name,template:address}]
  }
  save();
  $('#dialog').close();
  openSources();
  const row=$(externalAi?`[data-ai-provider="${id}"]`:`[data-personal-source="${id}"]`);
  row?.focus();
  row?.scrollIntoView({block:'nearest'})
 }
}
function chooseAiProvider(key){if(!aiProvider(key).url)return;draft().aiProvider=key;draft().refs=draft().refs.filter(r=>r.kind!=='image');state.lastAiProvider=key;save();sync();$('#query').focus();closeSources()}
function syncAiSearchTarget(){const key=activeAiProvider(),p=aiProvider(key);$('#ai-target-wrap').hidden=!key;$('#ai-target').innerHTML=key?`${aiProviderBadge(key)}<span class="ai-target-name">${esc(p.name)}</span><span aria-hidden="true">⌄</span>`:'';$('#ai-target').setAttribute('aria-label',key?'切换 AI 对话平台，当前 '+p.name:'选择 AI 对话平台');$('#search-shell').classList.toggle('ai-target-mode',!!key);$('#submit').classList.toggle('ai-submit',!!key);$('#submit').innerHTML=key?'<span class="ai-submit-label">复制并打开</span><span class="ai-submit-icon" aria-hidden="true">↗</span>':'<svg><use href="#arrow"/></svg>';$('#submit').title=key?'复制提问并打开 '+p.name:'提交搜索';$('#submit').setAttribute('aria-label',$('#submit').title);if(key){$('#query').placeholder='向 '+p.name+' 提问…';$('#query').setAttribute('aria-label','向 '+p.name+' 提问')};$('#ai-target').onclick=()=>$('#source-panel').hidden?openSources():closeSources()}
function copyAiText(text){if(!text)return Promise.resolve(true);try{return navigator.clipboard?.writeText?Promise.resolve(navigator.clipboard.writeText(text)).then(()=>true,()=>false):Promise.resolve(false)}catch{return Promise.resolve(false)}}
function launchAiConversation(){
 const key=activeAiProvider();if(!key)return;const provider=aiProvider(key),question=draft().text.trim(),context={provider:key,threadId:crypto.randomUUID(),title:question.slice(0,60)||provider.name+' 对话',question,url:''};state.aiImportContext=context;save();
 // Start the clipboard operation and open the window in the user's click/Enter
 // gesture. Never pass the prompt in a URL or send it to a model automatically.
 const copied=copyAiText(question);window.open(provider.url,'_blank','noopener,noreferrer');closeSources();$('#query').blur();
 panel(provider.name+' 对话',`<div class="ai-launch-heading">${aiProviderBadge(key)}<span>在外部窗口继续对话</span></div><p id="ai-copy-status" role="status">${question?'正在复制提问…':'已请求打开网站，可在新窗口开始对话。'}</p>${question?`<textarea class="ai-launch-prompt" aria-label="待复制的提问" readonly>${esc(question)}</textarea>`:''}<div class="ai-launch-actions">${question?'<button class="ai-secondary" id="copy-ai-prompt">复制提问</button>':''}<a class="ai-secondary" href="${esc(provider.url)}" target="_blank" rel="noopener noreferrer">打开 ${esc(provider.name)} ↗</a></div><p>在对话窗口粘贴并发送。找到有用的回答后，复制你要保留的部分，再导入画布。</p><button class="primary" id="collect-ai-answer">导入对话摘录</button><p class="ai-launch-footnote">仅复制输入文字；画布引用不会自动上传，外部聊天记录不会自动同步。</p>`);
 const status=$('#ai-copy-status');copied.then(ok=>{if(status.isConnected&&question)status.textContent=ok?'提问已复制，请在外部窗口粘贴并发送。':'未能自动复制。请选中下方提问手动复制，再打开对话。'});const retry=$('#copy-ai-prompt');if(retry)retry.onclick=async()=>{if(await copyAiText(question))notify('提问已复制');else{$('.ai-launch-prompt').focus();$('.ai-launch-prompt').select();notify('请按 ⌘C / Ctrl+C 复制提问')}};$('#collect-ai-answer').onclick=()=>openAiExcerptImporter({context})
}
function parseAiExcerptBlocks(value){
 const lines=String(value||'').replace(/\r\n?/g,'\n').split('\n'),blocks=[];let buffer=[],fence=null;
 const flush=()=>{if(buffer.some(line=>line.trim())){const raw=buffer.join('\n');blocks.push({type:fence?'code':/^\s*(`{3,}|~{3,})/.test(raw)?'code':buffer.length>1&&/^\s*\|?\s*:?-{3,}/.test(buffer[1])?'table':'text',text:raw})}buffer=[]};
 for(const line of lines){const match=line.match(/^\s*(`{3,}|~{3,})/);if(fence){buffer.push(line);if(match&&match[1][0]===fence[0]&&match[1].length>=fence.length){flush();fence=null}continue}if(match){flush();fence=match[1];buffer.push(line)}else if(!line.trim())flush();else buffer.push(line)}flush();return blocks
}
function aiInline(text){return esc(text).replace(/`([^`\n]+)`/g,'<code>$1</code>').replace(/\*\*([^*\n]+)\*\*/g,'<strong>$1</strong>').replace(/\[([^\]\n]+)\]\((https?:\/\/[^\s)]+)\)/g,(all,label,url)=>{const safe=validWebUrl(url.replace(/&amp;/g,'&'));return safe?`<a href="${esc(safe)}" target="_blank" rel="noopener noreferrer">${label}</a>`:all})}
function aiBlockMarkup(block){
 const raw=String(block.text||''),lines=raw.split('\n');if(block.type==='code'){if(/^\s*(`{3,}|~{3,})/.test(lines[0]))lines.shift();if(/^\s*(`{3,}|~{3,})\s*$/.test(lines.at(-1)||''))lines.pop();return `<pre><code>${esc(lines.join('\n'))}</code></pre>`}
 if(block.type==='table'){const row=line=>line.trim().replace(/^\||\|$/g,'').split(/(?<!\\)\|/).map(cell=>cell.replace(/\\\|/g,'|'));const rows=lines.filter((_,i)=>i!==1).map(row);return `<div class="ai-excerpt-table"><table><thead><tr>${(rows.shift()||[]).map(cell=>`<th>${aiInline(cell.trim())}</th>`).join('')}</tr></thead><tbody>${rows.map(cells=>`<tr>${cells.map(cell=>`<td>${aiInline(cell.trim())}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`}
 if(lines.every(line=>/^\s*[-*+]\s+/.test(line)))return '<ul>'+lines.map(line=>'<li>'+aiInline(line.replace(/^\s*[-*+]\s+/,''))+'</li>').join('')+'</ul>';
 if(lines.every(line=>/^\s*\d+[.)、]\s+/.test(line)))return '<ol>'+lines.map(line=>'<li>'+aiInline(line.replace(/^\s*\d+[.)、]\s+/,''))+'</li>').join('')+'</ol>';
 return '<p>'+lines.map(line=>/^#{1,6}\s/.test(line)?'<strong>'+aiInline(line.replace(/^#{1,6}\s+/,''))+'</strong>':aiInline(line)).join('<br>')+'</p>'
}
function aiBlocksMarkup(blocks){return blocks.map(block=>(block.gapBefore?'<div class="ai-excerpt-omitted">［中间内容未选入］</div>':'')+aiBlockMarkup(block)).join('')}
function aiExcerptSummary(text){const blocks=parseAiExcerptBlocks(text),prose=blocks.filter(b=>b.type!=='code').map(b=>({type:'text',text:b.text}));return prose.length?claimSummary({autoTitle:true,blocks:prose}):blocks.length?'代码摘录：'+(String(blocks[0].text).split('\n').slice(1).find(line=>line.trim())?.trim().slice(0,30)||'代码片段'):'对话摘录'}
function prepareAiExcerpt(c){c.url=validWebUrl(c.url||'');c.tags=Array.isArray(c.tags)?c.tags:[];c.ai.provider=aiProvider(c.ai.provider).url?c.ai.provider:'unknown';c.ai.blocks=Array.isArray(c.ai.blocks)?c.ai.blocks:parseAiExcerptBlocks(c.ai.originalText||'');c.title=c.title||aiExcerptSummary(c.ai.originalText);return c}
function aiSiblings(c){return state.cards.filter(x=>isAiExcerpt(x)&&x.ai.threadId===c.ai.threadId)}
function aiExcerptMarkup(c){
 prepareAiExcerpt(c);const p=aiProvider(c.ai.provider),siblings=aiSiblings(c),stamp=c.ai.capturedAt?new Date(c.ai.capturedAt).toLocaleString('zh-CN',{month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit'}):c.time,body=aiBlocksMarkup(c.ai.blocks);
 return `<article class="card resource-card ai-excerpt-card ${c.ai.mode==='full'?'ai-full-conversation':''} ${c.expanded?'web-window':''} ${zoom<.65?'semantic-low':''} ${selected===c.id?'selected':''}" data-id="${c.id}" data-type="source" style="left:${c.x}px;top:${c.y}px"><div class="resource-summary"><div class="ai-excerpt-normal">
 <div class="ai-excerpt-preview ai-rich-content ai-excerpt-drag">${body}</div>
 <div class="ai-excerpt-tags" data-card-tags ${c.tags.length?'':'hidden'}>${resourceTags(c)}</div>
 </div>
 <div class="ai-excerpt-low ai-excerpt-drag"><h3>${esc(c.title)}</h3><div data-card-tags ${c.tags.length?'':'hidden'}>${resourceTags(c)}</div></div>
 <footer class="ai-excerpt-footer">
 <span class="ai-excerpt-prompt" title="${esc(c.ai.question||c.title)}">${esc(c.ai.question||c.title)}</span>
 ${c.ai.example
  ? `<span class="ai-excerpt-link-preview" title="${esc(AI_EXAMPLE_LINKS[c.ai.provider]||'对话链接')}">${aiProviderBadge(c.ai.provider)}<span>${esc(AI_EXAMPLE_LINKS[c.ai.provider]||'对话链接')}</span></span>`
  : `<button data-ai-open title="${esc(p.name+' · 在画布内展开摘录')}">${aiProviderBadge(c.ai.provider)}<span>${c.url?'对话链接':'查看摘录'}</span></button>`}
 </footer></div><div class="resource-browser ai-excerpt-reader"><header class="ai-excerpt-drag"><span>${esc(p.name)} · ${c.ai.mode==='full'?'对话快照':'摘录阅读'}</span><div>${c.url?`<a href="${esc(c.url)}" target="_blank" rel="noopener noreferrer" title="打开原对话" aria-label="打开原对话">↗</a>`:''}<button data-ai-collapse title="收起阅读窗口" aria-label="收起阅读窗口">−</button></div></header><nav class="ai-reader-tools" aria-label="摘录操作"><button data-ai-siblings aria-expanded="false">同源摘录 ${siblings.length}</button><button data-ai-more>再摘一段</button><button data-ai-thought>写下想法</button>${c.ai.mode!=='full'?'<button data-ai-idea>提取为 AI 想法</button>':''}</nav><div class="ai-siblings" hidden>${siblings.map(s=>`<button data-ai-locate="${s.id}" ${s.id===c.id?'aria-current="true"':''}>${esc(s.title)}</button>`).join('')}</div><div class="ai-reader-body"><h3>${esc(c.title)}</h3>${c.ai.question?`<div class="ai-reader-role">原问题</div><div class="ai-reader-question">${esc(c.ai.question)}</div>`:'<div class="ai-excerpt-omitted">未附原问题</div>'}<div class="ai-reader-role">${c.ai.mode==='full'?'已保存对话（按粘贴原文）':c.ai.example?'示例回答 · '+esc(p.name):esc(p.name)+' 的回答 · 已保存片段'}</div><div class="ai-reader-quote ai-rich-content">${body}</div><div class="ai-excerpt-omitted">${c.ai.mode==='full'?'仅展示本次导入的内容':'其余对话未导入'}</div></div><div class="window-card-tags" data-card-tags ${c.tags.length?'':'hidden'}>${resourceTags(c)}</div><footer class="ai-reader-meta"><span>${esc(stamp||'')} · ${cardAdditionKind(c)==='agent'?'智能体添加':'用户摘取'}</span><span>${c.url?'已附原对话链接':c.ai.example?'原型示例':'未附原链接'}</span></footer></div></article>`
}
function openAiExcerpt(c){
 if(zoom<.65)setZoom(.8);
 c.expanded=true;
 const el=cardElement(c.id);
 if(el){
  el.classList.add('web-window');
  const rect=el.getBoundingClientRect();
  const right=innerWidth-16,bottom=innerHeight-16;
  const left=innerWidth-rect.width>=280&&!$('#sidebar').hidden?$('#sidebar').getBoundingClientRect().right+12:12;
  pan.x+=Math.max(left,Math.min(rect.left,right-rect.width))-rect.left;
  pan.y+=Math.max(80,Math.min(rect.top,bottom-rect.height))-rect.top;
  updateView();
 }
 save();
}
function bindAiExcerpt(el,c){
 el.querySelector('[data-ai-idea]')?.addEventListener('click',()=>ideaFromExcerpt(c));
 el.onclick=e=>{if(e.target.closest('button,a'))return;if(picking){useCard(c);return}selected=c.id;$$('.card').forEach(x=>x.classList.toggle('selected',x===el))};
 el.querySelectorAll('.ai-excerpt-drag').forEach(handle=>{handle.ondblclick=e=>{if(e.target.closest('button,a,[data-card-tag]'))return;openAiExcerpt(c)};handle.onpointerdown=e=>{if(e.button!==0||picking||e.target.closest('button,a,[data-card-tag]'))return;e.preventDefault();const origin={x:c.x,y:c.y,cx:e.clientX,cy:e.clientY};handle.setPointerCapture(e.pointerId);handle.onpointermove=ev=>{c.x=origin.x+(ev.clientX-origin.cx)/zoom;c.y=origin.y+(ev.clientY-origin.cy)/zoom;el.style.left=c.x+'px';el.style.top=c.y+'px'};handle.onpointerup=()=>{handle.onpointermove=null;save()}}});
 const openButton=el.querySelector('[data-ai-open]');
 if(openButton)openButton.onclick=()=>picking?useCard(c):openAiExcerpt(c);
 el.querySelector('[data-ai-collapse]').onclick=()=>{c.expanded=false;el.classList.remove('web-window');save();refreshGraph()};el.querySelector('[data-ai-more]').onclick=()=>openAiExcerptImporter({fresh:true,position:{x:c.x+el.offsetWidth+24,y:c.y},context:{provider:c.ai.provider,threadId:c.ai.threadId,title:state.aiThreads.find(t=>t.id===c.ai.threadId)?.title||'',url:c.url,question:c.ai.question}});el.querySelector('[data-ai-siblings]').onclick=e=>{const list=el.querySelector('.ai-siblings');list.hidden=!list.hidden;e.currentTarget.setAttribute('aria-expanded',String(!list.hidden));refreshGraph()};el.querySelectorAll('[data-ai-locate]').forEach(b=>b.onclick=()=>{const target=state.cards.find(x=>x.id===b.dataset.aiLocate);if(!target)return;target.expanded=true;if(zoom<.65)setZoom(.8);locate(target.id)});el.querySelector('[data-ai-thought]').onclick=()=>{const note=addCard('claim','未命名想法','',{autoTitle:true,x:c.x+el.offsetWidth+30,y:c.y,referenceIds:[c.id]});connectCards({id:c.id,side:'right'},{id:note.id,side:'left'});locate(note.id);cardElement(note.id)?.querySelector('.claim-text')?.focus()}
}
function aiThreadOptions(provider,current){return '<option value="">新对话</option>'+state.aiThreads.filter(t=>t.provider===provider&&(t.id===current||state.cards.some(c=>isAiExcerpt(c)&&c.ai.threadId===t.id))).map(t=>`<option value="${t.id}" ${t.id===current?'selected':''}>${esc(t.title||aiProvider(t.provider).name+' 对话')}</option>`).join('')}
function openAiExcerptImporter(options={}){
 closeSources();showCreationMenu(null);if($('#dialog').open)$('#dialog').close();aiImportEditing=options.card||null;aiImportCommitted=false;aiPastePosition=options.position||null;
 const c=aiImportEditing,requestedContext=options.context||state.aiImportContext||{},context=!options.context&&activeAiProvider()&&requestedContext.provider!==activeAiProvider()?{}:requestedContext,old=c?{provider:c.ai.provider,threadId:c.ai.threadId,title:state.aiThreads.find(t=>t.id===c.ai.threadId)?.title||'',question:c.ai.question,url:c.url,text:c.ai.originalText,summary:c.title,tags:c.tags.join(', '),mode:c.ai.mode}:null;
 let d=old||{provider:options.context?.provider||activeAiProvider()||context.provider||state.lastAiProvider||'unknown',threadId:context.threadId||'',title:context.title||'',question:context.question||'',url:context.url||'',text:options.text??'',summary:'',tags:'',mode:'excerpt'};
 if(!c&&!options.fresh&&!Object.hasOwn(options,'text')&&state.aiImportDraft?.provider===d.provider&&(!options.context||state.aiImportDraft.threadId===d.threadId))d={...d,...state.aiImportDraft};
 d.provider=aiProvider(d.provider).url?d.provider:'unknown';$('#ai-import-body').innerHTML=`<form id="ai-excerpt-form"><div class="ai-import-grid"><section class="ai-import-fields"><div class="ai-field-pair"><label>来源<select id="ai-import-provider">${aiProviderOptions(d.provider)}</select></label><label>所属对话<select id="ai-import-thread">${aiThreadOptions(d.provider,d.threadId)}</select></label></div><fieldset class="ai-import-mode"><legend class="selection-sr-only">保存范围</legend><label><input type="radio" name="ai-save-mode" value="excerpt" ${d.mode!=='full'?'checked':''}> 摘取片段</label><label><input type="radio" name="ai-save-mode" value="full" ${d.mode==='full'?'checked':''}> 整段保存</label></fieldset><label>${c?'已保存原文':'粘贴回答或对话内容'}<textarea id="ai-import-text" rows="7" maxlength="50000" ${c?'readonly':''} required placeholder="在外部 AI 中复制想保留的内容，粘贴到这里。支持 Markdown 列表、表格与代码。">${esc(d.text||'')}</textarea></label><label class="ai-import-question-toggle"><input id="ai-include-question" type="checkbox" ${d.question?'checked':''}> 附带对应问题</label><textarea id="ai-import-question" rows="2" maxlength="10000" aria-label="对应问题" placeholder="可选：这段回答对应的提问" ${d.question?'':'hidden'}>${esc(d.question||'')}</textarea><details class="ai-import-details" ${c?'open':''}><summary>标题、原链接与标签</summary><label>对话名称<input id="ai-import-thread-title" maxlength="120" value="${esc(d.title||'')}" placeholder="可选，方便下次关联同一对话"></label><label>原对话链接<input id="ai-import-url" type="url" value="${esc(d.url||'')}" placeholder="可选，没有链接也能保存"></label><label>卡片摘要<input id="ai-import-summary" maxlength="100" value="${esc(d.summary||'')}" placeholder="留空则从所选内容提取摘要"></label><label>标签<input id="ai-import-tags" maxlength="400" value="${esc(d.tags||'')}" placeholder="多个标签用逗号分隔"></label></details></section><section class="ai-import-selection"><div class="ai-import-selection-heading"><strong id="ai-selection-title">选择要保存的段落</strong><button type="button" id="ai-select-all">全选</button></div><div id="ai-block-options"></div><p class="ai-import-note">${c?'原文保留不变，可修改摘要和来源信息。':'一次摘取生成一张资源卡片。只有勾选内容和你附带的问题会被保存。'}</p></section></div><div class="ai-import-bottom"><span id="ai-import-count" role="status"></span><button class="primary" id="ai-import-save" type="submit">${c?'保存修改':'加入画布'}</button></div><p id="ai-import-error" role="alert"></p></form>`;
 const provider=$('#ai-import-provider'),thread=$('#ai-import-thread');if(!c&&d.threadId&&!state.aiThreads.some(t=>t.id===d.threadId)){const option=document.createElement('option');option.value=d.threadId;option.textContent=d.title||'当前 AI 对话';thread.append(option);thread.value=d.threadId}
 const rebuild=(preserve=false)=>{const previous=aiImportBlocks,selectedBefore=aiImportSelection;aiImportBlocks=c?c.ai.blocks:parseAiExcerptBlocks($('#ai-import-text').value);aiImportSelection=new Set(aiImportBlocks.map((block,i)=>{if(!preserve)return i;const match=previous.findIndex(old=>old.text===block.text&&old.type===block.type);return (match>=0?selectedBefore.has(match):i>=previous.length||selectedBefore.has(i))?i:null}).filter(i=>i!==null));renderAiImportBlocks()};
 $('#ai-import-text').oninput=()=>{rebuild(true);state.aiImportDraft=readAiImportDraft();save()};$('#ai-import-text').onpaste=e=>{if(aiImportEditing)return;const plain=e.clipboardData?.getData('text/plain')||'',html=e.clipboardData?.getData('text/html')||'',converted=aiClipboardText(plain,html);const field=e.currentTarget,remaining=50000-field.value.length+field.selectionEnd-field.selectionStart;if(converted.length>remaining){e.preventDefault();notify('内容超过 5 万字，请分段摘取后导入');return}if(converted!==plain){e.preventDefault();field.setRangeText(converted,field.selectionStart,field.selectionEnd,'end');field.oninput()}};$('#ai-include-question').onchange=e=>{$('#ai-import-question').hidden=!e.target.checked};provider.onchange=()=>{thread.innerHTML=aiThreadOptions(provider.value,'');$('#ai-import-thread-title').value='';$('#ai-import-url').value=''};thread.onchange=()=>{const t=state.aiThreads.find(x=>x.id===thread.value);if(t){$('#ai-import-thread-title').value=t.title||'';$('#ai-import-url').value=t.url||'';if(t.question&&!$('#ai-import-question').value){$('#ai-import-question').value=t.question;$('#ai-include-question').checked=true;$('#ai-import-question').hidden=false}}else{$('#ai-import-thread-title').value='';$('#ai-import-url').value=''}};
 $$('input[name="ai-save-mode"]').forEach(input=>{input.disabled=!!c;input.onchange=()=>{if(input.value==='full'&&input.checked)aiImportSelection=new Set(aiImportBlocks.map((_,i)=>i));renderAiImportBlocks()}});$('#ai-select-all').onclick=()=>{aiImportSelection=new Set(aiImportBlocks.map((_,i)=>i));renderAiImportBlocks()};$('#ai-excerpt-form').onsubmit=saveAiExcerptImport;rebuild();if(!c&&d.mode!=='full'&&Array.isArray(d.indices)){aiImportSelection=new Set(d.indices.filter(i=>Number.isInteger(i)&&i>=0&&i<aiImportBlocks.length));renderAiImportBlocks()}$('#ai-import-dialog').showModal();if(!c)$('#ai-import-text').focus()
}
function renderAiImportBlocks(){const full=$('input[name="ai-save-mode"]:checked')?.value==='full';$('#ai-selection-title').textContent=full?'本次粘贴内容将整段保存':'选择要保存的段落';$('#ai-block-options').innerHTML=aiImportBlocks.length?aiImportBlocks.map((block,i)=>`<label class="ai-block-option"><input type="checkbox" data-ai-block="${i}" ${aiImportSelection.has(i)?'checked':''} ${full||aiImportEditing?'disabled':''}><div class="ai-rich-content">${aiBlockMarkup(block)}</div></label>`).join(''):'<div class="ai-import-empty">粘贴内容后，在这里预览并选择段落</div>';$$('[data-ai-block]').forEach(input=>input.onchange=()=>{if(input.checked)aiImportSelection.add(Number(input.dataset.aiBlock));else aiImportSelection.delete(Number(input.dataset.aiBlock));updateAiImportCount()});$('#ai-select-all').hidden=full||!!aiImportEditing;updateAiImportCount()}
function updateAiImportCount(){$('#ai-import-count').textContent='已选 '+aiImportSelection.size+' 段 · 1 张卡片';$('#ai-import-save').disabled=!aiImportSelection.size}
function readAiImportDraft(){return {provider:$('#ai-import-provider').value,threadId:$('#ai-import-thread').value,title:$('#ai-import-thread-title').value,question:$('#ai-include-question').checked?$('#ai-import-question').value:'',url:$('#ai-import-url').value,text:$('#ai-import-text').value,summary:$('#ai-import-summary').value,tags:$('#ai-import-tags').value,mode:$('input[name="ai-save-mode"]:checked')?.value||'excerpt',indices:[...aiImportSelection]}}
function buildAiExcerptData(input){
 const provider=aiProvider(input.provider).url?input.provider:'unknown',all=parseAiExcerptBlocks(input.text),indices=input.mode==='full'?all.map((_,i)=>i):[...new Set(input.indices||[])].filter(i=>Number.isInteger(i)&&i>=0&&i<all.length).sort((a,b)=>a-b);
 if(String(input.text||'').length>50000)throw Error('内容超过 5 万字，请分段摘取后导入');if(!indices.length)throw Error('请粘贴内容，并至少选择一段回答');if(input.url&&!validWebUrl(input.url))throw Error('请填写有效的 http 或 https 原对话链接');
 const blocks=indices.map((index,i)=>({...all[index],sourceIndex:index,gapBefore:i>0&&index>indices[i-1]+1})),originalText=input.mode==='full'?input.text:blocks.map(b=>(b.gapBefore?'［中间内容未选入］\n\n':'')+b.text).join('\n\n');
 return {provider,mode:input.mode==='full'?'full':'excerpt',question:input.question||'',blocks,originalText,summary:input.summary?.trim()||aiExcerptSummary(originalText),url:validWebUrl(input.url||''),tags:[...new Set(String(input.tags||'').split(/[,，]/).map(tagLabel).filter(Boolean))]}
}
function saveAiExcerptImport(e){
 e.preventDefault();const provider=$('#ai-import-provider').value,question=$('#ai-include-question').checked?$('#ai-import-question').value.trim():'',url=$('#ai-import-url').value.trim();let data;
 try{data=aiImportEditing?{...aiImportEditing.ai,provider,question,summary:$('#ai-import-summary').value.trim()||aiExcerptSummary(aiImportEditing.ai.originalText),url:validWebUrl(url),tags:$('#ai-import-tags').value.split(/[,，]/).map(tagLabel).filter(Boolean)}:buildAiExcerptData({provider,question,url,text:$('#ai-import-text').value,indices:[...aiImportSelection],mode:$('input[name="ai-save-mode"]:checked').value,summary:$('#ai-import-summary').value,tags:$('#ai-import-tags').value});if(url&&!validWebUrl(url))throw Error('请填写有效的 http 或 https 原对话链接')}catch(error){$('#ai-import-error').textContent=error.message;return}
 const canonical=value=>value?value.split('#')[0]:'',selectedThread=$('#ai-import-thread').value,matching=data.url?state.aiThreads.find(t=>t.provider===provider&&canonical(t.url)===canonical(data.url)):null;let thread=state.aiThreads.find(t=>t.id===selectedThread&&t.provider===provider&&(!data.url||!t.url||canonical(t.url)===canonical(data.url)))||matching;
 if(!thread){thread={id:selectedThread&&!state.aiThreads.some(t=>t.id===selectedThread)?selectedThread:crypto.randomUUID(),provider};state.aiThreads.push(thread)}thread.title=$('#ai-import-thread-title').value.trim()||thread.title||question.slice(0,60)||aiProvider(provider).name+' 对话';if(data.url)thread.url=data.url;thread.question=question;const {summary,tags,...content}=data,ai={...content,threadId:thread.id,capturedAt:aiImportEditing?.ai.capturedAt||new Date().toISOString()},text=(question?'问题：'+question+'\n\n':'')+data.originalText;
 let c=aiImportEditing;if(c){c.title=summary;c.tags=tags;c.url=data.url;c.ai=ai;c.text=text;save();renderCards();renderSide()}else{c=addCard('source',summary,text,{subtype:'ai-excerpt',ai,url:data.url,tags,addedBy:'personal',...(aiPastePosition?{x:aiPastePosition.x,y:aiPastePosition.y}:{})});state.aiImportDraft=null}
 state.aiImportContext={provider,threadId:thread.id,title:thread.title,question,url:data.url};const wasEditing=!!aiImportEditing;aiImportCommitted=true;save();$('#ai-import-dialog').close();$('#result-panel').hidden=true;closeSources();if(!wasEditing)locate(c.id);notify(wasEditing?'已保存摘录信息':'已加入 1 张对话摘录卡片')
}
function initAiConversations(){
 state.aiThreads=Array.isArray(state.aiThreads)?state.aiThreads:[];seedAiExcerptExamples();state.cards.filter(isAiExcerpt).forEach(prepareAiExcerpt);
 const chip=document.createElement('div');chip.id='ai-target-wrap';chip.hidden=true;chip.innerHTML='<button id="ai-target" type="button" aria-haspopup="true" aria-controls="source-panel"></button>';$('#search-form').insertBefore(chip,$('#query'));
 const dialog=document.createElement('dialog');dialog.id='ai-import-dialog';dialog.setAttribute('aria-labelledby','ai-import-heading');dialog.innerHTML='<header><strong id="ai-import-heading">导入 AI 对话摘录</strong><button id="ai-import-close" class="icon" aria-label="关闭摘录导入">×</button></header><div id="ai-import-body"></div>';$('#workspace').append(dialog);$('#ai-import-close').onclick=()=>dialog.close();dialog.addEventListener('close',()=>{if(!aiImportCommitted&&!aiImportEditing&&$('#ai-import-text')){state.aiImportDraft=readAiImportDraft();save()}aiImportEditing=null});
 document.addEventListener('pointermove',e=>{if(e.target===$('#workspace')||e.target===$('#world'))aiLastPointer=worldPoint(e)});
 document.addEventListener('paste',e=>{if(document.querySelector('dialog[open]')||e.target.closest('input,textarea,[contenteditable]'))return;const plain=e.clipboardData?.getData('text/plain')||'',text=aiClipboardText(plain,e.clipboardData?.getData('text/html')||'');if(!text.trim())return;e.preventDefault();if(text.length>50000){notify('内容超过 5 万字，请分段摘取后导入');return}const options={text,position:aiLastPointer};if(activeAiProvider()){openAiExcerptImporter(options);return}modal('将内容加入画布',`<p class="ai-paste-preview">${esc(text.slice(0,160))}${text.length>160?'…':''}</p><div class="ai-paste-options"><button class="primary" id="paste-ai-excerpt">AI 对话摘录</button><button class="ai-secondary" id="paste-claim-note">想法便签</button></div>`);$('#paste-ai-excerpt').onclick=()=>openAiExcerptImporter(options);$('#paste-claim-note').onclick=()=>{const note=addCard('claim','未命名想法',text,{autoTitle:true,...(options.position||{})});$('#dialog').close();locate(note.id)}});
 document.addEventListener('keydown',e=>{if(!dialog.open)return;if(e.key==='Escape'){e.preventDefault();dialog.close()}e.stopImmediatePropagation()},true)
}

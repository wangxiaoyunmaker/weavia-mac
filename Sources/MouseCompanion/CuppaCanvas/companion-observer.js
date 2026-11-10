/* Observe only the trusted local canvas. Never install in remote web pages. */
(()=>{
 if(globalThis.cuppaCompanion)return;
 const config={mode:'focus',enabled:true,blocked:true};
 const limits={settle:12000,idle:3000,cooldown:300000,window:1200000,max:3,lifetime:18000};
 let entered=Date.now(),activity=Date.now(),heartbeat=0,lastShown=-Infinity,history=[],pauseUntil=0;
 let current=null,sequence=0,project=projectId,manual=false,manualUntil=0,displayed=0;
 let lastGeometry='',lastGeometryAt=Date.now();const rejected=new Set(),ignored=new Map(),held=new Set();
 const bubble=document.createElement('section');bubble.id='companion-hint';bubble.hidden=true;bubble.setAttribute('aria-label','鼠标伙伴本地提示');document.body.append(bubble);
 const rings=[];
 const sessionKey='cuppa-companion-session-v1';
 function cueKey(candidate){let hash=2166136261;const value=projectId+'|'+candidate.key;for(let i=0;i<value.length;i++){hash^=value.charCodeAt(i);hash=Math.imul(hash,16777619);}return projectId+'|'+(hash>>>0).toString(36);}
 function remember(){try{sessionStorage.setItem(sessionKey,JSON.stringify({version:1,lastShown,history,pauseUntil,rejected:[...rejected].slice(-300),ignored:[...ignored].slice(-300)}));}catch{/* Session feedback may remain in memory; never block the canvas. */}}
 try{const saved=JSON.parse(sessionStorage.getItem(sessionKey)||'null');if(saved?.version===1){if(Number.isFinite(saved.lastShown))lastShown=saved.lastShown;history=Array.isArray(saved.history)?saved.history.filter(Number.isFinite):[];if(Number.isFinite(saved.pauseUntil))pauseUntil=saved.pauseUntil;(saved.rejected||[]).filter(v=>typeof v==='string').slice(-300).forEach(v=>rejected.add(v));(saved.ignored||[]).filter(v=>Array.isArray(v)&&typeof v[0]==='string'&&Number.isFinite(v[1])).slice(-300).forEach(v=>ignored.set(v[0],v[1]));}}catch{}
 const element=id=>document.querySelector('.card[data-id="'+CSS.escape(id)+'"]');
 const escText=s=>String(s||'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 function clear(){current=null;bubble.hidden=true;rings.splice(0).forEach(n=>n.remove());AppStatus('observing');}
 function AppStatus(value){globalThis.cuppaCompanionStatus=value;}
 function interact(e){if(e.target?.closest?.('#companion-hint'))return;activity=Date.now();clear();}
 ['pointerdown','keydown','input','wheel','compositionstart','dragstart'].forEach(name=>document.addEventListener(name,e=>{if(e.target?.closest?.('#companion-hint'))return;if(name==='pointerdown')held.add(e.pointerId);interact(e);},true));
 ['pointerup','pointercancel'].forEach(name=>document.addEventListener(name,e=>{held.delete(e.pointerId);activity=Date.now();},true));
 document.addEventListener('pointermove',e=>{if(e.target?.closest?.('#companion-hint'))return;if(held.size){activity=Date.now();clear();}} ,true);
 window.addEventListener('blur',()=>{held.clear();activity=Date.now();clear();});
 document.addEventListener('visibilitychange',()=>{activity=Date.now();clear();});
 window.addEventListener('hashchange',()=>{activity=entered=Date.now();clear();});
 window.addEventListener('resize',()=>{activity=Date.now();clear();});
 function busy(){return config.blocked||document.hidden||Date.now()-heartbeat>1800||location.hash!=='#cuppa'||!globalThis.cuppaReady||!!globalThis.cuppaBootstrap?.error||document.querySelector('#workspace')?.hidden||held.size>0||!!document.querySelector('dialog[open]')||!!document.activeElement?.matches('input,textarea,[contenteditable="true"]')||!!document.querySelector('iframe:focus')||!!(typeof cardDragActive!=='undefined'&&cardDragActive)||!!(typeof marqueeDragging!=='undefined'&&marqueeDragging)||!!(typeof canvasAction!=='undefined'&&canvasAction)||!!(typeof picking!=='undefined'&&picking)||!!globalThis.cuppaCaptureBusy||!!globalThis.cuppaRelationFinished||!!document.querySelector('body.dragging')||['#result-panel','#source-panel','#add-menu','#more-menu','#selection-actions'].some(s=>{const e=document.querySelector(s);return e&&!e.hidden&&getComputedStyle(e).display!=='none';});}
 function visible(c){const el=element(c.id);if(!el)return false;const r=el.getBoundingClientRect();if(r.width<60||r.height<50||r.left<10||r.top<75||r.right>innerWidth-12||r.bottom>innerHeight-68)return false;const hit=document.elementFromPoint(r.left+r.width/2,r.top+Math.min(35,r.height/2));return !!hit&&hit.closest('.card')===el;}
 function geometry(ids){return ids.map(id=>{const r=element(id)?.getBoundingClientRect();return r?{id,x:r.x,y:r.y,width:r.width,height:r.height}:null;});}
 function fingerprint(){return JSON.stringify([projectId,pan.x,pan.y,zoom,innerWidth,innerHeight]);}
 function candidates(){return CompanionRules.candidates(state.cards.filter(visible),state.connections||[]);}
 function valid(item){return item&&item.project===projectId&&item.frame===fingerprint()&&item.candidate.ids.every(id=>{const c=state.cards.find(v=>v.id===id);return c&&visible(c);})&&JSON.stringify(geometry(item.candidate.ids))===JSON.stringify(item.rects)&&candidates().some(v=>JSON.stringify(v)===JSON.stringify(item.candidate));}
 function show(candidate,now){
  const rects=geometry(candidate.ids);if(rects.some(v=>!v))return;
  const r=rects[0],width=Math.min(300,innerWidth-24),height=226;
  let left=r.x+r.width+24,top=r.y+24,side='right';
  if(left+width>innerWidth-12){left=r.x-width-24;side='left';}
  if(left<12){left=Math.max(12,Math.min(innerWidth-width-12,r.x));top=r.y+r.height+18;side='below';}
  // If no space exists, do not cover the target or force a viewport change.
  if(top+height>innerHeight-55||left<12)return;
  const occupied=rects.some(v=>left<v.x+v.width&&left+width>v.x&&top<v.y+v.height&&top+height>v.y);
  if(occupied)return;
  current={id:String(++sequence),project:projectId,frame:fingerprint(),candidate,rects,shownAt:now,x:side==='left'?r.x-56:r.x+r.width+4,y:r.y-15,reduced:matchMedia('(prefers-reduced-motion: reduce)').matches};
  current.x=Math.max(0,Math.min(innerWidth-52,current.x));current.y=Math.max(0,Math.min(innerHeight-52,current.y));
  bubble.style.left=left+'px';bubble.style.top=top+'px';
  bubble.innerHTML='<header><span>本地提示 · 未执行操作</span><button data-hint="ignore" aria-label="忽略建议">×</button></header><h3>'+escText(candidate.title)+'</h3><p>'+escText(candidate.text)+'</p><p class="hint-basis">'+escText(candidate.basis)+'</p><footer><button data-hint="evidence">查看依据</button><button data-hint="ignore">忽略</button><button data-hint="pause">暂停 30 分钟</button><button data-hint="reject" class="hint-less">本次不再提示</button></footer>';
  bubble.hidden=false;
  for(const v of rects){const ring=document.createElement('div');ring.className='companion-target-ring';ring.setAttribute('aria-hidden','true');Object.assign(ring.style,{left:(v.x-4)+'px',top:(v.y-4)+'px',width:(v.width+8)+'px',height:(v.height+8)+'px'});document.body.append(ring);rings.push(ring);}
  lastShown=now;history.push(now);remember();displayed++;AppStatus('suggesting');
 }
 function evidence(){
  if(!valid(current)){clear();return;}
  const c=current.candidate,records=c.ids.map(id=>state.cards.find(v=>v.id===id));clear();
  modal('这条提示的依据','<p>仅查看当前项目已保存的信息。没有分析图片、调用模型或修改卡片。</p><p>'+escText(c.basis)+'</p>'+records.map(v=>'<section class="companion-evidence-item"><h4>'+escText(v.title||'未命名卡片')+'</h4><p>'+escText(v.userNote||v.note||'尚无用户备注')+'</p><p>标签：'+escText((v.tags||[]).join('、')||'无')+'</p><p class="companion-evidence-source">来源：'+escText(v.provenance?.url||v.url||v.sourceURL||'尚未记录链接')+'</p></section>').join(''));
 }
 bubble.addEventListener('click',e=>{const action=e.target.closest('[data-hint]')?.dataset.hint;if(!action||!current)return;if(action==='evidence'){evidence();return;}const key=cueKey(current.candidate);if(action==='reject')rejected.add(key);if(action==='ignore')ignored.set(key,Date.now()+1800000);if(action==='pause')pauseUntil=Date.now()+1800000;remember();clear();});
 function tick(){
  const now=Date.now();if(manual&&now>manualUntil)manual=false;if(project!==projectId){project=projectId;entered=activity=now;manual=false;clear();}
  const frame=fingerprint();if(frame!==lastGeometry){lastGeometry=frame;lastGeometryAt=now;clear();}
  if(config.mode!=='cocreate'||!config.enabled||now<pauseUntil||busy()){clear();return;}
  if(current){if(!valid(current)||now-current.shownAt>limits.lifetime)clear();return;}
  if(now-activity<limits.idle||now-lastGeometryAt<limits.idle)return;
  history=history.filter(t=>now-t<limits.window);
  if(!manual&&(now-entered<limits.settle||now-lastShown<limits.cooldown||history.length>=limits.max))return;
  for(const c of candidates()){const key=cueKey(c);if(rejected.has(key)||(ignored.get(key)||0)>now)continue;show(c,now);if(current){manual=false;break;}}
 }
 function configure(input){
  heartbeat=Date.now();const previous=config.mode;config.mode=input.mode==='cocreate'?'cocreate':'focus';config.enabled=input.enabled!==false;config.blocked=!!input.blocked;
  if(previous!==config.mode){entered=activity=Date.now();manual=false;clear();}
  tick();return read();
 }
 function read(){return {active:!!current,id:current?.id||'',project:projectId,x:(current?.x||0)/innerWidth,y:(current?.y||0)/innerHeight,reduced:!!current?.reduced,paused:Date.now()<pauseUntil,displayed,status:config.mode==='focus'?'quiet':Date.now()<pauseUntil?'paused':current?'suggesting':'observing'};}
 function request(){if(config.mode!=='cocreate'||!config.enabled)return false;pauseUntil=0;manual=true;manualUntil=Date.now()+30000;remember();clear();return true;}
 function pause(){pauseUntil=Date.now()+1800000;manual=false;remember();clear();return read();}
 function resume(){pauseUntil=0;activity=Date.now();remember();return read();}
 const timer=setInterval(tick,250);window.addEventListener('pagehide',()=>{clearInterval(timer);clear();});
 globalThis.cuppaCompanion={configure,read,request,pause,resume,cancel:()=>{activity=Date.now();manual=false;clear();}};
})();

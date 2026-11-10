// Shared card drag lifecycle. Editable content and card actions retain their gestures.
let cardDragActive=false;
function syncCardDragTargets(){
 const world=document.getElementById('world');if(!world)return;
 // The card scales, but its grab target must remain usable when zoomed out.
 const scale=String(1/Math.max(.25,zoom));
 if(world.style.getPropertyValue('--card-drag-scale')!==scale)world.style.setProperty('--card-drag-scale',scale);
}
function bindCardDragging(el,c){
 syncCardDragTargets();
 if(el.dataset.dragBound)return;el.dataset.dragBound='1';
 // Keep keyboard movement on the card without a raised six-dot handle.
 el.tabIndex=0;el.setAttribute('aria-description','方向键移动卡片，按住 Shift 加快；也可拖动标题、页脚或卡片空白处。');
 const meta=el.querySelector('.claim-meta');if(meta){meta.title='按住此栏拖动卡片';const hint=document.createElement('span');hint.className='drag-meta-hint';hint.textContent='拖动';meta.prepend(hint);}
 el.addEventListener('dragstart',e=>{if(e.target.closest('img,.card-drag-grip'))e.preventDefault()});
 el.addEventListener('pointerdown',e=>{
  if(e.button!==0||e.isPrimary===false||picking||canvasAction||cardDragActive)return;
  const handle=e.target.closest('.card-drag-grip,.claim-meta,.claim-summary,.resource-drag,.ai-excerpt-drag,header');
  const interactive=e.target.closest('button,a,input,textarea,select,[contenteditable],.claim-sketch,[data-card-tag]');
  const blank=e.target===el||e.target.matches('.claim-content,.resource-footer');
  if(interactive||(!handle&&!blank))return;
  e.preventDefault();e.stopImmediatePropagation();
  const id=e.pointerId,start={x:e.clientX,y:e.clientY},origin={x:c.x,y:c.y},scale=zoom;
  const threshold=e.pointerType==='mouse'?1:3;
  let last=start,frame=0,moved=false,ended=false,painted=null;
  cardDragActive=true;hidePort();hideTagTools();
  const paint=()=>{frame=0;if(!moved)return;if(!el.isConnected||!state.cards.includes(c)){cancel({pointerId:id});return;}const dx=(last.x-start.x)/scale,dy=(last.y-start.y)/scale;c.x=origin.x+dx;c.y=origin.y+dy;painted={x:c.x,y:c.y};el.style.transform=`translate3d(${dx}px,${dy}px,0)`;if(state.connections?.length)refreshGraph();};
  const move=ev=>{if(ev.pointerId!==id)return;last={x:ev.clientX,y:ev.clientY};if(!moved&&Math.hypot(last.x-start.x,last.y-start.y)>=threshold){moved=true;el.classList.add('card-dragging');}if(moved&&!frame)frame=requestAnimationFrame(paint);};
  const finish=(ev,cancelled=false)=>{
   if(ended||(ev.pointerId!==undefined&&ev.pointerId!==id))return;ended=true;cancelled=cancelled||!el.isConnected||!state.cards.includes(c);
   if(frame)cancelAnimationFrame(frame);
   if(cancelled){if(painted&&state.cards.includes(c)&&c.x===painted.x&&c.y===painted.y){c.x=origin.x;c.y=origin.y;const current=cardElement(c.id);if(current&&current!==el){current.style.left=c.x+'px';current.style.top=c.y+'px';}}}else{if(moved)last={x:ev.clientX,y:ev.clientY};paint();}
   el.removeEventListener('pointermove',move);el.removeEventListener('pointerup',up);el.removeEventListener('pointercancel',cancel);el.removeEventListener('lostpointercapture',cancel);
   document.removeEventListener('pointerup',up,true);document.removeEventListener('pointercancel',cancel,true);document.removeEventListener('lostpointercapture',cancel,true);
   window.removeEventListener('blur',cancel);window.removeEventListener('pagehide',cancel);window.removeEventListener('keydown',escape,true);
   el.style.transform='';el.style.left=c.x+'px';el.style.top=c.y+'px';el.classList.remove('card-dragging');cardDragActive=false;
   if(el.hasPointerCapture(id))el.releasePointerCapture(id);
   if(moved){if(!cancelled)save();refreshGraph();const stop=event=>event.stopImmediatePropagation();el.addEventListener('click',stop,{once:true,capture:true});setTimeout(()=>el.removeEventListener('click',stop,true),0);}
  };
  const up=ev=>finish(ev,!el.isConnected),cancel=ev=>finish(ev,true);
  const escape=ev=>{if(ev.key==='Escape'){ev.preventDefault();ev.stopImmediatePropagation();cancel(ev);}};
  el.addEventListener('pointermove',move);el.addEventListener('pointerup',up);el.addEventListener('pointercancel',cancel);el.addEventListener('lostpointercapture',cancel);
  document.addEventListener('pointerup',up,true);document.addEventListener('pointercancel',cancel,true);document.addEventListener('lostpointercapture',cancel,true);
  window.addEventListener('blur',cancel);window.addEventListener('pagehide',cancel);window.addEventListener('keydown',escape,true);
  try{el.setPointerCapture(id);}catch(_){cancel(e);}
 },true);
 el.addEventListener('keydown',e=>{if(e.target!==el||!['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(e.key)||picking||canvasAction||cardDragActive)return;e.preventDefault();e.stopPropagation();const step=e.shiftKey?20:5;c.x+=e.key==='ArrowLeft'?-step:e.key==='ArrowRight'?step:0;c.y+=e.key==='ArrowUp'?-step:e.key==='ArrowDown'?step:0;el.style.left=c.x+'px';el.style.top=c.y+'px';save();refreshGraph();});
}

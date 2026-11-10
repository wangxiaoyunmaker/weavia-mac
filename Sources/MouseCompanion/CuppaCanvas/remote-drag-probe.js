/* External Web only. A trusted press identifies one image/link; a native drag must
   bind it before a real canvas drop can consume it. No native proxy or requests. */
(()=>{
 const key='__cuppaExplicitDragV1';
 if(globalThis[key])return true;
 let down=null,bound=null,sequence=0;
 const web=value=>/^https?:\/\//i.test(value||'')?String(value).slice(0,12000):'';
 const geometry=target=>{const r=target.getBoundingClientRect();return [r.x,r.y,r.width,r.height,scrollX,scrollY,innerWidth,innerHeight,visualViewport?.scale||1]};
 const valid=value=>{
  if(!value||!value.target.isConnected||value.target.ownerDocument!==document||value.source!==location.href)return false;
  const current=geometry(value.target);
  return value.geometry.every((n,i)=>Math.abs(n-current[i])<.5)&&value.image===web(value.imageNode?.currentSrc||value.imageNode?.src)&&value.link===web(value.linkNode?.href);
 };
 const press=(event,kind,x,y)=>{
  down=null;bound=null;
  if(!event.isTrusted||!(event.target instanceof Element))return;
  const target=event.target,imageNode=target.closest('img'),linkNode=target.closest('a[href]');
  const image=web(imageNode?.currentSrc||imageNode?.src),link=web(linkNode?.href);
  if(!image&&!link)return;
  down={at:Date.now(),x:x/innerWidth,y:y/innerHeight,kind,target,imageNode,linkNode,image,link,source:location.href,
   geometry:geometry(target),title:(imageNode?.alt||linkNode?.textContent||'').slice(0,300)};
 };
 document.addEventListener('pointerdown',event=>{
  down=null;bound=null;
  if(!event.isPrimary||event.button!==0||!['mouse','touch'].includes(event.pointerType))return;
  press(event,event.pointerType,event.clientX,event.clientY);
 },true);
 document.addEventListener('mousedown',event=>{
  if(down?.kind==='touch'&&Date.now()-down.at<1000)return;
  down=null;bound=null;if(event.button!==0)return;
  press(event,'mouse',event.clientX,event.clientY);
 },true);
 document.addEventListener('touchstart',event=>{
  down=null;bound=null;if(event.touches.length!==1||event.changedTouches.length!==1)return;
  const point=event.changedTouches[0];press(event,'touch',point.clientX,point.clientY);
 },true);
 for(const type of ['pointerup','mouseup','touchend'])document.addEventListener(type,()=>{down=null},true);
 for(const type of ['pointercancel','touchcancel'])document.addEventListener(type,()=>{if(down&&down.cancelledAt===undefined)down.cancelledAt=Date.now()},true);
 Object.defineProperty(globalThis,key,{value:Object.freeze({
  bind:gesture=>{
   const sessionId=gesture?.sessionId;
   const value=down;down=null;bound=null;
   if(!Number.isSafeInteger(sessionId)||!valid(value)||value.kind!==gesture.kind||!Number.isFinite(gesture.at)||!Number.isFinite(gesture.x)||!Number.isFinite(gesture.y)||Math.abs(value.at-gesture.at)>500||Math.abs(value.x-gesture.x)>.03||Math.abs(value.y-gesture.y)>.03||Date.now()-value.at>10000||(value.cancelledAt!==undefined&&Date.now()-value.cancelledAt>2500))return false;
   bound={value,sessionId,sequence:++sequence,draggedAt:Date.now()};return true;
  },
  cancel:sessionId=>{if(bound?.sessionId===sessionId)bound=null},
  take:()=>{
   const pending=bound;bound=null;
   if(!pending||!valid(pending.value))return null;
   const v=pending.value;
   return {sessionId:pending.sessionId,sequence:pending.sequence,at:v.at,draggedAt:pending.draggedAt,kind:v.kind,source:v.source.slice(0,12000),x:v.x,y:v.y,image:v.image,link:v.link,title:v.title};
  }
 }),writable:false,configurable:false});
 return true;
})();

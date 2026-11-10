/* Explicit canvas editing history, separate from the old selection-only undo. */
(()=>{
 'use strict';
 const engine=WeaviaCanvasHistory.create(state),workspace=document.getElementById('workspace');
 let busy=false;
 const bar=document.createElement('div');bar.id='canvas-history';bar.className='floating';bar.setAttribute('role','group');bar.setAttribute('aria-label','画布撤回与重做');
 bar.innerHTML='<button id="canvas-history-undo" type="button" aria-label="撤回画布操作"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m9 5-5 5 5 5M4 10h10a6 6 0 0 1 0 12h-4" transform="translate(1 -2)"/></svg><span>撤回</span></button><button id="canvas-history-redo" type="button" aria-label="重做画布操作"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m15 5 5 5-5 5M20 10H10a6 6 0 0 0 0 12h4" transform="translate(-1 -2)"/></svg><span>重做</span></button><span id="canvas-history-status" class="selection-sr-only" role="status" aria-live="polite"></span>';
 workspace.append(bar);
 const undo=document.getElementById('canvas-history-undo'),redo=document.getElementById('canvas-history-redo'),status=document.getElementById('canvas-history-status');
 const scope='当前打开项目内的卡片、移动、区域、连线、标签与画笔。项目记忆、托盘、搜索草稿、已发送回答不在范围内；重开项目后历史清空。';
 function update(){const s=engine.status(),locked=busy||!!globalThis.cuppaBootstrap?.error;undo.disabled=locked||!s.canUndo;redo.disabled=locked||!s.canRedo;bar.setAttribute('aria-busy',String(busy));undo.title=(s.canUndo?'撤回「'+s.undoLabel+'」':'暂无可撤回操作')+' · ⌘Z / Ctrl+Z\n'+scope;redo.title=(s.canRedo?'重做「'+s.redoLabel+'」':'暂无可重做操作')+' · ⌘⇧Z / Ctrl+Shift+Z\n'+scope;}
 const editing=()=>!!document.activeElement?.closest?.('input,textarea,select,[contenteditable]');
 async function run(isRedo=false){
  if(busy)return false;
  if(globalThis.cuppaBootstrap?.error||globalThis.cuppaCaptureBusy||globalThis.cuppaRelationBusy||typeof cardDragActive!=='undefined'&&cardDragActive||typeof marqueeDragging!=='undefined'&&marqueeDragging||typeof canvasAction!=='undefined'&&canvasAction){notify('请先完成当前操作，再撤回画布。');return false;}
  if(document.querySelector('dialog[open]')){notify('请先保存或关闭当前编辑窗口。');return false;}
  document.activeElement?.blur();
  let token;try{token=engine.prepare(state,isRedo);}catch(error){notify(error.message);update();return false;}
  busy=true;update();
  try{
   // Mac commits wait for native disk acknowledgement. A failed save leaves
   // both the current board and its history intact, with the bridge recovery copy.
   if(!globalThis.mouseCompanionMac?.commitCanvasHistory)throw Error('画布撤回需要本机保存连接；原内容未修改。');
   const expected=JSON.stringify(state);await mouseCompanionMac.commitCanvasHistory(token.next,expected);
   engine.finish(token,state);relationUndoRecord=null;globalThis.cuppaCanvasTools?.resetHistory?.();
   selected=null;activeEdge=null;clearMarqueeSelection();hidePort();hideTagTools();
   renderCards();renderRegions();renderSide();sync();updateView();
   const message=(isRedo?'已重做':'已撤回')+'「'+token.entry.label+'」';status.textContent=message;notify(message);return true;
  }catch(error){status.textContent=error.message;notify(error.message||'撤回未完成，原内容仍保留。');return false;}
  finally{busy=false;update();}
 }
 function keyCommand(isRedo){if(location.hash!=='#cuppa'||workspace.hidden||editing()||document.querySelector('dialog[open]'))return false;run(isRedo);return true;}
 globalThis.cuppaCanvasHistory=Object.freeze({record:(next,name)=>{if(!busy)engine.record(next,name);update();},external:next=>{engine.external(next);update();},reset:next=>{engine.reset(next);update();},run,keyCommand,update,status:()=>({...engine.status(),busy})});
 undo.onclick=()=>run(false);redo.onclick=()=>run(true);
 // Leave native text editing, IME composition and form undo untouched.
 window.addEventListener('keydown',event=>{if(event.isComposing||event.altKey||!(event.metaKey||event.ctrlKey)||event.key.toLowerCase()!=='z'||editing())return;if(keyCommand(event.shiftKey)){event.preventDefault();event.stopImmediatePropagation();}},true);
 update();
})();

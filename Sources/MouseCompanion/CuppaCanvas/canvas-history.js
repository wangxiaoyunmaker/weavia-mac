/* Session-only canvas history. Content snapshots deliberately exclude project
 * memory, tray state, native receipts, search drafts and persistence metadata. */
(function(root){
 'use strict';
 const clone=value=>JSON.parse(JSON.stringify(value));
 const fields=['cards','connections','regions','canvasInk'];
 function content(state){const value={};for(const key of fields)if(state[key]!==undefined)value[key]=clone(state[key]);return value;}
 function equal(a,b){return JSON.stringify(a)===JSON.stringify(b);}
 function label(before,after){
  const a=before.cards||[],b=after.cards||[],old=new Set(a.map(c=>c.id)),now=new Set(b.map(c=>c.id));
  if(a.some(c=>!now.has(c.id)))return '删除卡片';
  if(b.some(c=>!old.has(c.id)))return '添加卡片';
  if(!equal(before.connections,after.connections))return '修改连线';
  if(!equal(before.regions,after.regions))return '修改区域';
  if(!equal(before.canvasInk,after.canvasInk))return '画笔批注';
  const changed=b.filter(c=>!equal(c,a.find(v=>v.id===c.id)));
  if(changed.length&&changed.every(c=>{const prior=a.find(v=>v.id===c.id);return equal({...prior,x:c.x,y:c.y},c);}))return '移动卡片';
  if(changed.length&&changed.every(c=>{const prior=a.find(v=>v.id===c.id);return equal({...prior,tags:c.tags,smartTags:c.smartTags},c);}))return '修改标签';
  return '编辑卡片';
 }
 function create(initial,{limit=80,maxBytes=16*1024*1024}={}){
  let baseline=content(initial),past=[],future=[],size=0;
  const trim=()=>{while(past.length>limit||size>maxBytes){const item=past.shift();if(!item)break;size-=item.bytes;}};
  function reset(state){baseline=content(state);past=[];future=[];size=0;}
  function external(state){const next=content(state);if(!equal(next,baseline))reset(state);}
  function record(state,name){const next=content(state);if(equal(next,baseline))return false;const entry={before:baseline,after:next,label:name||label(baseline,next)};entry.bytes=JSON.stringify(entry).length*2;past.push(entry);size+=entry.bytes;future=[];baseline=next;trim();return true;}
  function prepare(state,redo=false){const stack=redo?future:past,entry=stack.at(-1);if(!entry)throw Error(redo?'暂无可重做的画布操作。':'暂无可撤回的画布操作。');const expected=redo?entry.before:entry.after;if(!equal(content(state),expected))throw Error('画布已有其他修改，未覆盖新内容。请先保存当前编辑。');const next=clone(state),target=redo?entry.after:entry.before;for(const key of fields){if(Object.hasOwn(target,key))next[key]=clone(target[key]);else delete next[key];}return {next,entry,redo};}
  function finish(token,committed){const from=token.redo?future:past,to=token.redo?past:future;if(from.at(-1)!==token.entry||!equal(content(committed),token.redo?token.entry.after:token.entry.before))throw Error('撤回历史已变化，未继续操作。');from.pop();to.push(token.entry);size+=token.redo?token.entry.bytes:-token.entry.bytes;baseline=content(committed);trim();}
  return {record,external,reset,prepare,finish,status:()=>({canUndo:past.length>0,canRedo:future.length>0,undoLabel:past.at(-1)?.label||'',redoLabel:future.at(-1)?.label||'',undoCount:past.length,redoCount:future.length})};
 }
 root.WeaviaCanvasHistory={create,content};
 if(typeof module==='object')module.exports=root.WeaviaCanvasHistory;
})(typeof window==='object'?window:globalThis);

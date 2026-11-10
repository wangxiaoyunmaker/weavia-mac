/* One native-confirmed work mode drives both search behavior and proactive help. */
(() => {
  const root=document.querySelector('#work-mode-switch');if(!root)return;
  const buttons=[...root.querySelectorAll('[data-work-mode]')],status=root.querySelector('#work-mode-status');
  let available=false,mode='',nativePending=false,request=null,notice='',error=false,sequence=0,timer,nativeRevision=null,settle=null;
  const settings=[...document.querySelectorAll('[data-open-settings]')];
  const pageNonce=Math.random().toString(36).slice(2,12);
  const valid=value=>value==='focus'||value==='cocreate';
  const label=value=>value==='focus'?'专注':'共创';
  const detail=value=>value==='focus'?'单平台搜索，不主动生成建议':'多来源搜索，允许待采纳建议，不自动保存';
  function render(){
    const pending=!!request||nativePending;root.setAttribute('aria-busy',String(pending));
    const current=available&&valid(mode)?'当前：'+label(mode)+'模式':'正在确认工作模式';
    root.setAttribute('aria-label',current);
    root.title=!available?'请在鸿蒙应用中切换工作模式':current+' · '+detail(mode)+(pending?' · 正在确认':'');
    if(available&&valid(mode))applySearchMode(mode==='cocreate'?'agent':'personal');
    buttons.forEach(button=>{
      const selected=available&&button.dataset.workMode===mode,name=label(button.dataset.workMode);
      button.disabled=!available||pending;
      button.setAttribute('aria-pressed',String(selected));button.classList.toggle('selected',selected);
      button.setAttribute('aria-label',name+'模式'+(selected?'，当前已选':''));
      button.title=name+'模式'+(selected?'（当前）':'')+'：'+detail(button.dataset.workMode);
    });
    settings.forEach(button=>{button.disabled=!available||pending;button.setAttribute('aria-busy',String(!!request&&request.action==='settings'));});
    status.textContent=notice;status.hidden=!notice;status.dataset.error=String(error);
  }
  function finish(value=false){const resolve=settle;settle=null;resolve?.(value);}
  function clear(){clearTimeout(timer);request=null;nativePending=false;finish(false);render();}
  function begin(next){
    if(!valid(next))return Promise.resolve(false);
    if(!available||request||nativePending){notice=!available?'工作模式尚未确认，请稍后重试。':'工作模式正在更新，请稍后重试。';error=false;render();return Promise.resolve(false)}
    if(next===mode)return Promise.resolve(true);
    notice='';error=false;request={token:'wm:'+Date.now()+':'+pageNonce+':'+(++sequence),mode:next};
    const token=request.token,result=new Promise(resolve=>{settle=resolve});render();
    timer=setTimeout(()=>{if(request?.token!==token)return;request=null;nativePending=false;notice='未收到模式确认，请重试。当前状态以已显示模式为准。';error=true;finish(false);render();},12000);
    return result;
  }
  buttons.forEach(button=>button.addEventListener('click',()=>{void begin(button.dataset.workMode)}));
  settings.forEach(button=>button.addEventListener('click',()=>{
    if(!available||request||nativePending)return;
    notice='';error=false;request={token:'wm:'+Date.now()+':'+pageNonce+':'+(++sequence),action:'settings'};render();
    const token=request.token;timer=setTimeout(()=>{if(request?.token!==token)return;request=null;nativePending=false;notice='设置未能打开，请重试。';error=true;render();},12000);
  }));
  globalThis.cuppaWorkModeV1=Object.freeze({
    request:begin,
    peek(){return request?{...request}:null;},
    sync(value){if(!value||typeof value.available!=='boolean'||(value.available&&!valid(value.mode)))return false;
      available=value.available;nativePending=!!value.pending;if(valid(value.mode))mode=value.mode;
      if(Number.isInteger(value.revision)&&value.revision>=0&&value.revision!==nativeRevision){nativeRevision=value.revision;if(!value.message){notice='';error=false;}}
      if(value.message){notice=String(value.message).slice(0,240);error=value.error===true;}render();return true;},
    ack(token,value){if(!request||request.token!==token||!value||typeof value.ok!=='boolean'||!valid(value.mode))return false;
      const requested=request.mode;clearTimeout(timer);request=null;nativePending=false;mode=value.mode;notice=String(value.message||'').slice(0,240);error=!value.ok;render();finish(mode===requested);return true;}
  });
  window.addEventListener('pagehide',clear);window.addEventListener('hashchange',clear);render();
})();

/* Read durable capture snapshots before legacy scripts initialize or normalize cards. */
(async()=>{
 document.body.style.visibility='hidden';
 const id=new URLSearchParams(location.search).get('project')||'';
 try{globalThis.cuppaBootstrap=globalThis.mouseCompanionMac?mouseCompanionMac.boot(id):await CuppaCaptureStore.boot(id);if(!globalThis.mouseCompanionMac)globalThis.cuppaBootstrap.snapshot=await CuppaRelationStore.recover(id,globalThis.cuppaBootstrap.snapshot);}catch(error){globalThis.cuppaBootstrap={error:error.message};}
 try{
  for(const node of document.querySelectorAll('script[data-cuppa-src]'))await new Promise((resolve,reject)=>{const script=document.createElement('script');script.src=node.dataset.cuppaSrc;script.onload=resolve;script.onerror=()=>reject(Error('画布模块加载失败，请重新打开。'));document.body.append(script);});
  if(globalThis.cuppaBootstrap?.error){const warning=document.createElement('div');warning.textContent=cuppaBootstrap.error+' 当前画布只读，原数据未覆盖。';warning.setAttribute('role','alert');Object.assign(warning.style,{position:'fixed',top:'8px',left:'20%',right:'20%',zIndex:'9999',padding:'10px',background:'#fff2f0',color:'#a8071a',borderRadius:'8px'});document.body.append(warning);}
  globalThis.cuppaReady=true;globalThis.mouseCompanionMac?.install();
 }catch(error){const message=document.createElement('p');message.textContent=error.message;message.setAttribute('role','alert');document.body.append(message);}
 finally{document.body.style.visibility='';}
})();

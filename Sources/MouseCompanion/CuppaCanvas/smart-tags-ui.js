(function(root){
 'use strict';
 let controller=null,lastView=null;
 function setup(){
  if(controller)return;
  const panel=document.createElement('div');panel.id='tag-smart-panel';panel.hidden=true;$('#tag-popover').append(panel);
  controller=root.WeaviaSmartTags.createController({project:()=>new URLSearchParams(location.search).get('project')||'',card:id=>state.cards.find(c=>c.id===id),generate:card=>{
   if(!root.mouseCompanionMac?.requestSmartTags)throw Error('智能标签需要 Mac 版的模型接口。请先设置 Agent API；不会使用演示标签。');
   return root.mouseCompanionMac.requestSmartTags(card);
  },commit:(...args)=>root.mouseCompanionMac.commitSmartTags(...args),changed:render});
 }
 function render(view){
  lastView=view;const panel=$('#tag-smart-panel');if(!panel||view.status==='idle')return;
  const busy=['loading','saving'].includes(view.status);$('#tag-close').disabled=view.status==='saving';
  panel.setAttribute('aria-busy',busy?'true':'false');
  panel.innerHTML=`<p id="tag-smart-status" role="status" aria-live="polite">${esc(view.message||'')}</p><div id="tag-smart-list">${view.suggestions.map((row,index)=>`<div class="smart-tag-candidate"><label><input type="checkbox" data-smart-check="${index}" checked ${busy?'disabled':''} aria-label="采纳此标签"><input type="text" data-smart-label="${index}" value="${esc(row.label)}" maxlength="40" aria-label="修改候选标签" ${busy?'disabled':''}></label><p>${esc(row.reason)}</p></div>`).join('')}</div><div id="tag-smart-actions">${view.suggestions.length?`<button type="button" class="smart-tag-adopt" id="tag-smart-adopt" ${busy?'disabled':''}>采纳所选</button>`:''}<button type="button" id="tag-smart-retry" ${busy?'disabled':''}>${view.status==='error'?'重试':'重新生成'}</button><button type="button" id="tag-smart-manual" ${view.status==='saving'?'disabled':''}>手动添加</button>${view.status==='loading'?'<button type="button" id="tag-smart-stop">中止</button>':''}</div><p id="tag-smart-provider">${esc(view.provider||'使用已设置的 Agent API；生成前可确认发送范围。')}${view.provider?' · '+(view.inputMode==='image_and_text'?'图片和文字':'仅文字，未分析图片'):''}</p>`;
  const adopt=$('#tag-smart-adopt');if(adopt)adopt.onclick=()=>{
   const rows=view.suggestions.flatMap((row,index)=>panel.querySelector(`[data-smart-check="${index}"]`).checked?[{label:panel.querySelector(`[data-smart-label="${index}"]`).value,reason:row.reason,originalLabel:row.label}]:[]);
   if(!rows.length){$('#tag-smart-status').textContent='请选择至少一个标签。';return;}
   controller.accept(rows).then(saved=>{if(saved){const c=activeTagCard();if(c)renderTagList(c);positionTagTools();}});
  };
  $('#tag-smart-retry').onclick=()=>{const c=activeTagCard();if(c)controller.begin(c);};
  $('#tag-smart-manual').onclick=()=>openTagEditor();
  const stop=$('#tag-smart-stop');if(stop)stop.onclick=()=>{controller.close();render({status:'error',suggestions:[],message:'已中止生成，未添加任何标签。'});};
  positionTagTools();
 }
 function open(card){setup();controller.close();$('#tag-popover').hidden=false;$('#tag-popover').classList.add('smart-tag-mode');$('#tag-popover-title').textContent='智能标签';$('#tag-form').hidden=true;$('#tag-smart-panel').hidden=false;renderTagList(card);controller.begin(card);}
 function close(){controller?.close();const panel=$('#tag-smart-panel');if(panel)panel.hidden=true;$('#tag-popover')?.classList.remove('smart-tag-mode');if($('#tag-form'))$('#tag-form').hidden=false;if($('#tag-close'))$('#tag-close').disabled=false;lastView=null;}
 root.WeaviaSmartTagUI={open,close};
})(globalThis);

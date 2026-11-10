function seedAiExcerptExamples(){
 if(projectId||state.aiExcerptExamplesAdded)return;
 const examples=[
  {
   provider:'chatgpt', title:'机器人在哪些场景能帮上忙？', question:'机器人适合哪些使用场景？', tags:['使用场景'],
   text:`| 场景 | 机器人做什么 |
| --- | --- |
| 🏠 家庭生活 | 整理、取物、收纳、倒水 |
| 🦽 老人／特殊人群辅助 | 递东西、取药、开门 |
| 🏢 办公空间 | 整理桌面、递文件、找物品 |
| 🍽️ 餐饮服务 | 取餐、送餐、收拾桌面 |
| 📦 仓储物流 | 搬运、分拣、装箱 |
| 🏭 工业制造 | 装配、检测、协作 |
| 🧪 实验室 | 拿取器材、实验操作 |
| 🌳 户外／公共空间 | 巡检、导航、寻找物体 |`
  },
  {
   provider:'doubao', title:'让第一次做咖啡更容易开始', question:'怎么让新手更愿意试做一杯咖啡？', tags:['新手引导','交互文案'],
   text:`**先让用户做出第一杯，再解释参数。**

首页只问「今天想喝什么？」选择拿铁后，直接显示杯量、预计用时和第一步。研磨度、温度等设置收在「调整配方」里。

完成后再问一句「这一杯怎么样？」用简单的口味选项帮用户调整下一杯。`
  },
  {
   provider:'deepseek', title:'咖啡机异常时的三步恢复路径', question:'咖啡机缺水时该怎么引导用户？', tags:['异常恢复'],
   text:`1. **说明现状。** 显示「水量不足，制作已暂停」，并标明当前进度。
2. **给出下一步。** 提示「请给水箱加水，再放回原位」。配图只标出水箱的位置。
3. **允许继续。** 水箱放回后显示「继续制作」，保留已经完成的步骤。`
  }
 ];
 const columns=innerWidth>=1180?[300,604,908]:innerWidth>=880?[300,604]:[300];
 const addedAt=new Date();
 let row=0,column=0;
 for(const example of examples){
  let x,y;
  do{
   x=columns[column];
   y=134+row*338;
   column++;
   if(column===columns.length){column=0;row++}
  }while(state.cards.some(c=>{
   const width=c.expanded?620:273,height=c.expanded?445:273;
   return x<c.x+width+12&&x+285>c.x&&y<c.y+height+12&&y+285>c.y;
  }));
  const id='ai-example-'+example.provider;
  state.aiThreads.push({id,provider:example.provider,title:example.title,question:example.question});
  state.cards.push({
   id,type:'source',subtype:'ai-excerpt',title:example.title,text:example.question+'\n\n'+example.text,
   addedBy:'personal',x,y,tags:example.tags,url:'',
   time:addedAt.toLocaleTimeString('zh-CN',{hour:'2-digit',minute:'2-digit'}),
   ai:{provider:example.provider,threadId:id,mode:'excerpt',question:example.question,
    blocks:parseAiExcerptBlocks(example.text),originalText:example.text,capturedAt:addedAt.toISOString(),example:true}
  });
 }
 state.aiExcerptExamplesAdded=true;
 save();
}

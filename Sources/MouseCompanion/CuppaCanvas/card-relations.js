/* User-authored annotations only. No inference, network calls or memory promotion. */
(function(root){
 'use strict';
 const kinds={related:'普通关联',similar:'相似',different:'差异',complementary:'互补',conflicting:'冲突',custom:'自定义'};
 const object=x=>!!x&&typeof x==='object'&&!Array.isArray(x);
 function supported(edge){
  if(!Object.prototype.hasOwnProperty.call(edge,'relation'))return true;
  const r=edge.relation;
  return object(r)&&r.version===1&&r.source==='user'&&Object.hasOwn(kinds,r.kind)&&
   typeof r.customLabel==='string'&&typeof r.evidence==='string'&&['pending','confirmed'].includes(r.status)&&
   Array.isArray(r.history)&&r.history.every(object);
 }
 function fields(edge){const r=supported(edge)&&edge.relation;return {kind:r?r.kind:'related',customLabel:r?r.customLabel:'',evidence:r?r.evidence:''};}
 function view(edge){
  if(!supported(edge))return {label:'暂不支持的关系',status:'unsupported',statusLabel:'保留原数据'};
  if(!edge.relation)return {label:'普通连线',status:'legacy',statusLabel:'未标注'};
  const r=edge.relation;return {label:r.kind==='custom'?r.customLabel:kinds[r.kind],status:r.status,statusLabel:r.status==='confirmed'?'已确认':'待确认'};
 }
 function validate(input){
  if(!object(input)||!Object.hasOwn(kinds,input.kind)||typeof input.customLabel!=='string'||typeof input.evidence!=='string')throw Error('关系格式不正确。');
  if(input.customLabel.length>40||input.evidence.length>4000)throw Error('关系名称最多 40 字，依据最多 4000 字。');
  if(input.kind==='custom'&&!input.customLabel.trim())throw Error('请填写自定义关系名称。');
  return {kind:input.kind,customLabel:input.kind==='custom'?input.customLabel.trim():'',evidence:input.evidence.trim()};
 }
 function update(edge,input,decision,now){
  if(!supported(edge))throw Error('关系记录的版本或格式暂不支持编辑，原数据已保留。');
  if(!['keep','confirm','withdraw'].includes(decision))throw Error('确认状态不正确。');
  const f=validate(input),prior=edge.relation,changed=JSON.stringify(f)!==JSON.stringify(fields(edge));
  if(decision==='confirm'&&!f.evidence)throw Error('明确确认前，请补充支持这一判断的依据。');
  const status=decision==='confirm'?'confirmed':decision==='withdraw'||changed||!prior?'pending':prior.status;
  if(prior&&!changed&&status===prior.status)return edge;
  const event={at:now,action:!prior?'annotated':changed?'edited':status==='confirmed'?'confirmed':'withdrawn',kind:f.kind,customLabel:f.customLabel,evidence:f.evidence,status};
  return {...edge,relation:{...prior,version:1,source:'user',...f,status,createdAt:prior?.createdAt||now,updatedAt:now,confirmedAt:status==='confirmed'?(decision==='confirm'?now:prior?.confirmedAt||null):null,history:[...(prior?.history||[]),event]}};
 }
 function pairExists(edges,from,to,except){return edges.find(e=>e.id!==except&&((e.from===from&&e.to===to)||(e.from===to&&e.to===from)));}
 root.CardRelations={kinds,supported,fields,view,validate,update,pairExists};
 if(typeof module==='object')module.exports=root.CardRelations;
})(typeof window==='object'?window:globalThis);

/* Private tray images: immutable metadata in state, validated derived pixels in IDB,
 * and revocable Blob URLs only in this module's memory. Never reads original files. */
(function(root){
 'use strict';
 const MAX_BYTES=2*1024*1024,MAX_PIXELS=40000000,SHA=/^[a-f0-9]{64}$/,PREFIX='data:image/png;base64,';
 const urls=new Map(),errors=new Map();
 const integer=(n,max)=>Number.isSafeInteger(n)&&n>0&&n<=max;
 const keys=(value,names)=>value&&typeof value==='object'&&!Array.isArray(value)&&Object.keys(value).length===names.length&&names.every(k=>Object.hasOwn(value,k));
 function metadata(m){
  const snapshot=m?.version===2;
  if(!keys(m,snapshot?['version','representation','assetId','mime','byteLength','width','height','snapshotFileName','preview']:['version','assetId','mime','byteLength','width','height','originalFileName','preview'])||(!snapshot&&m.version!==1)||(snapshot&&(m.representation!=='clipboard_pixel_snapshot'||m.mime!=='image/png'))||!SHA.test(m.assetId)||!['image/png','image/jpeg','image/webp'].includes(m.mime)||!integer(m.byteLength,20*1024*1024)||!integer(m.width,32768)||!integer(m.height,32768)||m.width*m.height>MAX_PIXELS)throw Error('图片资产信息无效，素材仍保留在托盘。');
  const suffix={'image/png':'.png','image/jpeg':'.jpg','image/webp':'.webp'}[m.mime];
  if((snapshot?m.snapshotFileName:m.originalFileName)!==m.assetId+suffix)throw Error('图片文件标识无效。');
  const p=m.preview;if(!keys(p,['id','fileName','mime','byteLength','width','height'])||!SHA.test(p.id)||p.fileName!==p.id+'.png'||p.mime!=='image/png'||!integer(p.byteLength,MAX_BYTES)||!integer(p.width,1536)||!integer(p.height,1536))throw Error('图片预览信息无效。');
  return m;
 }
 const image=c=>c?.companionCapture?.material?.image;
 const isPrivate=c=>image(c)!==undefined;
 const assetKey=id=>['tray-image-preview-v1',id];
 const crcTable=Array.from({length:256},(_,n)=>{for(let i=0;i<8;i++)n=(n&1)?0xedb88320^(n>>>1):n>>>1;return n>>>0});
 function crc(bytes,start,end){let c=0xffffffff;for(let i=start;i<end;i++)c=crcTable[(c^bytes[i])&255]^(c>>>8);return(c^0xffffffff)>>>0}
 function png(bytes,p){
  if(bytes.length!==p.byteLength||bytes.length<57||![137,80,78,71,13,10,26,10].every((v,i)=>bytes[i]===v))throw Error('图片预览格式或大小不符。');
  const view=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength),allowed=new Set(['IHDR','PLTE','tRNS','IDAT','IEND','cHRM','gAMA','sRGB','sBIT','bKGD','pHYs']);
  let offset=8,idat=false,end=false,closed=false,header=false,color,depth,palette=0;const seen=new Set();
  while(offset<bytes.length){
   if(offset+12>bytes.length)throw Error('图片预览结构不完整。');
   const size=view.getUint32(offset),next=offset+12+size,type=String.fromCharCode(...bytes.subarray(offset+4,offset+8));
   if(next>bytes.length||!allowed.has(type)||crc(bytes,offset+4,next-4)!==view.getUint32(next-4))throw Error('图片预览结构或校验不符。');
   if(!header){if(type!=='IHDR'||size!==13||view.getUint32(offset+8)!==p.width||view.getUint32(offset+12)!==p.height||bytes[offset+18]!==0||bytes[offset+19]!==0||bytes[offset+20]>1)throw Error('图片预览尺寸不符。');depth=bytes[offset+16];color=bytes[offset+17];if(!({0:[1,2,4,8,16],2:[8,16],3:[1,2,4,8],4:[8,16],6:[8,16]})[color]?.includes(depth))throw Error('图片预览像素格式无效。');header=true;}
   else if(type==='IHDR')throw Error('图片预览包含重复头部。');
   if(!['IHDR','IDAT','IEND'].includes(type)){
    if(idat)throw Error('图片预览颜色信息顺序无效。');
    const fixed={cHRM:32,gAMA:4,sRGB:1,pHYs:9};if(fixed[type]!==undefined&&size!==fixed[type])throw Error('图片预览颜色信息长度无效。');
    if(['cHRM','gAMA','sRGB','sBIT'].includes(type)&&palette)throw Error('图片预览颜色信息顺序无效。');
    if(type==='PLTE'){if(!size||size>768||size%3||[0,4].includes(color))throw Error('图片预览调色板无效。');palette=size/3;if(color===3&&palette>2**depth)throw Error('图片预览调色板过大。');}
    if(type==='sBIT'&&(size!==({0:1,2:3,3:3,4:2,6:4})[color]||bytes.subarray(offset+8,offset+8+size).some(v=>v<1||v>(color===3?8:depth))))throw Error('图片预览精度信息无效。');
    if(type==='bKGD'&&(size!==(color===3?1:[0,4].includes(color)?2:6)||(color===3&&(!palette||bytes[offset+8]>=palette))))throw Error('图片预览背景信息无效。');
    if(type==='tRNS'&&(color===3?(!palette||!size||size>palette):size!==({0:2,2:6})[color]))throw Error('图片预览透明信息无效。');
    if(type==='sRGB'&&bytes[offset+8]>3||type==='pHYs'&&bytes[offset+16]>1||type==='gAMA'&&view.getUint32(offset+8)===0)throw Error('图片预览颜色信息无效。');
   }
   if(type==='IDAT'){if(color===3&&!palette)throw Error('图片预览缺少调色板。');if(closed)throw Error('图片预览数据顺序无效。');idat=true;}
   else {if(idat)closed=true;if(seen.has(type))throw Error('图片预览包含重复块。');seen.add(type);}
   if(type==='IEND'){if(size!==0||!idat||next!==bytes.length)throw Error('图片预览尾部无效。');end=true;}
   offset=next;
  }
  if(!end)throw Error('图片预览缺少尾部。');
 }
 async function validateBlob(blob,m){
  metadata(m);const p=m.preview;if(!(blob instanceof Blob)||blob.type!=='image/png'||blob.size!==p.byteLength)throw Error('已保存的图片预览缺失或损坏，原素材仍在托盘。');
  const bytes=new Uint8Array(await blob.arrayBuffer());png(bytes,p);
  if(!root.crypto?.subtle)throw Error('当前环境无法校验图片，请保留托盘素材后重试。');
  const hash=Array.from(new Uint8Array(await root.crypto.subtle.digest('SHA-256',bytes)),x=>x.toString(16).padStart(2,'0')).join('');
  if(hash!==p.id)throw Error('图片预览内容校验失败，未保存卡片。');
  // Header dimensions are bounded before decoding compressed pixels.
  const url=URL.createObjectURL(blob);
  try{await new Promise((resolve,reject)=>{const img=new Image(),timer=setTimeout(()=>{img.src='';reject(Error('图片预览解码超时。'));},10000);img.onload=()=>{clearTimeout(timer);img.naturalWidth===p.width&&img.naturalHeight===p.height?resolve():reject(Error('图片预览实际尺寸不符。'))};img.onerror=()=>{clearTimeout(timer);reject(Error('图片预览无法解码。'))};img.src=url;});}finally{URL.revokeObjectURL(url);}
  return {version:1,id:p.id,mime:'image/png',width:p.width,height:p.height,byteLength:p.byteLength,blob};
 }
 async function prepare(payload){
  const m=payload?.material?.image;
  if(m===undefined){if(payload?.imagePreview!==undefined)throw Error('图片预览缺少对应素材。');return null;}
  metadata(m);const transfer=payload.imagePreview;
  if(!keys(transfer,['id','dataURL'])||transfer.id!==m.preview.id||typeof transfer.dataURL!=='string'||!transfer.dataURL.startsWith(PREFIX)||transfer.dataURL.length>PREFIX.length+4*Math.ceil(MAX_BYTES/3))throw Error('图片预览未就绪或过大，素材仍保留在托盘。');
  const encoded=transfer.dataURL.slice(PREFIX.length);if(encoded.length%4!==0||!/^[A-Za-z0-9+/]*={0,2}$/.test(encoded))throw Error('图片预览编码无效。');
  const binary=atob(encoded);if(binary.length!==m.preview.byteLength||btoa(binary)!==encoded)throw Error('图片预览字节数不符。');
  return validateBlob(new Blob([Uint8Array.from(binary,c=>c.charCodeAt(0))],{type:'image/png'}),m);
 }
 async function stored(record,m){metadata(m);const p=m.preview;if(!record||record.version!==1||record.id!==p.id||record.mime!==p.mime||record.width!==p.width||record.height!==p.height||record.byteLength!==p.byteLength)throw Error('已保存的图片预览缺失或损坏，原素材仍在托盘。');return validateBlob(record.blob,m);}
 function install(record){if(!record)return;const old=urls.get(record.id);if(old)URL.revokeObjectURL(old);urls.set(record.id,URL.createObjectURL(record.blob));errors.delete(record.id);}
 async function hydrate(snapshot,read){
  const wanted=new Map();for(const c of snapshot.cards||[])if(isPrivate(c)){const m=image(c);try{metadata(m);wanted.set(m.preview.id,m)}catch(e){errors.set(m?.preview?.id||c.id,e.message)}}
  // Bound simultaneous pixel decodes even for a large saved tray. A broken
  // preview is reported per card and never prevents loading unrelated material.
  const entries=[...wanted];let next=0;
  await Promise.all(Array.from({length:Math.min(2,entries.length)},async()=>{while(next<entries.length){const [id,m]=entries[next++];try{install(await stored(await read(assetKey(id)),m))}catch(e){if(urls.has(id)){URL.revokeObjectURL(urls.get(id));urls.delete(id)}errors.set(id,e.message)}}}));
 }
 function source(c){try{metadata(image(c));return urls.get(image(c).preview.id)||''}catch{return ''}}
 function warning(snapshot){return (snapshot.cards||[]).some(c=>isPrivate(c)&&!source(c))?'图片预览暂不可用；已保存卡片与托盘素材仍保留。':''}
 function error(c){return errors.get(image(c)?.preview?.id||c?.id)||'图片预览暂不可用；素材仍保留在托盘。'}
 root.addEventListener('pagehide',event=>{if(event.persisted)return;urls.forEach(url=>URL.revokeObjectURL(url));urls.clear()});
 root.CuppaTrayImageAssets=Object.freeze({metadata,isPrivate,image,key:assetKey,prepare,stored,install,hydrate,source,error,warning});
})(globalThis);

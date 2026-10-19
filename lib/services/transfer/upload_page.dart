const uploadPage = r'''<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Upload to CrisperPlayer</title>
<style>body{font:18px system-ui;background:#15171c;color:#eee;max-width:650px;margin:3rem auto;padding:20px}input,button{font:inherit;max-width:100%;padding:10px;margin:8px 0;box-sizing:border-box}label{display:block}button{cursor:pointer;background:#adc6ff;border:0;border-radius:8px}progress{width:100%}#status{white-space:pre-wrap;overflow-wrap:anywhere}small{color:#bbc}</style>
<h1>Upload audiobooks</h1><p>Keep CrisperPlayer open on your device. Use a trusted local network: this connection uses HTTP.</p>
<label>Access code shown in the app<input id="code" type="password" autocomplete="off" spellcheck="false"></label>
<label>Book title (optional)<input id="title" maxlength="200"></label>
<label>Audio files for one book<input id="files" type="file" multiple accept=".m4b,.m4a,.mp3,.flac,.ogg,.wav,.aac,.opus,.wma,.aiff,.aif,.mp2,.mov,.webm,.3gp,.mkv,.mka"></label>
<p><small>Tracks are naturally sorted by filename. Large files resume at completed 8 MiB chunks when you retry the same selection without closing this page. Up to 4 GiB per file, 20 GiB per book, 500 files. Upload each book separately.</small></p>
<button id="send">Upload and import book</button><progress id="progress" value="0" max="100"></progress><p id="status" role="status" aria-live="polite"></p>
<script>
const el=id=>document.getElementById(id);
const pairing=new URLSearchParams(location.hash.slice(1)).get('code');
if(pairing&&/^[a-f0-9]{40}$/.test(pairing))el('code').value=pairing;
if(location.hash)history.replaceState(null,'',location.pathname);

const pendingUploads=new WeakMap();
let importAttempt=null;
el('files').onchange=()=>{importAttempt=null;};
function success(){el('status').textContent='Book imported. It is ready in your device library.';el('files').value='';el('title').value='';importAttempt=null;el('progress').value=100;}

async function api(method,url,code){
const response=await fetch(url,{method,headers:{Authorization:'Bearer '+code}});
const result=await response.json();if(!response.ok)throw Error(result.error||'Transfer failed');return result;
}
function sendBytes(body,url,code,index,total,offset,fileSize,method='PUT'){return new Promise((resolve,reject)=>{
const x=new XMLHttpRequest();x.open(method,url);x.setRequestHeader('Authorization','Bearer '+code);x.timeout=30*60*1000;
x.upload.onprogress=e=>{if(e.lengthComputable)el('progress').value=100*(index+(offset+e.loaded)/fileSize)/total;};
x.onload=()=>{try{const result=JSON.parse(x.responseText);if(x.status!==200)throw Error(result.error||'Upload failed');resolve(result);}catch(e){reject(e);}};
x.onerror=()=>reject(Error('Connection lost. Keep the app open and retry.'));x.ontimeout=()=>reject(Error('Upload timed out. Retry.'));x.send(body);
});}
async function upload(file,code,index,total){
const chunkSize=8*1024*1024;
if(file.size<=chunkSize)return sendBytes(file,'/upload?name='+encodeURIComponent(file.name),code,index,total,0,file.size);
let state=pendingUploads.get(file);
if(state){state=await api('GET','/upload?id='+encodeURIComponent(state.id),code);}
else{state=await api('POST','/upload?name='+encodeURIComponent(file.name)+'&size='+file.size,code);pendingUploads.set(file,state);}
while(state.offset<file.size){
const end=Math.min(state.offset+chunkSize,file.size);
const result=await sendBytes(file.slice(state.offset,end),'/upload?id='+encodeURIComponent(state.id)+'&offset='+state.offset,code,index,total,state.offset,file.size,'PATCH');
if(result.offset!==end)throw Error('Upload position mismatch. Retry.');state={...state,...result};pendingUploads.set(file,state);
}
}
el('send').onclick=async()=>{
const files=Array.from(el('files').files),code=el('code').value.trim();
if(!code||!files.length){el('status').textContent='Enter your access code and select audio files.';return;}
if(new Set(files.map(f=>f.name)).size!==files.length){el('status').textContent='Files must have unique names.';return;}
el('send').disabled=true;el('files').disabled=true;el('title').disabled=true;el('code').disabled=true;el('progress').value=0;
try{if(importAttempt){const known=await api('GET','/import?operation='+importAttempt,code);if(known.imported){success();return;}}
for(let i=0;i<files.length;i++){el('status').textContent='Uploading '+(i+1)+'/'+files.length+': '+files[i].name;await upload(files[i],code,i,files.length);el('progress').value=100*(i+1)/files.length;}
el('status').textContent='Importing book on your device…';
importAttempt=importAttempt||Date.now().toString(36)+'-'+Math.random().toString(36).slice(2)+'-'+Math.random().toString(36).slice(2);
const response=await fetch('/import?operation='+importAttempt+'&title='+encodeURIComponent(el('title').value),{method:'POST',headers:{Authorization:'Bearer '+code}});
const result=await response.json();if(!response.ok)throw Error(result.error||'Import failed');
success();
}catch(e){el('status').textContent=e.message+' Retry the same files, or stop and restart sharing to discard the unfinished book.';}finally{el('send').disabled=false;el('files').disabled=false;el('title').disabled=false;el('code').disabled=false;}
};
</script></html>''';

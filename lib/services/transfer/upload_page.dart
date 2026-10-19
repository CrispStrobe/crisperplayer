const uploadPage = r'''<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Upload to CrisperPlayer</title>
<style>body{font:18px system-ui;background:#15171c;color:#eee;max-width:650px;margin:3rem auto;padding:20px}input,button{font:inherit;max-width:100%;padding:10px;margin:8px 0;box-sizing:border-box}label{display:block}button{cursor:pointer;background:#adc6ff;border:0;border-radius:8px}progress{width:100%}#status{white-space:pre-wrap;overflow-wrap:anywhere}small{color:#bbc}</style>
<h1>Upload audiobooks</h1><p>Keep CrisperPlayer open on your device. Use a trusted local network: this connection uses HTTP.</p>
<label>Access code shown in the app<input id="code" type="password" autocomplete="off" spellcheck="false"></label>
<label>Book title (optional)<input id="title" maxlength="200"></label>
<label>Audio files for one book<input id="files" type="file" multiple accept=".m4b,.m4a,.mp3,.flac,.ogg,.wav,.aac,.opus,.wma,.aiff,.aif,.mp2,.mov,.webm,.3gp,.mkv,.mka"></label>
<p><small>Tracks are naturally sorted by filename. Up to 4 GiB per file, 20 GiB per book, 500 files. Upload each book separately.</small></p>
<button id="send">Upload and import book</button><progress id="progress" value="0" max="100"></progress><p id="status" role="status" aria-live="polite"></p>
<script>
const el=id=>document.getElementById(id);
function upload(file,code,index,total){return new Promise((resolve,reject)=>{
const x=new XMLHttpRequest(); x.open('PUT','/upload?name='+encodeURIComponent(file.name));
x.setRequestHeader('Authorization','Bearer '+code);x.timeout=30*60*1000;
x.upload.onprogress=e=>{if(e.lengthComputable)el('progress').value=100*(index+e.loaded/e.total)/total;};
x.onload=()=>{try{const r=JSON.parse(x.responseText);if(x.status!==200)throw Error(r.error||'Upload failed');resolve();}catch(e){reject(e);}};
x.onerror=()=>reject(Error('Connection lost. Keep the app open and retry.'));x.ontimeout=()=>reject(Error('Upload timed out. Retry.'));x.send(file);
});}
el('send').onclick=async()=>{
const files=Array.from(el('files').files),code=el('code').value.trim();
if(!code||!files.length){el('status').textContent='Enter your access code and select audio files.';return;}
if(new Set(files.map(f=>f.name)).size!==files.length){el('status').textContent='Files must have unique names.';return;}
el('send').disabled=true;el('progress').value=0;
try{for(let i=0;i<files.length;i++){el('status').textContent='Uploading '+(i+1)+'/'+files.length+': '+files[i].name;await upload(files[i],code,i,files.length);}
el('status').textContent='Importing book on your device…';
const response=await fetch('/import?title='+encodeURIComponent(el('title').value),{method:'POST',headers:{Authorization:'Bearer '+code}});
const result=await response.json();if(!response.ok)throw Error(result.error||'Import failed');
el('status').textContent='Book imported. It is ready in your device library.';el('files').value='';el('title').value='';
}catch(e){el('status').textContent=e.message+' Retry the same files, or stop and restart sharing to discard the unfinished book.';}finally{el('send').disabled=false;}
};
</script></html>''';

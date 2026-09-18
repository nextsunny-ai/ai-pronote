(function () {
  'use strict';
  const DB_NAME = 'pronote-ink-v1';
  const STORE = 'documents';
  const canvas = document.getElementById('inkCanvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  const textPanel = document.getElementById('mynoteBlockContent');
  const inkPanel = document.getElementById('inkPanel');
  const textTab = document.getElementById('noteModeText');
  const inkTab = document.getElementById('noteModeInk');
  const anchors = document.getElementById('inkTimeAnchors');
  const doc = { schemaVersion: 1, meetingId: '', updatedAt: '', strokes: [] };
  let redoStack = [], active = null, activePointerId = null, tool = 'pen', saveTimer = 0;
  let loadedMeetingId = '', loadGeneration = 0;
  let saveQueue = Promise.resolve(), switchQueue = Promise.resolve(), switchGeneration = 0, clearing = false;

  function meetingId() {
    return localStorage.getItem('ai_pronote.current_view_meeting.v1') || 'draft';
  }
  function audioElement() {
    return document.querySelector('#view-result audio, #resultAudio, audio[data-meeting-audio]');
  }
  function audioMs() {
    const audio = audioElement();
    return audio && Number.isFinite(audio.currentTime) ? Math.round(audio.currentTime * 1000) : 0;
  }
  function openDb() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(DB_NAME, 1);
      request.onupgradeneeded = () => request.result.createObjectStore(STORE, { keyPath: 'meetingId' });
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }
  function save(targetMeetingId = loadedMeetingId) {
    if (!targetMeetingId || clearing) return saveQueue;
    const snapshot = {schemaVersion:1, meetingId:targetMeetingId, updatedAt:new Date().toISOString(), strokes:structuredClone(doc.strokes)};
    saveQueue=saveQueue.catch(()=>{}).then(async()=>{if(clearing)return;const preview=await new Promise(resolve=>canvas.toBlob(resolve,'image/webp',0.78));const db=await openDb();await new Promise((resolve,reject)=>{const tx=db.transaction(STORE,'readwrite');tx.objectStore(STORE).put({...snapshot,preview});tx.oncomplete=resolve;tx.onerror=()=>reject(tx.error);});db.close();});
    return saveQueue;
  }
  function scheduleSave() { const target=loadedMeetingId; clearTimeout(saveTimer); saveTimer=setTimeout(()=>save(target).catch(console.warn),250); }
  async function load(explicitTarget = meetingId()) {
    const target=explicitTarget, generation=++loadGeneration;
    const db = await openDb();
    const saved = await new Promise((resolve, reject) => {
      const request = db.transaction(STORE).objectStore(STORE).get(target);
      request.onsuccess = () => resolve(request.result); request.onerror = () => reject(request.error);
    });
    db.close(); if(clearing||generation!==loadGeneration||target!==meetingId())return;
    loadedMeetingId=target;doc.meetingId=target;doc.strokes=saved?.schemaVersion===1?structuredClone(saved.strokes||[]):[];redoStack=[];active=null;activePointerId=null;render();
  }
  function switchMeeting(target){if(!target||target===loadedMeetingId)return switchQueue;const transition=++switchGeneration;canvas.style.pointerEvents='none';canvas.setAttribute('aria-busy','true');switchQueue=switchQueue.catch(()=>{}).then(async()=>{clearTimeout(saveTimer);if(loadedMeetingId)await save(loadedMeetingId);loadGeneration++;loadedMeetingId='';await saveQueue;await load(target);}).finally(()=>{if(transition===switchGeneration){canvas.style.pointerEvents='';canvas.removeAttribute('aria-busy');}});return switchQueue;}
  async function clearAll(){clearing=true;clearTimeout(saveTimer);loadGeneration++;switchGeneration++;active=null;activePointerId=null;try{await Promise.allSettled([saveQueue,switchQueue]);const db=await openDb();await new Promise((resolve,reject)=>{const tx=db.transaction(STORE,'readwrite');tx.objectStore(STORE).clear();tx.oncomplete=resolve;tx.onerror=()=>reject(tx.error);});db.close();doc.strokes=[];redoStack=[];loadedMeetingId='';render();}finally{clearing=false;canvas.style.pointerEvents='';canvas.removeAttribute('aria-busy');}}
  async function exportDocuments(meetingIds){
    clearTimeout(saveTimer);if(loadedMeetingId)await save(loadedMeetingId);await saveQueue;
    const wanted=new Set(meetingIds||[]),db=await openDb();
    const rows=await new Promise((resolve,reject)=>{const req=db.transaction(STORE,'readonly').objectStore(STORE).getAll();req.onsuccess=()=>resolve(req.result||[]);req.onerror=()=>reject(req.error);});
    db.close();return rows.filter(row=>wanted.has(row.meetingId)).map(row=>({schemaVersion:1,meetingId:row.meetingId,updatedAt:row.updatedAt||null,strokes:structuredClone(row.strokes||[])}));
  }
  async function importDocuments(rows){
    if(!Array.isArray(rows)||!rows.length)return;
    let totalPoints=0;const tools=new Set(['pen','line','arrow','rect','ellipse']);
    const cleanRows=rows.map(row=>{if(!row||row.schemaVersion!==1||typeof row.meetingId!=='string'||!row.meetingId||!Array.isArray(row.strokes)||row.strokes.length>5000)throw new Error('펜 필기 백업 형식이 올바르지 않습니다.');const strokes=row.strokes.map(stroke=>{if(!stroke||!tools.has(stroke.tool)||typeof stroke.color!=='string'||!/^#[0-9a-f]{6}$/i.test(stroke.color)||!Number.isFinite(stroke.width)||stroke.width<0.5||stroke.width>64||!Array.isArray(stroke.points)||!stroke.points.length||stroke.points.length>10000)throw new Error('펜 필기 백업 형식이 올바르지 않습니다.');totalPoints+=stroke.points.length;if(totalPoints>200000)throw new Error('펜 필기 백업이 너무 큽니다.');const points=stroke.points.map(point=>{if(!point||!Number.isFinite(point.x)||!Number.isFinite(point.y)||Math.abs(point.x)>1000000||Math.abs(point.y)>1000000||!Number.isFinite(point.pressure)||point.pressure<0||point.pressure>1||!Number.isFinite(point.t))throw new Error('펜 필기 좌표가 올바르지 않습니다.');return{x:point.x,y:point.y,pressure:point.pressure,t:point.t};});return{id:typeof stroke.id==='string'?stroke.id:'',tool:stroke.tool,color:stroke.color,width:stroke.width,startMs:Number.isFinite(stroke.startMs)?Math.max(0,stroke.startMs):0,endMs:Number.isFinite(stroke.endMs)?Math.max(0,stroke.endMs):0,pointerType:typeof stroke.pointerType==='string'?stroke.pointerType:'pen',points};});return{schemaVersion:1,meetingId:row.meetingId,updatedAt:new Date().toISOString(),strokes};});
    const db=await openDb();await new Promise((resolve,reject)=>{const tx=db.transaction(STORE,'readwrite'),store=tx.objectStore(STORE);for(const row of cleanRows)store.put(row);tx.oncomplete=resolve;tx.onerror=()=>reject(tx.error);tx.onabort=()=>reject(tx.error||new Error('펜 필기를 복원하지 못했습니다.'));});db.close();
  }
  async function deleteDocuments(meetingIds){
    if(!Array.isArray(meetingIds)||!meetingIds.length)return;
    const db=await openDb();await new Promise((resolve,reject)=>{const tx=db.transaction(STORE,'readwrite'),store=tx.objectStore(STORE);meetingIds.forEach(id=>store.delete(id));tx.oncomplete=resolve;tx.onerror=()=>reject(tx.error);});db.close();
  }
  function point(event) {
    const r = canvas.getBoundingClientRect();
    return {x:(event.clientX-r.left)*canvas.width/r.width, y:(event.clientY-r.top)*canvas.height/r.height,
      pressure:event.pressure > 0 ? event.pressure : 0.5, t:Date.now()};
  }
  function pathStroke(item) {
    const pts = item.points || []; if (!pts.length) return;
    ctx.strokeStyle=item.color;ctx.lineCap='round';ctx.lineJoin='round';
    if(pts.length===1||Math.hypot(pts[pts.length-1].x-pts[0].x,pts[pts.length-1].y-pts[0].y)<0.5){ctx.fillStyle=item.color;ctx.beginPath();ctx.arc(pts[0].x,pts[0].y,Math.max(1,item.width*(0.45+(pts[0].pressure||.5))/2),0,Math.PI*2);ctx.fill();return;}
    for(let i=1;i<pts.length;i++){ctx.lineWidth=item.width*(0.45+(pts[i].pressure||.5));ctx.beginPath();ctx.moveTo(pts[i-1].x,pts[i-1].y);ctx.lineTo(pts[i].x,pts[i].y);ctx.stroke();}
  }
  function shape(item) {
    const a=item.points[0], b=item.points[item.points.length-1]; if(!a||!b)return;
    ctx.strokeStyle=item.color;ctx.lineWidth=item.width;ctx.beginPath();
    if(item.tool==='rect')ctx.rect(a.x,a.y,b.x-a.x,b.y-a.y);
    else if(item.tool==='ellipse')ctx.ellipse((a.x+b.x)/2,(a.y+b.y)/2,Math.abs(b.x-a.x)/2,Math.abs(b.y-a.y)/2,0,0,Math.PI*2);
    else {ctx.moveTo(a.x,a.y);ctx.lineTo(b.x,b.y);if(item.tool==='arrow'){const q=Math.atan2(b.y-a.y,b.x-a.x),s=16;ctx.moveTo(b.x,b.y);ctx.lineTo(b.x-s*Math.cos(q-.45),b.y-s*Math.sin(q-.45));ctx.moveTo(b.x,b.y);ctx.lineTo(b.x-s*Math.cos(q+.45),b.y-s*Math.sin(q+.45));}}
    ctx.stroke();
  }
  function render() {
    ctx.clearRect(0,0,canvas.width,canvas.height);
    doc.strokes.forEach(item => item.tool==='pen' ? pathStroke(item) : shape(item));
    if(active) (active.tool==='pen' ? pathStroke(active) : shape(active));
    anchors.innerHTML='';
    const audio=audioElement();if(audio&&(audio.currentSrc||audio.src))doc.strokes.filter(s=>Number.isFinite(s.startMs)).forEach((s,i)=>{const b=document.createElement('button');b.className='ink-anchor';b.textContent=`${i+1} · ${formatMs(s.startMs)}`;b.onclick=()=>{try{audio.currentTime=s.startMs/1000;audio.play().catch(()=>{});}catch{}};anchors.appendChild(b);});
  }
  function formatMs(ms){const sec=Math.floor(ms/1000);return `${Math.floor(sec/60)}:${String(sec%60).padStart(2,'0')}`;}
  function segmentDistance(p,a,b){const dx=b.x-a.x,dy=b.y-a.y,l=dx*dx+dy*dy;if(!l)return Math.hypot(p.x-a.x,p.y-a.y);const t=Math.max(0,Math.min(1,((p.x-a.x)*dx+(p.y-a.y)*dy)/l));return Math.hypot(p.x-(a.x+t*dx),p.y-(a.y+t*dy));}
  function itemHit(item,p,radius){const pts=item.points||[],a=pts[0],b=pts[pts.length-1];if(!a||!b)return false;if(item.tool==='pen'||item.tool==='line'||item.tool==='arrow')return pts.slice(1).some((q,i)=>segmentDistance(p,pts[i],q)<=radius);if(item.tool==='rect'){const edges=[[a,{x:b.x,y:a.y}],[{x:b.x,y:a.y},b],[b,{x:a.x,y:b.y}],[{x:a.x,y:b.y},a]];return edges.some(e=>segmentDistance(p,e[0],e[1])<=radius);}const cx=(a.x+b.x)/2,cy=(a.y+b.y)/2,rx=Math.max(1,Math.abs(b.x-a.x)/2),ry=Math.max(1,Math.abs(b.y-a.y)/2);return Math.abs(Math.hypot((p.x-cx)/rx,(p.y-cy)/ry)-1)<=radius/Math.min(rx,ry);}
  function eraseAt(p) {
    const cssRadius=18*canvas.width/canvas.getBoundingClientRect().width;
    for(let i=doc.strokes.length-1;i>=0;i--){if(itemHit(doc.strokes[i],p,cssRadius)){redoStack=[];doc.strokes.splice(i,1);render();scheduleSave();break;}}
  }
  canvas.addEventListener('pointerdown', event => {
    if(activePointerId!==null||event.button>0)return;event.preventDefault();activePointerId=event.pointerId;canvas.setPointerCapture(event.pointerId); const p=point(event);
    if(tool==='eraser'){eraseAt(p);activePointerId=null;return;}
    active={id:crypto.randomUUID?.()||String(Date.now()),tool,color:document.getElementById('inkColor').value,width:Number(document.getElementById('inkWidth').value),startMs:audioMs(),endMs:audioMs(),pointerType:event.pointerType,points:[p]};
  });
  canvas.addEventListener('pointermove', event => {if(!active||event.pointerId!==activePointerId)return;active.points.push(point(event));active.endMs=audioMs();render();});
  function finish(event){if(!active||event.pointerId!==activePointerId)return;active.points.push(point(event));active.endMs=audioMs();doc.strokes.push(active);active=null;activePointerId=null;redoStack=[];render();scheduleSave();}
  canvas.addEventListener('pointerup', finish);canvas.addEventListener('pointercancel',event=>{if(event.pointerId===activePointerId){active=null;activePointerId=null;render();}});
  document.querySelectorAll('[data-ink-tool]').forEach(button=>button.addEventListener('click',()=>{tool=button.dataset.inkTool;document.querySelectorAll('[data-ink-tool]').forEach(b=>b.setAttribute('aria-pressed',String(b===button)));}));
  function undo(){const item=doc.strokes.pop();if(item)redoStack.push(item);render();scheduleSave();}
  function redo(){const item=redoStack.pop();if(item)doc.strokes.push(item);render();scheduleSave();}
  document.getElementById('inkUndo').onclick=undo;
  document.getElementById('inkRedo').onclick=redo;
  document.getElementById('inkClear').onclick=()=>{if(doc.strokes.length&&confirm('Delete all handwriting for this meeting?')){redoStack=doc.strokes.splice(0);render();scheduleSave();}};
  async function showInk(enabled){inkPanel.hidden=!enabled;textPanel.hidden=enabled;textTab.setAttribute('aria-selected',String(!enabled));inkTab.setAttribute('aria-selected',String(enabled));textTab.tabIndex=enabled?-1:0;inkTab.tabIndex=enabled?0:-1;if(enabled){canvas.style.pointerEvents='none';canvas.setAttribute('aria-busy','true');try{await load();requestAnimationFrame(render);}finally{canvas.style.pointerEvents='';canvas.removeAttribute('aria-busy');}}}
  textTab.onclick=()=>showInk(false).catch(console.warn); inkTab.onclick=()=>showInk(true).catch(console.warn);
  [textTab,inkTab].forEach((tab,index)=>tab.addEventListener('keydown',event=>{if(!['ArrowLeft','ArrowRight'].includes(event.key))return;event.preventDefault();const next=[textTab,inkTab][event.key==='ArrowRight'?(index+1)%2:(index+1)%2];next.focus();next.click();}));
  setInterval(()=>{if(!inkPanel.hidden&&meetingId()!==loadedMeetingId)switchMeeting(meetingId()).catch(console.warn);},500);

  window.__pronoteExternalConsent=()=>Boolean(document.getElementById('providerConsent')?.checked);
  window.PronoteInk={load,save,render,clearAll,switchMeeting,exportDocuments,importDocuments,deleteDocuments,document:doc};
})();

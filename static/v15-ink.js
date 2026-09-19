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
  const pageLabel = document.getElementById('inkPageLabel');
  const doc = { schemaVersion: 1, meetingId: '', updatedAt: '', pageCount: 1, pageBackgrounds: ['blank'], pageColors: ['#ffffff'], pageTemplates: [''], strokes: [] };
  let redoStack = [], active = null, activePointerId = null, tool = 'pen', saveTimer = 0;
  let currentPage = 0;
  let lassoStart = null, lassoRect = null, lassoMoveStart = null, lassoOriginalPoints = null, selectedIds = new Set();
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
    const snapshot = {schemaVersion:1, meetingId:targetMeetingId, updatedAt:new Date().toISOString(), pageCount:Math.max(1,doc.pageCount||1), pageBackgrounds:structuredClone(doc.pageBackgrounds||['blank']), pageColors:structuredClone(doc.pageColors||['#ffffff']), pageTemplates:structuredClone(doc.pageTemplates||['']), strokes:structuredClone(doc.strokes)};
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
    loadedMeetingId=target;doc.meetingId=target;doc.strokes=saved?.schemaVersion===1?structuredClone(saved.strokes||[]):[];doc.pageCount=Math.min(100,Math.max(1,Number(saved?.pageCount)||1,...doc.strokes.map(s=>(Number.isInteger(s.pageIndex)&&s.pageIndex>=0&&s.pageIndex<100?s.pageIndex:0)+1)));doc.pageBackgrounds=Array.isArray(saved?.pageBackgrounds)?saved.pageBackgrounds.slice(0,100):['blank'];doc.pageColors=Array.isArray(saved?.pageColors)?saved.pageColors.slice(0,100):['#ffffff'];doc.pageTemplates=Array.isArray(saved?.pageTemplates)?saved.pageTemplates.slice(0,100):[''];currentPage=0;redoStack=[];active=null;activePointerId=null;render();
  }
  function switchMeeting(target){if(!target||target===loadedMeetingId)return switchQueue;const transition=++switchGeneration;canvas.style.pointerEvents='none';canvas.setAttribute('aria-busy','true');switchQueue=switchQueue.catch(()=>{}).then(async()=>{clearTimeout(saveTimer);if(loadedMeetingId)await save(loadedMeetingId);loadGeneration++;loadedMeetingId='';await saveQueue;await load(target);}).finally(()=>{if(transition===switchGeneration){canvas.style.pointerEvents='';canvas.removeAttribute('aria-busy');}});return switchQueue;}
  async function clearAll(){clearing=true;clearTimeout(saveTimer);loadGeneration++;switchGeneration++;active=null;activePointerId=null;try{await Promise.allSettled([saveQueue,switchQueue]);const db=await openDb();await new Promise((resolve,reject)=>{const tx=db.transaction(STORE,'readwrite');tx.objectStore(STORE).clear();tx.oncomplete=resolve;tx.onerror=()=>reject(tx.error);});db.close();doc.strokes=[];doc.pageCount=1;doc.pageBackgrounds=['blank'];doc.pageColors=['#ffffff'];doc.pageTemplates=[''];currentPage=0;redoStack=[];loadedMeetingId='';render();}finally{clearing=false;canvas.style.pointerEvents='';canvas.removeAttribute('aria-busy');}}
  async function exportDocuments(meetingIds){
    clearTimeout(saveTimer);if(loadedMeetingId)await save(loadedMeetingId);await saveQueue;
    const wanted=new Set(meetingIds||[]),db=await openDb();
    const rows=await new Promise((resolve,reject)=>{const req=db.transaction(STORE,'readonly').objectStore(STORE).getAll();req.onsuccess=()=>resolve(req.result||[]);req.onerror=()=>reject(req.error);});
    db.close();return rows.filter(row=>wanted.has(row.meetingId)).map(row=>({schemaVersion:1,meetingId:row.meetingId,updatedAt:row.updatedAt||null,pageCount:Math.max(1,Number(row.pageCount)||1),pageBackgrounds:structuredClone(row.pageBackgrounds||['blank']),pageColors:structuredClone(row.pageColors||['#ffffff']),pageTemplates:structuredClone(row.pageTemplates||['']),strokes:structuredClone(row.strokes||[])}));
  }
  async function importDocuments(rows){
    if(!Array.isArray(rows)||!rows.length)return;
    let totalPoints=0;const tools=new Set(['pen','highlighter','line','arrow','rect','ellipse','sticky']);
    const cleanRows=rows.map(row=>{if(!row||row.schemaVersion!==1||typeof row.meetingId!=='string'||!row.meetingId||!Array.isArray(row.strokes)||row.strokes.length>5000)throw new Error('펜 필기 백업 형식이 올바르지 않습니다.');const strokes=row.strokes.map(stroke=>{if(!stroke||!tools.has(stroke.tool)||typeof stroke.color!=='string'||!/^#[0-9a-f]{6}$/i.test(stroke.color)||!Number.isFinite(stroke.width)||stroke.width<0.5||stroke.width>64||!Array.isArray(stroke.points)||!stroke.points.length||stroke.points.length>10000)throw new Error('펜 필기 백업 형식이 올바르지 않습니다.');totalPoints+=stroke.points.length;if(totalPoints>200000)throw new Error('펜 필기 백업이 너무 큽니다.');const points=stroke.points.map(point=>{if(!point||!Number.isFinite(point.x)||!Number.isFinite(point.y)||Math.abs(point.x)>1000000||Math.abs(point.y)>1000000||!Number.isFinite(point.pressure)||point.pressure<0||point.pressure>1||!Number.isFinite(point.t))throw new Error('펜 필기 좌표가 올바르지 않습니다.');return{x:point.x,y:point.y,pressure:point.pressure,t:point.t};});return{id:typeof stroke.id==='string'?stroke.id:'',tool:stroke.tool,color:stroke.color,width:stroke.width,text:typeof stroke.text==='string'?stroke.text.slice(0,500):'',pageIndex:Number.isInteger(stroke.pageIndex)&&stroke.pageIndex>=0&&stroke.pageIndex<100?stroke.pageIndex:0,startMs:Number.isFinite(stroke.startMs)?Math.max(0,stroke.startMs):0,endMs:Number.isFinite(stroke.endMs)?Math.max(0,stroke.endMs):0,pointerType:typeof stroke.pointerType==='string'?stroke.pointerType:'pen',points};});const papers=Array.isArray(row.pageBackgrounds)?row.pageBackgrounds.slice(0,100).map(value=>['blank','ruled','ruled-wide','grid','dot','manuscript'].includes(value)?value:'blank'):['blank'];const colors=Array.isArray(row.pageColors)?row.pageColors.slice(0,100).map(value=>/^#[0-9a-f]{6}$/i.test(value)?value:'#ffffff'):['#ffffff'];const templates=Array.isArray(row.pageTemplates)?row.pageTemplates.slice(0,100).map(value=>typeof value==='string'&&value.length<=7_000_000&&/^data:image\/(png|jpeg|webp);base64,/i.test(value)?value:''):[''];return{schemaVersion:1,meetingId:row.meetingId,updatedAt:new Date().toISOString(),pageCount:Math.max(1,Math.min(100,Number(row.pageCount)||1),...strokes.map(s=>s.pageIndex+1)),pageBackgrounds:papers,pageColors:colors,pageTemplates:templates,strokes};});
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
    ctx.save();if(item.tool==='highlighter'){ctx.globalAlpha=.28;ctx.globalCompositeOperation='multiply';}
    ctx.strokeStyle=item.color;ctx.lineCap='round';ctx.lineJoin='round';
    if(pts.length===1||Math.hypot(pts[pts.length-1].x-pts[0].x,pts[pts.length-1].y-pts[0].y)<0.5){ctx.fillStyle=item.color;ctx.beginPath();ctx.arc(pts[0].x,pts[0].y,Math.max(1,item.width*(0.45+(pts[0].pressure||.5))/2),0,Math.PI*2);ctx.fill();ctx.restore();return;}
    for(let i=1;i<pts.length;i++){ctx.lineWidth=item.width*(0.45+(pts[i].pressure||.5));ctx.beginPath();ctx.moveTo(pts[i-1].x,pts[i-1].y);ctx.lineTo(pts[i].x,pts[i].y);ctx.stroke();}
    ctx.restore();
  }
  function shape(item) {
    const a=item.points[0], b=item.points[item.points.length-1]; if(!a||!b)return;
    if(item.tool==='sticky'){ctx.save();ctx.fillStyle='#fff1a8';ctx.strokeStyle='#d2b34c';ctx.lineWidth=2;ctx.shadowColor='rgba(0,0,0,.14)';ctx.shadowBlur=12;ctx.fillRect(a.x,a.y,220,150);ctx.strokeRect(a.x,a.y,220,150);ctx.shadowColor='transparent';ctx.fillStyle='#302d2a';ctx.font='20px sans-serif';const words=String(item.text||'').split(/\s+/);let line='',y=a.y+34;for(const word of words){const next=line?`${line} ${word}`:word;if(ctx.measureText(next).width>184&&line){ctx.fillText(line,a.x+18,y);line=word;y+=28;if(y>a.y+130)break;}else line=next;}if(line&&y<=a.y+130)ctx.fillText(line,a.x+18,y);ctx.restore();return;}
    ctx.strokeStyle=item.color;ctx.lineWidth=item.width;ctx.beginPath();
    if(item.tool==='rect')ctx.rect(a.x,a.y,b.x-a.x,b.y-a.y);
    else if(item.tool==='ellipse')ctx.ellipse((a.x+b.x)/2,(a.y+b.y)/2,Math.abs(b.x-a.x)/2,Math.abs(b.y-a.y)/2,0,0,Math.PI*2);
    else {ctx.moveTo(a.x,a.y);ctx.lineTo(b.x,b.y);if(item.tool==='arrow'){const q=Math.atan2(b.y-a.y,b.x-a.x),s=16;ctx.moveTo(b.x,b.y);ctx.lineTo(b.x-s*Math.cos(q-.45),b.y-s*Math.sin(q-.45));ctx.moveTo(b.x,b.y);ctx.lineTo(b.x-s*Math.cos(q+.45),b.y-s*Math.sin(q+.45));}}
    ctx.stroke();
  }
  function render() {
    ctx.clearRect(0,0,canvas.width,canvas.height);
    doc.strokes.filter(item=>(item.pageIndex||0)===currentPage).forEach(item => item.tool==='pen'||item.tool==='highlighter' ? pathStroke(item) : shape(item));
    if(active) (active.tool==='pen'||active.tool==='highlighter' ? pathStroke(active) : shape(active));
    const selected=doc.strokes.filter(item=>selectedIds.has(item.id));
    const selectedBounds=boundsFor(selected);
    if(selectedBounds){ctx.save();ctx.strokeStyle='#376a8a';ctx.lineWidth=2;ctx.setLineDash([9,6]);ctx.strokeRect(selectedBounds.x-8,selectedBounds.y-8,selectedBounds.w+16,selectedBounds.h+16);ctx.restore();}
    if(lassoRect){ctx.save();ctx.strokeStyle='#376a8a';ctx.lineWidth=2;ctx.setLineDash([8,5]);ctx.strokeRect(lassoRect.x,lassoRect.y,lassoRect.w,lassoRect.h);ctx.restore();}
    const selectionActions=document.getElementById('inkSelectionActions');if(selectionActions)selectionActions.hidden=!selectedIds.size;
    if(pageLabel)pageLabel.textContent=`${currentPage+1} / ${doc.pageCount}`;
    const paper=document.getElementById('inkPaper'),paperColor=document.getElementById('inkPaperColor'),wrap=canvas.closest('.ink-canvas-wrap'),templateImage=document.getElementById('inkTemplateImage'),paperValue=['blank','ruled','ruled-wide','grid','dot','manuscript'].includes(doc.pageBackgrounds?.[currentPage])?doc.pageBackgrounds[currentPage]:'blank',colorValue=/^#[0-9a-f]{6}$/i.test(doc.pageColors?.[currentPage]||'')?doc.pageColors[currentPage]:'#ffffff',templateValue=doc.pageTemplates?.[currentPage]||'';if(paper)paper.value=paperValue;if(paperColor)paperColor.value=colorValue;if(wrap){wrap.dataset.paper=paperValue;wrap.style.setProperty('--paper-color',colorValue);}if(templateImage){templateImage.hidden=!templateValue;if(templateValue)templateImage.src=templateValue;else templateImage.removeAttribute('src');}
    anchors.innerHTML='';
    const audio=audioElement();if(audio&&(audio.currentSrc||audio.src))doc.strokes.filter(s=>(s.pageIndex||0)===currentPage&&Number.isFinite(s.startMs)).forEach((s,i)=>{const b=document.createElement('button');b.className='ink-anchor';b.textContent=`${i+1} · ${formatMs(s.startMs)}`;b.onclick=()=>{try{audio.currentTime=s.startMs/1000;audio.play().catch(()=>{});}catch{}};anchors.appendChild(b);});
  }
  function formatMs(ms){const sec=Math.floor(ms/1000);return `${Math.floor(sec/60)}:${String(sec%60).padStart(2,'0')}`;}
  function itemBounds(item){const pts=item.points||[];if(!pts.length)return null;const xs=pts.map(p=>p.x),ys=pts.map(p=>p.y);const x=Math.min(...xs),y=Math.min(...ys);return{x,y,w:Math.max(1,Math.max(...xs)-x),h:Math.max(1,Math.max(...ys)-y)};}
  function boundsFor(items){const boxes=items.map(itemBounds).filter(Boolean);if(!boxes.length)return null;const x=Math.min(...boxes.map(b=>b.x)),y=Math.min(...boxes.map(b=>b.y)),right=Math.max(...boxes.map(b=>b.x+b.w)),bottom=Math.max(...boxes.map(b=>b.y+b.h));return{x,y,w:right-x,h:bottom-y};}
  function rectFrom(a,b){return{x:Math.min(a.x,b.x),y:Math.min(a.y,b.y),w:Math.abs(b.x-a.x),h:Math.abs(b.y-a.y)};}
  function intersects(a,b){return a&&b&&a.x<=b.x+b.w&&a.x+a.w>=b.x&&a.y<=b.y+b.h&&a.y+a.h>=b.y;}
  function segmentDistance(p,a,b){const dx=b.x-a.x,dy=b.y-a.y,l=dx*dx+dy*dy;if(!l)return Math.hypot(p.x-a.x,p.y-a.y);const t=Math.max(0,Math.min(1,((p.x-a.x)*dx+(p.y-a.y)*dy)/l));return Math.hypot(p.x-(a.x+t*dx),p.y-(a.y+t*dy));}
  function itemHit(item,p,radius){const pts=item.points||[],a=pts[0],b=pts[pts.length-1];if(!a||!b)return false;if(item.tool==='pen'||item.tool==='highlighter'||item.tool==='line'||item.tool==='arrow')return pts.slice(1).some((q,i)=>segmentDistance(p,pts[i],q)<=radius);if(item.tool==='sticky')return p.x>=a.x-radius&&p.x<=a.x+220+radius&&p.y>=a.y-radius&&p.y<=a.y+150+radius;if(item.tool==='rect'){const edges=[[a,{x:b.x,y:a.y}],[{x:b.x,y:a.y},b],[b,{x:a.x,y:b.y}],[{x:a.x,y:b.y},a]];return edges.some(e=>segmentDistance(p,e[0],e[1])<=radius);}const cx=(a.x+b.x)/2,cy=(a.y+b.y)/2,rx=Math.max(1,Math.abs(b.x-a.x)/2),ry=Math.max(1,Math.abs(b.y-a.y)/2);return Math.abs(Math.hypot((p.x-cx)/rx,(p.y-cy)/ry)-1)<=radius/Math.min(rx,ry);}
  function eraseAt(p) {
    const cssRadius=18*canvas.width/canvas.getBoundingClientRect().width;
    for(let i=doc.strokes.length-1;i>=0;i--){if((doc.strokes[i].pageIndex||0)===currentPage&&itemHit(doc.strokes[i],p,cssRadius)){redoStack=[];doc.strokes.splice(i,1);render();scheduleSave();break;}}
  }
  function openStickyEditor(p) {
    const overlay=document.createElement('div');overlay.className='modal-overlay open';overlay.setAttribute('role','dialog');overlay.setAttribute('aria-modal','true');overlay.setAttribute('aria-labelledby','inkStickyTitle');
    overlay.innerHTML='<div class="modal-card" style="max-width:440px"><div class="modal-head"><div><div class="modal-eyebrow">필기 도구</div><h2 class="modal-title" id="inkStickyTitle">포스트잇 내용</h2></div><button type="button" class="modal-close" aria-label="닫기">×</button></div><div class="modal-body"><label for="inkStickyText" style="display:block;font-weight:700;margin-bottom:8px">메모</label><textarea id="inkStickyText" maxlength="500" rows="6" placeholder="포스트잇에 남길 내용을 입력하세요" style="width:100%;resize:vertical;min-height:132px;padding:12px;border:1px solid #cfc8bd;border-radius:10px;font:inherit;line-height:1.55"></textarea><p style="margin:8px 0 0;color:#777;font-size:12px">최대 500자</p></div><div class="modal-foot"><button type="button" class="modal-btn" data-sticky-cancel>취소</button><button type="button" class="modal-btn primary" data-sticky-save>포스트잇 추가</button></div></div>';
    const input=overlay.querySelector('#inkStickyText');
    const close=()=>{overlay.remove();canvas.focus();};
    const save=()=>{const text=input.value.trim();if(!text){input.focus();return;}doc.strokes.push({id:crypto.randomUUID?.()||String(Date.now()),tool:'sticky',color:'#fff1a8',width:2,text:text.slice(0,500),pageIndex:currentPage,startMs:audioMs(),endMs:audioMs(),pointerType:'ui',points:[p,{...p,x:p.x+220,y:p.y+150}]});redoStack=[];selectedIds.clear();render();scheduleSave();close();};
    overlay.querySelector('.modal-close').onclick=close;overlay.querySelector('[data-sticky-cancel]').onclick=close;overlay.querySelector('[data-sticky-save]').onclick=save;overlay.addEventListener('click',event=>{if(event.target===overlay)close();});overlay.addEventListener('keydown',event=>{if(event.key==='Escape'){event.preventDefault();close();}else if((event.ctrlKey||event.metaKey)&&event.key==='Enter'){event.preventDefault();save();}});document.body.appendChild(overlay);input.focus();
  }
  canvas.addEventListener('pointerdown', event => {
    if(activePointerId!==null||event.button>0)return;event.preventDefault();activePointerId=event.pointerId;canvas.setPointerCapture(event.pointerId); const p=point(event);
    if(tool==='eraser'){eraseAt(p);activePointerId=null;return;}
    if(tool==='lasso'){
      const selected=doc.strokes.filter(item=>selectedIds.has(item.id));
      const radius=20*canvas.width/canvas.getBoundingClientRect().width;
      if(selected.some(item=>itemHit(item,p,radius))){lassoMoveStart=p;lassoOriginalPoints=new Map(selected.map(item=>[item.id,structuredClone(item.points)]));render();return;}
      lassoStart=p;lassoRect={x:p.x,y:p.y,w:0,h:0};selectedIds.clear();render();return;
    }
    if(tool==='sticky'){activePointerId=null;openStickyEditor(p);return;}
    active={id:crypto.randomUUID?.()||String(Date.now()),tool,color:document.getElementById('inkColor').value,width:tool==='highlighter'?Math.max(14,Number(document.getElementById('inkWidth').value)*3):Number(document.getElementById('inkWidth').value),pageIndex:currentPage,startMs:audioMs(),endMs:audioMs(),pointerType:event.pointerType,points:[p]};
  });
  canvas.addEventListener('pointermove', event => {if(event.pointerId!==activePointerId)return;const p=point(event);if(tool==='lasso'&&lassoMoveStart&&lassoOriginalPoints){const dx=p.x-lassoMoveStart.x,dy=p.y-lassoMoveStart.y;doc.strokes.forEach(item=>{const original=lassoOriginalPoints.get(item.id);if(original)item.points=original.map(q=>({...q,x:q.x+dx,y:q.y+dy}));});render();return;}if(tool==='lasso'&&lassoStart){lassoRect=rectFrom(lassoStart,p);render();return;}if(!active)return;active.points.push(p);active.endMs=audioMs();render();});
  function finish(event){if(event.pointerId!==activePointerId)return;if(tool==='lasso'&&lassoMoveStart){lassoMoveStart=null;lassoOriginalPoints=null;activePointerId=null;redoStack=[];render();scheduleSave();return;}if(tool==='lasso'&&lassoStart){const box=rectFrom(lassoStart,point(event));selectedIds=new Set(doc.strokes.filter(item=>(item.pageIndex||0)===currentPage&&intersects(itemBounds(item),box)).map(item=>item.id));lassoStart=null;lassoRect=null;activePointerId=null;render();return;}if(!active)return;active.points.push(point(event));active.endMs=audioMs();doc.strokes.push(active);active=null;activePointerId=null;redoStack=[];selectedIds.clear();render();scheduleSave();}
  canvas.addEventListener('pointerup', finish);canvas.addEventListener('pointercancel',event=>{if(event.pointerId===activePointerId){if(lassoOriginalPoints)doc.strokes.forEach(item=>{const original=lassoOriginalPoints.get(item.id);if(original)item.points=original;});active=null;activePointerId=null;lassoStart=null;lassoRect=null;lassoMoveStart=null;lassoOriginalPoints=null;render();}});
  document.querySelectorAll('[data-ink-tool]').forEach(button=>button.addEventListener('click',()=>{tool=button.dataset.inkTool;selectedIds.clear();lassoRect=null;document.querySelectorAll('[data-ink-tool]').forEach(b=>b.setAttribute('aria-pressed',String(b===button)));button.closest('details')?.removeAttribute('open');render();}));
  document.querySelectorAll('[data-ink-color]').forEach(button=>button.addEventListener('click',()=>{document.getElementById('inkColor').value=button.dataset.inkColor;document.querySelectorAll('[data-ink-color]').forEach(item=>item.setAttribute('aria-pressed',String(item===button)));}));
  document.getElementById('inkColor').addEventListener('input',()=>document.querySelectorAll('[data-ink-color]').forEach(item=>item.setAttribute('aria-pressed','false')));
  const inkMenuHomes=new WeakMap();
  function menuFor(details){return inkMenuHomes.get(details)?.menu||details.querySelector('.ink-more-menu,.ink-paper-menu');}
  function restoreInkMenu(details){const home=inkMenuHomes.get(details);if(!home)return;home.menu.classList.remove('ink-floating-menu');home.menu.removeAttribute('style');if(home.next?.parentNode===home.parent)home.parent.insertBefore(home.menu,home.next);else home.parent.appendChild(home.menu);inkMenuHomes.delete(details);}
  function positionInkMenu(details){const menu=menuFor(details),summary=details.querySelector('summary');if(!details.open||!menu||!summary)return;requestAnimationFrame(()=>{const trigger=summary.getBoundingClientRect(),box=menu.getBoundingClientRect(),left=Math.max(8,Math.min(trigger.left,window.innerWidth-box.width-8));let top=trigger.bottom+8;if(top+box.height>window.innerHeight-8)top=Math.max(8,trigger.top-box.height-8);menu.style.left=`${left}px`;menu.style.top=`${top}px`;});}
  document.querySelectorAll('.ink-more-tools').forEach(details=>details.addEventListener('toggle',()=>{if(details.open){document.querySelectorAll('.ink-more-tools').forEach(other=>{if(other!==details)other.open=false;});const menu=menuFor(details);if(menu&&!inkMenuHomes.has(details)){inkMenuHomes.set(details,{menu,parent:menu.parentNode,next:menu.nextSibling});menu.classList.add('ink-floating-menu');document.body.appendChild(menu);}positionInkMenu(details);}else restoreInkMenu(details);}));
  window.addEventListener('resize',()=>document.querySelectorAll('.ink-more-tools[open]').forEach(positionInkMenu));
  function undo(){for(let i=doc.strokes.length-1;i>=0;i--){if((doc.strokes[i].pageIndex||0)===currentPage){redoStack.push(doc.strokes.splice(i,1)[0]);break;}}render();scheduleSave();}
  function redo(){const item=redoStack.pop();if(item)doc.strokes.push(item);render();scheduleSave();}
  document.getElementById('inkUndo').onclick=undo;
  document.getElementById('inkRedo').onclick=redo;
  document.getElementById('inkClear').onclick=()=>{if(doc.strokes.length&&confirm('Delete all handwriting for this meeting?')){redoStack=doc.strokes.splice(0);render();scheduleSave();}};
  document.getElementById('inkDuplicateSelection').onclick=()=>{const source=doc.strokes.filter(item=>selectedIds.has(item.id));const copies=source.map(item=>({...structuredClone(item),id:crypto.randomUUID?.()||`${Date.now()}-${Math.random()}`,points:item.points.map(p=>({...p,x:p.x+24,y:p.y+24}))}));doc.strokes.push(...copies);selectedIds=new Set(copies.map(item=>item.id));redoStack=[];render();scheduleSave();};
  document.getElementById('inkDeleteSelection').onclick=()=>{if(!selectedIds.size)return;const removed=doc.strokes.filter(item=>selectedIds.has(item.id));doc.strokes=doc.strokes.filter(item=>!selectedIds.has(item.id));redoStack.push(...removed);selectedIds.clear();render();scheduleSave();};
  function goPage(index){currentPage=Math.max(0,Math.min(doc.pageCount-1,index));active=null;activePointerId=null;selectedIds.clear();lassoRect=null;redoStack=[];render();}
  document.getElementById('inkPrevPage').onclick=()=>goPage(currentPage-1);
  document.getElementById('inkNextPage').onclick=()=>goPage(currentPage+1);
  document.getElementById('inkAddPage').onclick=()=>{doc.pageCount=Math.min(100,doc.pageCount+1);doc.pageBackgrounds[doc.pageCount-1]='blank';doc.pageColors[doc.pageCount-1]='#ffffff';doc.pageTemplates[doc.pageCount-1]='';goPage(doc.pageCount-1);scheduleSave();};
  document.getElementById('inkDeletePage').onclick=()=>{if(doc.pageCount<=1){doc.strokes=doc.strokes.filter(s=>(s.pageIndex||0)!==0);doc.pageBackgrounds=['blank'];doc.pageColors=['#ffffff'];doc.pageTemplates=[''];render();scheduleSave();return;}if(!confirm('현재 페이지와 필기를 삭제할까요?'))return;doc.strokes=doc.strokes.filter(s=>(s.pageIndex||0)!==currentPage).map(s=>({...s,pageIndex:(s.pageIndex||0)>currentPage?(s.pageIndex||0)-1:(s.pageIndex||0)}));doc.pageBackgrounds.splice(currentPage,1);doc.pageColors.splice(currentPage,1);doc.pageTemplates.splice(currentPage,1);doc.pageCount--;goPage(Math.min(currentPage,doc.pageCount-1));scheduleSave();};
  document.getElementById('inkPaper').onchange=event=>{doc.pageBackgrounds[currentPage]=event.target.value;render();scheduleSave();};
  document.getElementById('inkPaperColor').oninput=event=>{doc.pageColors[currentPage]=event.target.value;render();scheduleSave();};
  const templateInput=document.getElementById('inkTemplateInput');document.getElementById('inkTemplateOpen').onclick=()=>templateInput.click();templateInput.onchange=()=>{const file=templateInput.files?.[0];if(!file)return;if(!/^image\/(png|jpeg|webp)$/.test(file.type)||file.size>5*1024*1024){alert('PNG, JPG, WEBP 이미지를 5MB 이하로 선택해 주세요.');templateInput.value='';return;}const reader=new FileReader();reader.onload=()=>{doc.pageTemplates[currentPage]=String(reader.result||'');render();scheduleSave();};reader.readAsDataURL(file);};document.getElementById('inkTemplateClear').onclick=()=>{doc.pageTemplates[currentPage]='';render();scheduleSave();};
  const workspace=document.getElementById('inkWorkspace'),sourceInput=document.getElementById('inkSourceInput'),sourceImage=document.getElementById('inkSourceImage'),sourcePdf=document.getElementById('inkSourcePdf'),sourceEmpty=document.getElementById('inkSourceEmpty'),sourceToggle=document.getElementById('inkSourceToggle');let sourceUrl='';
  function setSplit(enabled){workspace?.classList.toggle('split',enabled);sourceToggle?.setAttribute('aria-pressed',String(enabled));requestAnimationFrame(render);}
  sourceToggle.onclick=()=>setSplit(!workspace.classList.contains('split'));
  document.getElementById('inkSourceOpen').onclick=()=>sourceInput.click();
  sourceInput.onchange=()=>{const file=sourceInput.files?.[0];if(!file)return;if(sourceUrl)URL.revokeObjectURL(sourceUrl);sourceUrl=URL.createObjectURL(file);const pdf=file.type==='application/pdf';sourcePdf.hidden=!pdf;sourceImage.hidden=pdf;sourceEmpty.hidden=true;if(pdf)sourcePdf.src=sourceUrl;else sourceImage.src=sourceUrl;setSplit(true);};
  function drawPaper(target){const color=/^#[0-9a-f]{6}$/i.test(doc.pageColors?.[currentPage]||'')?doc.pageColors[currentPage]:'#ffffff',kind=doc.pageBackgrounds?.[currentPage]||'blank';target.fillStyle=color;target.fillRect(0,0,canvas.width,canvas.height);target.strokeStyle=kind==='manuscript'?'#e5c7c1':'#dfe5eb';target.lineWidth=1;if(kind==='grid'||kind==='manuscript'){const step=kind==='manuscript'?40:24;for(let x=step;x<canvas.width;x+=step){target.beginPath();target.moveTo(x,0);target.lineTo(x,canvas.height);target.stroke();}for(let y=step;y<canvas.height;y+=step){target.beginPath();target.moveTo(0,y);target.lineTo(canvas.width,y);target.stroke();}}else if(kind==='ruled'||kind==='ruled-wide'){const step=kind==='ruled-wide'?48:32;for(let y=step;y<canvas.height;y+=step){target.beginPath();target.moveTo(0,y);target.lineTo(canvas.width,y);target.stroke();}}else if(kind==='dot'){target.fillStyle='#cbd2d9';for(let x=24;x<canvas.width;x+=24)for(let y=24;y<canvas.height;y+=24){target.beginPath();target.arc(x,y,1.5,0,Math.PI*2);target.fill();}}}
  async function exportCurrentPage(){const out=document.createElement('canvas');out.width=canvas.width;out.height=canvas.height;const target=out.getContext('2d');drawPaper(target);const template=doc.pageTemplates?.[currentPage];if(template){const image=new Image();image.src=template;try{await image.decode();const scale=Math.min(out.width/image.naturalWidth,out.height/image.naturalHeight),w=image.naturalWidth*scale,h=image.naturalHeight*scale;target.drawImage(image,(out.width-w)/2,(out.height-h)/2,w,h);}catch{}}target.drawImage(canvas,0,0);out.toBlob(blob=>{if(!blob)return;const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download=`AI_PRONOTE_${currentPage+1}.png`;a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000);},'image/png');}
  document.getElementById('inkExportPng').onclick=()=>exportCurrentPage().catch(console.warn);
  async function showInk(enabled){inkPanel.hidden=!enabled;textPanel.hidden=enabled;inkPanel.closest('.mynote-block')?.classList.toggle('ink-active',enabled);textTab.setAttribute('aria-selected',String(!enabled));inkTab.setAttribute('aria-selected',String(enabled));textTab.tabIndex=enabled?-1:0;inkTab.tabIndex=enabled?0:-1;if(enabled){canvas.style.pointerEvents='none';canvas.setAttribute('aria-busy','true');try{await load();requestAnimationFrame(render);}finally{canvas.style.pointerEvents='';canvas.removeAttribute('aria-busy');}}}
  textTab.onclick=()=>showInk(false).catch(console.warn); inkTab.onclick=()=>showInk(true).catch(console.warn);
  [textTab,inkTab].forEach((tab,index)=>tab.addEventListener('keydown',event=>{if(!['ArrowLeft','ArrowRight'].includes(event.key))return;event.preventDefault();const next=[textTab,inkTab][event.key==='ArrowRight'?(index+1)%2:(index+1)%2];next.focus();next.click();}));
  setInterval(()=>{if(!inkPanel.hidden&&meetingId()!==loadedMeetingId)switchMeeting(meetingId()).catch(console.warn);},500);

  window.__pronoteExternalConsent=()=>Boolean(document.getElementById('providerConsent')?.checked);
  window.PronoteInk={load,save,render,clearAll,switchMeeting,exportDocuments,importDocuments,deleteDocuments,document:doc};
})();

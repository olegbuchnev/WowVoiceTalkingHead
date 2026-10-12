const round=value=>Math.round(Math.max(0,value));
// These are browser observations, not trusted voting data. Never block the UI.
export function observePortrait({questID,npc}, {clock=performance,send=payload=>fetch('/api/diagnostics/portrait',{
  method:'POST',credentials:'omit',headers:{'Content-Type':'application/json'},
  body:JSON.stringify(payload),keepalive:true,signal:AbortSignal.timeout(5000),
}).catch(()=>{})}={}) {
  const loadID=`p-${crypto.randomUUID().replaceAll('-','').slice(0,12)}`;
  const start=clock.now(),phases={},resources=[];
  let observer,finished=false,hidden=document.hidden;
  const visibility=()=>{hidden ||= document.hidden;};
  document.addEventListener('visibilitychange',visibility);
  const collect=entries=>{
    for(const r of entries) if(/\/(?:modelviewer\/(?:portrait-v1\/)?classicplus\/.*\.(?:m2|skel)|api\/portrait-camera\/\d+)$/.test(new URL(r.name,location.origin).pathname)) {
      resources.push(r);if(resources.length>20) resources.shift();
    }
  };
  if(typeof PerformanceObserver!=='undefined') {
    observer=new PerformanceObserver(list=>collect(list.getEntries()));
    observer.observe({type:'resource',buffered:true});
  }
  function report(stage) {
    const totalMs=round(clock.now()-start);
    collect(observer?.takeRecords() || []);
    const modelFileID=npc.modelFileID;
    const matching=resources.filter(r=>new URL(r.name,location.origin).pathname===`/modelviewer/classicplus/m2/${modelFileID}.m2`
      || new URL(r.name,location.origin).pathname===`/modelviewer/portrait-v1/classicplus/m2/${modelFileID}.m2`
      || new URL(r.name,location.origin).pathname===`/api/portrait-camera/${modelFileID}`);
    const latest=[...new Map(matching.map(r=>[r.name,r])).values()];
    const payload={version:1,loadID,questID,displayID:npc.displayID,modelFileID,stage,totalMs,hidden,...phases,
      resources:latest.slice(-5).map(r=>({path:new URL(r.name).pathname,
        durationMs:round(r.duration),ttfbMs:round(r.responseStart-r.requestStart),
        transferMs:round(r.responseEnd-r.responseStart),transferBytes:r.transferSize,
        encodedBytes:r.encodedBodySize,decodedBytes:r.decodedBodySize,reused:r.startTime<start,
        requestID:r.serverTiming?.find(t=>t.name==='request')?.description,
      })),
    };
    try {Promise.resolve(send(payload)).catch(()=>{});} catch {}
  }
  report('started');
  return {
    loadID,
    mark:key=>{phases[key]=round(clock.now()-start-(key==='cameraMs' ? phases.assetsReadyMs || 0 : 0));},
    report,
    ready:()=>{finished=true;report('ready');},
    stop:()=>{if(!finished) report('cancelled');observer?.disconnect();document.removeEventListener('visibilitychange',visibility);},
  };
}

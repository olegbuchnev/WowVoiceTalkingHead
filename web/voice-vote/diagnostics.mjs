const number=(value,max=3600000)=>typeof value==='number' && Number.isFinite(value) && value>=0 && value<=max;
const id=value=>Number.isSafeInteger(value) && value>0 && value<2147483648;
const stages=new Set(['started','ready','timeout','viewer-error','assets-error','camera-error','cancelled']);
const resourcePath=/^\/(?:modelviewer\/(?:portrait-v1\/)?classicplus\/(?:m2|skel|textures|meta)\/[a-zA-Z0-9_./-]+|api\/portrait-camera\/\d+)$/;

// Whitelist fields: never persist arbitrary client messages, URLs, cookies or IPs.
export function sanitizePortraitReport(input) {
  if(!input || input.version!==1 || !/^p-[a-f0-9]{12}$/.test(input.loadID || '') || !id(input.displayID) || !stages.has(input.stage) || !number(input.totalMs)) throw Error('Invalid portrait report');
  const report={version:1,loadID:input.loadID,displayID:input.displayID,stage:input.stage,totalMs:Math.round(input.totalMs)};
  for(const key of ['questID','modelFileID']) if(id(input[key])) report[key]=input[key];
  for(const key of ['viewerMs','assetsReadyMs','cameraMs','visibleMs']) if(number(input[key])) report[key]=Math.round(input[key]);
  report.hidden=!!input.hidden;
  report.resources=(Array.isArray(input.resources)?input.resources:[]).slice(0,5).flatMap(r=>{
    if(!r || typeof r.path!=='string' || r.path.length>180 || !resourcePath.test(r.path) || r.path.includes('..')) return [];
    const out={path:r.path,reused:!!r.reused};
    for(const key of ['durationMs','ttfbMs','transferMs']) if(number(r[key])) out[key]=Math.round(r[key]);
    for(const key of ['transferBytes','encodedBytes','decodedBytes']) if(number(r[key],200000000)) out[key]=Math.round(r[key]);
    if(/^[a-f0-9]{32}$/.test(r.requestID || '')) out.requestID=r.requestID;
    return [out];
  });
  return report;
}

export function createDiagnosticsHandler({log=console.log,now=Date.now,limit=1800}={}) {
  let windowStart=now(),count=0;
  return async(req,res)=>{
    res.setHeader('Cache-Control','no-store');
    if(req.method!=='POST') {res.writeHead(405).end();return;}
    // Backstop to Nginx rate limiting, including direct local development access.
    if(now()-windowStart>=60000) {windowStart=now();count=0;}
    if(++count>limit) {res.writeHead(429).end();return;}
    if(!/^application\/json(?:;|$)/i.test(req.headers['content-type'] || '')) {res.writeHead(415).end();return;}
    try {
      let size=0;const chunks=[];
      for await(const chunk of req) {
        size+=chunk.length;
        if(size>8192) {res.writeHead(413).end();return;}
        chunks.push(chunk);
      }
      const report=sanitizePortraitReport(JSON.parse(Buffer.concat(chunks).toString('utf8')));
      log(JSON.stringify({event:'portrait_client',time:new Date(now()).toISOString(),...report}));
      res.writeHead(204).end();
    } catch {if(!res.headersSent) res.writeHead(400).end();}
  };
}

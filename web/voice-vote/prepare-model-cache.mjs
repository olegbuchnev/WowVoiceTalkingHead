import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {parseArgs} from 'node:util';
import {createServer} from 'vite';
import {firefox} from 'playwright';
import {repo, localApi} from './server.mjs';

const {values:args}=parseArgs({options:{
  catalogue:{type:'string',default:'artifacts/voice-vote-deploy/catalogue/site-catalogue.json'},
  cache:{type:'string',default:'artifacts/voice-vote-model-cache'},
  verify:{type:'boolean',default:false},
  'quest-ids':{type:'string'},
  timeout:{type:'string',default:'60000'},
  retries:{type:'string',default:'2'},
  workers:{type:'string',default:'1'},
  help:{type:'boolean'},
}});
if(args.help) {
  console.log('Prepare: node web/voice-vote/prepare-model-cache.mjs\nVerify offline: add --verify\nOptions: --catalogue FILE --cache DIR --quest-ids 7,179,3741 --timeout 60000 --retries 2 --workers 1');
  process.exit(0);
}
const cache=path.resolve(args.cache),cataloguePath=path.resolve(args.catalogue);
const timeout=Number(args.timeout),retries=args.verify?0:Number(args.retries);
const workers=Number(args.workers);
if(!Number.isInteger(workers)||workers<1||workers>4) throw Error('Workers must be between 1 and 4');
if(!Number.isInteger(timeout)||timeout<1000||!Number.isInteger(retries)||retries<0||retries>5) throw Error('Invalid timeout or retries');
process.env.VOICE_VOTE_MODEL_CACHE=cache;
process.env.VOICE_VOTE_MODEL_OFFLINE=String(args.verify);
fs.mkdirSync(cache,{recursive:true});
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const atomicJSON=(file,data)=>{const tmp=`${file}.${crypto.randomUUID()}.tmp`;fs.writeFileSync(tmp,JSON.stringify(data,null,2));fs.renameSync(tmp,file);};
const catalogueBytes=fs.readFileSync(cataloguePath),catalogue=JSON.parse(catalogueBytes);
const selected=args['quest-ids']?.split(',').map(Number);
if(selected?.some(id=>!Number.isInteger(id)||id<=0||!catalogue.quests.some(q=>q.questID===id))) throw Error('Unknown quest ID');
const portraits=new Map(),unavailable=[];
for(const quest of catalogue.quests) {
  if(selected&&!selected.includes(quest.questID)) continue;
  if(!quest.npc?.displayID) {unavailable.push(quest.questID);continue;}
  const id=quest.npc.displayID;
  if(!portraits.has(id)) portraits.set(id,{npc:quest.npc,questIDs:[]});
  portraits.get(id).questIDs.push(quest.questID);
}
// An adapter or camera change invalidates readiness, but reuses downloaded files.
const sourceFiles=['web/voice-vote/src/model.js','web/voice-vote/src/portrait-camera.js',
  'web/voice-vote/src/portrait-light.js','web/voice-vote/portrait-camera.mjs',
  'web/voice-vote/viewer-lighting.mjs','web/voice-vote/native-camera-samples.json',
  'src/CameraProfiles.lua','src/CameraModels.lua'];
const fingerprint=hash(Buffer.concat([Buffer.from('portrait-cache-v1'),...sourceFiles.map(f=>fs.readFileSync(path.join(repo,f)))]));
const manifestPath=path.join(cache,'manifest.json');
const manifest=fs.existsSync(manifestPath)?JSON.parse(fs.readFileSync(manifestPath,'utf8')):{schemaVersion:1,portraits:{}};
if(manifest.schemaVersion!==1) throw Error('Unknown cache manifest version');
const report={mode:args.verify?'offline-verification':'prepare',startedAt:new Date().toISOString(),
  catalogueSHA256:hash(catalogueBytes),partial:!!selected,total:portraits.size,ready:0,reused:0,
  unavailableQuestIDs:unavailable,failures:[],completed:false};
const reportPath=path.join(cache,args.verify?'verify-report.json':'prepare-report.json');
const checks=new Map();
function cacheFile(url) {
  if(!/^\/modelviewer\/[a-zA-Z0-9_./-]+$/.test(url)||url.includes('..')) throw Error('Invalid cached asset path');
  return path.join(cache,url.slice(1));
}
function intact(entry) {
  if(entry?.fingerprint!==fingerprint||!entry.files?.length) return false;
  return entry.files.every(file=>{
    const key=`${file.url}:${file.sha256}`;
    if(!checks.has(key)) {
      const location=cacheFile(file.url);
      checks.set(key,fs.existsSync(location)&&hash(fs.readFileSync(location))===file.sha256);
    }
    return checks.get(key);
  });
}
const harness=`<!doctype html><html><body><div id="portrait" style="width:115px;height:115px"></div>
<script type="module">
import {createPortrait,isPortraitLoaded,framePortrait,setTalking} from '/src/model.js';
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
window.prepare=async npc=>{
  const element=document.querySelector('#portrait');
  const viewer=await createPortrait(element,npc);
  const wait=async()=>{while(!isPortraitLoaded(viewer)) await delay(50);};
  await wait();await framePortrait(viewer);setTalking(viewer,true);
  await delay(700);await wait();setTalking(viewer,false);await delay(200);await wait();
  return {fileID:viewer.renderer.actors[0].c.aX,profile:element.dataset.cameraProfile,animation:element.dataset.animation};
};
</script></body></html>`;
let server,browser,stopping=false;
process.on('SIGINT',()=>{stopping=true;console.log('Stopping after the current portrait; rerun to resume.');});
const saveReport=()=>atomicJSON(reportPath,report);
try {
  const middleware=localApi();
  server=await createServer({root:path.join(repo,'web/voice-vote'),configFile:false,
    server:{host:'127.0.0.1',port:0},plugins:[{name:'prepare-portraits',configureServer(vite){
      vite.middlewares.use((req,res,next)=>{
        if(req.url==='/__prepare') {res.setHeader('Content-Type','text/html');res.end(harness);return;}
        return middleware(req,res,next);
      });
    }}]});
  await server.listen();
  const base=`http://127.0.0.1:${server.httpServer.address().port}`;
  const installed=process.env.PLAYWRIGHT_FIREFOX_EXECUTABLE;
  browser=await firefox.launch({headless:true,...(installed?{executablePath:installed}:{})});
  saveReport();
  console.log(`${report.mode}: ${portraits.size} unique portraits, ${unavailable.length} quests without a display ID. Cache: ${cache}`);
  let cursor=0;
  const entries=[...portraits];
  async function worker() {
   while(!stopping&&cursor<entries.length) {
    const count=++cursor;
    const [id,portrait]=entries[count-1];
    if(!args.verify&&intact(manifest.portraits[id])) {
      report.reused++;report.ready++;saveReport();console.log(`[${count}/${portraits.size}] ${id}: reused`);continue;
    }
    let failure;
    for(let attempt=0;attempt<=retries;attempt++) {
      const context=await browser.newContext({viewport:{width:300,height:300}});
      const page=await context.newPage(),assets=new Set(),errors=[];
      // No browser access to third-party domains; the server handles cache misses.
      await context.route('**/*',route=>{
        if(new URL(route.request().url()).origin===base) return route.continue();
        errors.push(`External browser request: ${route.request().url()}`);return route.abort();
      });
      page.on('pageerror',error=>errors.push(error.message));
      page.on('request',request=>{
        const url=new URL(request.url());
        if(url.pathname.startsWith('/modelviewer/')) assets.add(url.pathname);
        const match=/^\/api\/portrait-camera\/(\d+)$/.exec(url.pathname);
        if(match) assets.add(`/modelviewer/classicplus/m2/${match[1]}.m2`);
      });
      page.on('response',response=>{if(response.status()>=400)errors.push(`HTTP ${response.status()}: ${new URL(response.url()).pathname}`);});
      try {
        await page.goto(base+'/__prepare');
        await page.waitForFunction(()=>typeof window.prepare==='function',null,{timeout});
        await page.evaluate(npc=>{window.prepare(npc).then(result=>window.result=result,error=>window.error=error.message);},portrait.npc);
        await page.waitForFunction(()=>window.result||window.error,null,{timeout});
        const state=await page.evaluate(()=>({result:window.result,error:window.error}));
        if(state.error||errors.length) throw Error(state.error||errors.join('; '));
        const files=[...assets].sort().map(url=>({url,sha256:hash(fs.readFileSync(cacheFile(url)))}));
        if(!files.length) throw Error('No model assets recorded');
        if(!args.verify) {
          manifest.portraits[id]={fingerprint,preparedAt:new Date().toISOString(),...state.result,files};
          atomicJSON(manifestPath,manifest);
        }
        report.ready++;failure=null;
        console.log(`[${count}/${portraits.size}] ${id}: ready (${files.length} assets)`);
        break;
      } catch(error) {
        failure={displayID:id,questIDs:portrait.questIDs,error:[error.message,...errors].join('; ')};
        console.log(`[${count}/${portraits.size}] ${id}: attempt ${attempt+1} failed: ${failure.error}`);
      } finally {await context.close();}
    }
    if(failure) report.failures.push(failure);
    saveReport();
   }
  }
  await Promise.all(Array.from({length:workers},worker));
  report.completed=!stopping;
} finally {
  report.finishedAt=new Date().toISOString();saveReport();
  await browser?.close();await server?.close();
}
console.log(`Ready ${report.ready}/${report.total}; reused ${report.reused}; failed ${report.failures.length}. Report: ${reportPath}`);
if(!report.completed||report.failures.length) process.exitCode=1;

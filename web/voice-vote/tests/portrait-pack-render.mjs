// Real WebGL poses before/after packing; all resources stay on localhost.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {firefox} from 'playwright';
import {createServer} from 'vite';
import {localApi} from '../server.mjs';

const root=path.resolve(import.meta.dirname,'../../..');
const packRoot=path.join(root,'artifacts/portrait-packs');
const report=JSON.parse(fs.readFileSync(path.join(packRoot,'verification.json')));
const verified=new Set(report.verified.map(row=>row.file));
const catalogue=JSON.parse(fs.readFileSync(process.argv.find(a=>a.startsWith('--catalogue='))?.slice(12)||path.join(root,'artifacts/voice-vote-deploy/catalogue/site-catalogue.json')));
const ids=(process.argv.find(a=>a.startsWith('--quests='))?.slice(9)||'977,1050,179,1479,3741').split(',').map(Number);
const quests=ids.map(id=>catalogue.quests.find(q=>q.questID===id));
assert(quests.every(Boolean),'all test quests must exist');
process.env.VOICE_VOTE_MODEL_OFFLINE='true';
let packed=false;
const harness=`<!doctype html><html><body style="background:#222"><div id="portrait" style="width:300px;height:300px"></div>
<script type="module">
import {createPortrait,isPortraitLoaded,framePortrait,setTalking} from '/src/model.js';
const delay=ms=>new Promise(r=>setTimeout(r,ms));
window.prepare=async npc=>{
 const el=document.querySelector('#portrait'),v=await createPortrait(el,npc);
 const wait=async()=>{const start=Date.now();while(!isPortraitLoaded(v)){if(Date.now()-start>30000)throw Error('Portrait timed out');await delay(25);}};
 await wait();await framePortrait(v);
 const actor=v.renderer.actors[0],m=actor.c;
  actor.setAnimNoSubAnim(true);
  // External .anim loads are not part of renderer.downloads. Wait for the
  // selected clips before comparing poses, and fix random variation selection.
  for(const index of m.am.u.map((a,i)=>[a,i]).filter(([a])=>(a.b===0&&a.f===0)||a.b===60).map(([,i])=>i))await m.am.f(index);
 // Cloth simulation advances with real frame timing and writes bone overrides.
 // Compare the authored animation tracks, not two unrelated physics histories.
 // Disable cloth only in this harness before sampling exact bone matrices.
 m.aC=null;
 for(const bone of m.W) bone.m=null;
 const poses=[];
 for(const talking of [false,true,false]){
   setTalking(v,talking);await delay(150);await wait();actor.setAnimPaused(true);
   const duration=m.aa.e.a?.g||1000;
   for(const fraction of talking?[0,.125,.25,.375,.5,.625,.75,.875,.999]:[0]){
     m.q();actor.setAnimPaused(false);v.renderer.delta=0;m.aa.e.b=duration*fraction;m.ab();actor.setAnimPaused(true);
     poses.push({talking,fraction,animation:el.dataset.animation,index:m.aa.e.e,duration,bones:m.W.map(b=>Array.from(b.j)),
       materials:m.aY.map(t=>({color:Array.from(t.l),alpha:Array.from(t.f),matrices:t.h.map(h=>Array.from(h))}))});
   }
 }
 window.viewer=v;return {fileID:m.aX,profile:el.dataset.cameraProfile,poses};
};
</script></body></html>`;
const middleware=localApi();
const server=await createServer({root:path.join(root,'web/voice-vote'),configFile:false,server:{host:'127.0.0.1',port:0},plugins:[{
  name:'packed-portrait-regression',configureServer(vite){vite.middlewares.use((req,res,next)=>{
    if(req.url==='/__test'){res.setHeader('Content-Type','text/html');res.end(harness);return;}
    const match=/^\/modelviewer\/(?:portrait-v1\/)?classicplus\/m2\/(\d+\.m2)$/.exec(req.url);
    if(packed&&match&&verified.has(match[1])){res.setHeader('Content-Type','application/octet-stream');res.end(fs.readFileSync(path.join(packRoot,match[1])));return;}
    req.url=req.url.replace('/modelviewer/portrait-v1/','/modelviewer/');
    return middleware(req,res,next);
  });}
}]});
await server.listen();const base=`http://127.0.0.1:${server.httpServer.address().port}`;
const installed=process.env.PLAYWRIGHT_FIREFOX_EXECUTABLE;
const browser=await firefox.launch({headless:true,...(installed?{executablePath:installed}:{})});
try{
 for(const quest of quests){
  const results=[];
  for(const mode of [false,true]){
    packed=mode;const page=await browser.newPage(),errors=[];
    await page.addInitScript(()=>{Math.random=()=>0.5;});
    await page.route('**/*',route=>new URL(route.request().url()).origin===base?route.continue():route.abort());
    page.on('pageerror',e=>errors.push(e.message));
    page.on('response',r=>{if(r.status()>=400)errors.push(`${r.status()} ${r.url()}`);});
    try{
      await page.goto(base+'/__test');await page.waitForFunction(()=>window.prepare);
      const result=await page.evaluate(npc=>Promise.race([window.prepare(npc),new Promise((_,reject)=>setTimeout(()=>reject(Error('Pose verification timed out')),45000))]),quest.npc);
      assert.deepEqual(errors,[]);results.push(result);
      await page.screenshot({path:path.join(packRoot,`${quest.questID}-${mode?'packed':'original'}.png`)});
    }finally{await page.close();}
  }
  if(JSON.stringify(results[1])!==JSON.stringify(results[0])){
    fs.writeFileSync(path.join(packRoot,`${quest.questID}-mismatch.json`),JSON.stringify(results));
    throw Error(`Quest ${quest.questID}: rest/talk poses differ; see ${quest.questID}-mismatch.json`);
  }
  console.log(`PASS quest ${quest.questID}: neutral pose, 9 talk samples, return to neutral, materials and profile identical`);
 }
}finally{await browser.close();await server.close();}

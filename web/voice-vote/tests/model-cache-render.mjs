// Real cached viewer and WebGL, with HTTP caching enabled (no Playwright routes).
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createServer} from 'vite';
import {firefox} from 'playwright';
import {localApi} from '../server.mjs';

const root=path.resolve(import.meta.dirname,'../../..');
process.env.VOICE_VOTE_MODEL_OFFLINE='true';
const catalogue=JSON.parse(fs.readFileSync(path.join(root,'artifacts/voice-vote-deploy/catalogue/site-catalogue.json')));
const ids=(process.argv.find(a=>a.startsWith('--quests='))?.slice(9)||'179,925,5657,97326,1116,898,271').split(',').map(Number);
const requests=[];
const api=localApi();
const html=`<!doctype html><html><body><div id="portrait" style="width:300px;height:300px"></div>
<script type="module">
import {createPortrait,isPortraitLoaded,framePortrait,setTalking} from '/src/model.js';
window.prepare=async npc=>{
 const el=document.querySelector('#portrait'),v=await createPortrait(el,npc);
 const wait=async()=>{const start=Date.now();while(!isPortraitLoaded(v)){if(Date.now()-start>30000)throw Error('Portrait timed out');await new Promise(r=>setTimeout(r,25));}};
 await wait();await framePortrait(v);setTalking(v,true);await new Promise(r=>setTimeout(r,800));await wait();
 setTalking(v,false);await wait();return {profile:el.dataset.cameraProfile,animation:el.dataset.animation};
};</script></body></html>`;
const server=await createServer({root:path.join(root,'web/voice-vote'),configFile:false,server:{host:'127.0.0.1',port:0},plugins:[{
 name:'versioned-portrait-test',configureServer(vite){vite.middlewares.use((req,res,next)=>{
   if(req.url==='/__test'){res.setHeader('Content-Type','text/html');res.end(html);return;}
   if(req.url.startsWith('/modelviewer/')) requests.push(req.url);
   return api(req,res,next);
 });}
}]});
let browser;
try {
 await server.listen();const base=`http://127.0.0.1:${server.httpServer.address().port}`;
 browser=await firefox.launch({headless:true});const page=await browser.newPage(),errors=[];
 page.on('pageerror',e=>errors.push(e.message));
 page.on('request',r=>{if(new URL(r.url()).origin!==base)errors.push(`External request: ${r.url()}`);});
 page.on('response',r=>{if(r.status()>=400)errors.push(`HTTP ${r.status()}: ${r.url()}`);});
 for(const id of ids) {
   const quest=catalogue.quests.find(q=>q.questID===id);assert(quest);
   for(const repeat of [false,true]) {
     const start=requests.length;
     await page.goto(base+'/__test');await page.waitForFunction(()=>window.prepare);
     const result=await page.evaluate(npc=>window.prepare(npc),quest.npc);
     assert.equal(result.animation,'Stand');assert(result.profile);assert.deepEqual(errors,[]);
     if(repeat)assert.equal(requests.length,start,`Quest ${id} should reuse all model resources`);
   }
   console.log(`PASS quest ${id}: versioned neutral/talk/reset; repeated portrait made no model requests.`);
 }
 for(const request of requests)assert.match(request,/\bv=[a-f0-9]{64}(?:&|$)/,`Unversioned viewer resource: ${request}`);
 console.log(`PASS: ${requests.length} resource requests all had content hashes; no external requests.`);
} finally {await browser?.close();await server.close();}

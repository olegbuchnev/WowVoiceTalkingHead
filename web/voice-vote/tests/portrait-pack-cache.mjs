// Optional integration gate: real cached assets, actual viewer parser, no network.
// node tests/portrait-pack-cache.mjs [--ids=119369,950080]
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {firefox} from 'playwright';
import {gzipSync} from 'node:zlib';
import {createHash} from 'node:crypto';
import {packPortraitModel,chunksOf} from '../portrait-pack.mjs';
import {readPortraitCamera} from '../portrait-camera.mjs';

const root=path.resolve(import.meta.dirname,'../../..');
const cache=path.join(root,'artifacts/voice-vote-model-cache/modelviewer');
const out=path.join(root,'artifacts/portrait-packs');fs.mkdirSync(out,{recursive:true});
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const idsArg=process.argv.find(arg=>arg.startsWith('--ids='))?.slice(6).split(',');
const files=fs.readdirSync(path.join(cache,'classicplus/m2')).filter(f=>f.endsWith('.m2')&&(!idsArg||idsArg.includes(f.split('.')[0])));
const viewer=fs.readFileSync(path.join(cache,'live/viewer/viewer.min.js'),'utf8');
const marker='window.ZamModelViewer=Tf,ts()';
assert.equal(viewer.split(marker).length,2,'viewer parser adapter must match exactly');
const injected=viewer.replace(marker,`${marker};window.parseM2=(m,s)=>new pA(new hA(m),new CA(s),null)`);
let current;
const server=createServer((req,res)=>{
  if(req.url==='/jquery.js'){res.setHeader('Content-Type','text/javascript');res.end(fs.readFileSync(path.join(root,'web/voice-vote/node_modules/jquery/dist/jquery.min.js')));}
  else if(req.url==='/viewer.js'){res.setHeader('Content-Type','text/javascript');res.end(injected);}
  else if(req.url==='/original')res.end(current.input);
  else if(req.url==='/packed')res.end(current.packed);
  else if(req.url==='/skin')res.end(current.skin);
  else res.end('<!doctype html><html><body><script>window.WH={debug(){},WebP:{getImageExtension(){return ".webp"}}};</script><script src="/jquery.js"></script><script src="/viewer.js"></script></body></html>');
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const base=`http://127.0.0.1:${server.address().port}`;
const installed=process.env.PLAYWRIGHT_FIREFOX_EXECUTABLE;
const browser=await firefox.launch({headless:true,...(installed?{executablePath:installed}:{})});
const report={version:1,viewerSha256:hash(Buffer.from(viewer)),packerSha256:hash(fs.readFileSync(new URL('../portrait-pack.mjs',import.meta.url))),verified:[],unsupported:[],failed:[]};
try {
  const page=await browser.newPage();
  await page.route('**/*',route=>new URL(route.request().url()).origin===base?route.continue():route.abort());
  page.on('pageerror',e=>console.error(e.message));
  await page.goto(base);
  await page.waitForFunction(()=>typeof window.parseM2==='function');
  for(const file of files){
    let packed,input,skin,stats;
    try {
      input=fs.readFileSync(path.join(cache,'classicplus/m2',file));
      const skinID=chunksOf(input).find(c=>c.tag==='SFID')?.bytes.readUInt32LE();
      skin=fs.readFileSync(path.join(cache,'classicplus/skin',`${skinID}.skin`));
      ({bytes:packed,stats}=packPortraitModel(input,skin));
    }catch(e){report.unsupported.push({file,error:e.message});continue;}
    try{
      assert.deepEqual(readPortraitCamera(packed),readPortraitCamera(input),'authored camera must stay identical');
      current={input,packed,skin};
      const failures=await page.evaluate(async stats=>{
        const fetchBytes=async url=>(await fetch(url)).arrayBuffer();
        const s=await fetchBytes('/skin');
        const original=window.parseM2(await fetchBytes('/original'),s),packed=window.parseM2(await fetchBytes('/packed'),s);
        const differences=[];
        const equal=(a,b,label)=>{if(JSON.stringify(a)!==JSON.stringify(b))differences.push(label);};
        equal(packed.h,original.h.slice(0,stats.vertices),'base vertices');
        const selected=new Set(stats.retainedSequences.map(s=>s.index));
        const compareTrack=(a,b,label)=>{
          equal(a.e.length,b.e.length,`${label} table length`);
          for(let i=0;i<a.e.length;i++){
            const keep=selected.has(i)||(i===0&&(!selected.size||[...selected].some(s=>s>=a.e.length)));
            if(keep)equal(a.e[i],b.e[i],`${label} sequence ${i}`);
            else if(b.e[i].d?.length||b.e[i].b?.length||b.e[i].e)differences.push(`${label} unused keys ${i}`);
          }
        };
        for(let i=0;i<original.j.length;i++){
          const a=original.j[i],b=packed.j[i];
          for(const key of Object.keys(a)){
            if(['i','h','e'].includes(key))compareTrack(a[key],b[key],`bone ${i}/${key}`);
            else equal(a[key],b[key],`bone ${i}/${key}`);
          }
        }
        for(const key of Object.keys(original)){
          if(['h','j','Y','u','s','V','i','ac'].includes(key))continue;
          equal(original[key],packed[key],key);
        }
        for(const [field,tracks] of [['s',['b','d','a']],['V',['c','d']],['i',['d']],['ac',['h','j','i','a','e','d','b']]]){
          equal(original[field].length,packed[field].length,field);
          for(let i=0;i<original[field].length;i++)for(const key of tracks)
            compareTrack(original[field][i][key],packed[field][i][key],`${field}/${i}/${key}`);
        }
        return differences.slice(0,15);
      },stats);
      assert.deepEqual(failures,[]);
      const entry={file,...stats,sourceSha256:hash(input),skinSha256:hash(skin),sourceGzipBytes:gzipSync(input,{level:3}).length,gzipBytes:gzipSync(packed,{level:3}).length};
      report.verified.push(entry);fs.writeFileSync(path.join(out,file),packed);
      console.log(`PASS ${file}: ${entry.sourceGzipBytes} -> ${entry.gzipBytes} gzip bytes`);
    }catch(e){report.failed.push({file,error:e.message});console.log(`FAIL ${file}: ${e.message}`);}
  }
}finally{
  await browser.close();await new Promise(resolve=>server.close(resolve));
  fs.writeFileSync(path.join(out,'verification.json'),JSON.stringify(report,null,2)+'\n');
}
console.log(JSON.stringify({verified:report.verified.length,unsupported:report.unsupported.length,failed:report.failed.length}));
if(report.failed.length)process.exitCode=1;

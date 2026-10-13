import {createServer} from 'node:http';
import {once} from 'node:events';
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {firefox} from 'playwright';
import {modelHash,sendModelAsset} from '../model-versions.mjs';

const model='/modelviewer/portrait-v1/classicplus/m2/1.m2';
const texture='/modelviewer/portrait-v1/classicplus/textures/2.webp';
const files=new Map([[model,Buffer.from('model A')],[texture,Buffer.from('texture')]]);
const requests=[];
const server=createServer((req,res)=>{
  const url=new URL(req.url,'http://localhost');
  if(files.has(url.pathname)) {
    requests.push(req.url);sendModelAsset(req,res,url,files.get(url.pathname),'application/octet-stream');return;
  }
  if(url.pathname==='/api/model-versions/7') {
    res.writeHead(200,{'Content-Type':'application/json','Cache-Control':'no-cache'}).end(JSON.stringify({assets:Object.fromEntries([...files].map(([p,b])=>[p,modelHash(b)]))}));return;
  }
  if(url.pathname==='/client.js') {
    res.writeHead(200,{'Content-Type':'text/javascript'}).end(fs.readFileSync(new URL('../src/model-versions.js',import.meta.url)));return;
  }
  res.writeHead(200,{'Content-Type':'text/html','Cache-Control':'no-cache'}).end(`<script type="module">
    import {loadModelVersions,modelAssetURL} from '/client.js';
    window.loaded=(async()=>{await loadModelVersions(7);return Promise.all(${JSON.stringify([model,texture])}.map(async p=>{
      const url=modelAssetURL(p);return {url,body:await (await fetch(url)).text()};
    }));})();</script>`);
});
server.listen(0,'127.0.0.1');await once(server,'listening');
let browser;
try {
  // No route interception: it disables the browser HTTP cache.
  browser=await firefox.launch({headless:true});
  const page=await browser.newPage(),base=`http://127.0.0.1:${server.address().port}`;
  const load=async()=>{await page.goto(base);await page.waitForFunction(()=>window.loaded);return page.evaluate(()=>window.loaded);};
  const first=await load();assert.equal(requests.length,2);
  assert.deepEqual(await load(),first);assert.equal(requests.length,2,'Revisiting must not request cached resources');
  await page.reload();assert.deepEqual(await page.evaluate(()=>window.loaded),first);
  assert.equal(requests.length,2,'Normal refresh must reuse immutable resources');
  files.set(model,Buffer.from('model B'));
  const updated=await load();assert.equal(updated[0].body,'model B');assert.notEqual(updated[0].url,first[0].url);
  assert.equal(updated[1].url,first[1].url);assert.equal(requests.length,3,'Only the changed model downloads again');
  const old=await fetch(first[0].url);assert.equal(old.status,410,'Old hashes must never serve new content');
  console.log('PASS: year-long browser cache survives refresh; changed files get new URLs, unchanged textures stay cached.');
} finally {await browser?.close();await new Promise(resolve=>server.close(resolve));}

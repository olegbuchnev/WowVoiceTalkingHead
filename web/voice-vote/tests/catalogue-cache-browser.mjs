import {createServer} from 'node:http';
import {once} from 'node:events';
import fs from 'node:fs';
import {gzipSync} from 'node:zlib';
import assert from 'node:assert/strict';
import {firefox} from 'playwright';

// Real HTTP cache: Playwright routing disables caching and cannot test reloads.
let revision=1,fail=false;
const requests=[];
const client=fs.readFileSync(new URL('../src/catalogue-refresh.js',import.meta.url));
const server=createServer((req,res)=>{
  if(req.url==='/client.js') {
    res.writeHead(200,{'Content-Type':'text/javascript'}).end(client);return;
  }
  if(req.url==='/api/catalogue') {
    const etag=`W/"catalogue-${revision}"`;
    const status=fail?503:req.headers['if-none-match']===etag?304:200;
    requests.push({status,validator:req.headers['if-none-match']});
    res.writeHead(status,{'Content-Type':'application/json','Cache-Control':'no-cache',
      'ETag':etag,'Content-Encoding':'gzip','Vary':'Accept-Encoding'});
    res.end(status===200?gzipSync(JSON.stringify({quests:[{questID:revision}]})):undefined);return;
  }
  res.writeHead(200,{'Content-Type':'text/html','Cache-Control':'no-cache'}).end(
    '<script type="module">import {createCatalogueClient} from "/client.js";window.client=createCatalogueClient();window.loaded=client.load();</script>');
});
server.listen(0,'127.0.0.1');await once(server,'listening');
let browser;
try {
  browser=await firefox.launch({headless:true});
  const page=await browser.newPage();
  const loaded=()=>page.evaluate(()=>window.loaded);
  await page.goto(`http://127.0.0.1:${server.address().port}`);
  assert.equal((await loaded()).quests[0].questID,1);
  assert.equal(requests.at(-1).status,200);
  await page.reload();
  assert.equal((await loaded()).quests[0].questID,1);
  assert.equal(requests.at(-1).status,304,'Reload must validate and reuse the cached body');
  assert(await page.evaluate(async()=>await client.load()===await window.loaded));
  assert.equal(requests.at(-1).status,304);
  revision=2;
  assert.equal((await page.evaluate(()=>client.load())).quests[0].questID,2);
  assert.equal(requests.at(-1).status,200,'Changed catalogue must replace the old body');
  await page.reload();
  assert.equal((await loaded()).quests[0].questID,2);
  assert.equal(requests.at(-1).status,304);
  fail=true;
  assert.equal(await page.evaluate(()=>client.load().then(()=>false,()=>true)),true,
    'A failed revalidation must not silently serve stale data');
  assert.equal(requests.at(-1).status,503);
  console.log('PASS: reload reuses the compressed catalogue, validates every request and receives updated revisions.');
} finally {await browser?.close();await new Promise(resolve=>server.close(resolve));}

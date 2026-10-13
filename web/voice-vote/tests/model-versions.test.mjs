import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {createModelVersions,modelHash,viewerPath,viewerStylePath,sendModelAsset,adaptViewerAssetURLs} from '../model-versions.mjs';

test('portrait hashes track served bytes, not stale manifest hashes or timestamps',async()=>{
  const root=await fs.mkdtemp(path.join(os.tmpdir(),'model-versions-'));
  try {
    const model='/modelviewer/portrait-v1/classicplus/m2/1.m2';
    const texture='/modelviewer/portrait-v1/classicplus/textures/2.webp';
    const bytes=new Map([[viewerPath,'adapted viewer'],[viewerStylePath,'style'],[model,'packed A'],[texture,'texture']]);
    await fs.writeFile(path.join(root,'manifest.json'),JSON.stringify({portraits:{7:{files:[
      {url:'/modelviewer/classicplus/m2/1.m2',sha256:'stale'},
      {url:'/modelviewer/classicplus/textures/2.webp',sha256:'stale'},
    ]}}}));
    const versions=createModelVersions({cacheRoot:()=>root,readAsset:async url=>bytes.get(url)});
    const first=await versions(7);
    assert.equal(first.assets[model],modelHash('packed A'));
    bytes.set(model,'packed B');
    const next=await versions(7);
    assert.notEqual(next.assets[model],first.assets[model]);
    assert.equal(next.assets[texture],first.assets[texture]);
    assert.equal(next.assets[viewerPath],modelHash('adapted viewer'));
    await assert.rejects(versions(8),/manifest unavailable/);
  } finally {await fs.rm(root,{recursive:true,force:true});}
});

test('only matching content-addressed resources get a year of immutable caching',()=>{
  const bytes=Buffer.from('model'),hash=modelHash(bytes);
  function get(query='',headers={},method='GET') {
    const res={writeHead(status,headers){this.status=status;this.headers=headers;return this;},end(body){this.body=body;}};
    sendModelAsset({headers,method},res,new URL(`http://localhost/modelviewer/classicplus/m2/1.m2${query}`),bytes,'application/octet-stream');
    return res;
  }
  assert.equal(get().headers['Cache-Control'],'no-cache');
  assert.equal(get(`?v=${hash}`).headers['Cache-Control'],'public, max-age=31536000, immutable');
  assert.deepEqual(get(`?v=${hash}`).body,bytes);
  for(const query of ['?v=','?v=bad',`?v=${'0'.repeat(64)}`]) {
    const r=get(query);assert.equal(r.status,410);assert.equal(r.headers['Cache-Control'],'no-store');assert.equal(r.body,undefined);
  }
  const r=get(`?v=${hash}`,{'if-none-match':`W/"${hash}"`});assert.equal(r.status,304);assert.equal(r.body,undefined);
  assert.equal(get(`?v=${hash}`,{},'HEAD').body,undefined);
});

test('a vendor transport change fails explicitly rather than silently bypassing versioning',()=>{
  assert.throws(()=>adaptViewerAssetURLs(Buffer.from('new vendor build')),/transport changed/);
});

import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {modelAsset} from '../server.mjs';

test('offline cache never fetches missing assets; online files publish atomically',async()=>{
  const directory=fs.mkdtempSync(path.join(os.tmpdir(),'portrait-cache-test-'));
  const previousCache=process.env.VOICE_VOTE_MODEL_CACHE,previousOffline=process.env.VOICE_VOTE_MODEL_OFFLINE;
  const fetchOriginal=globalThis.fetch;let requests=0;
  process.env.VOICE_VOTE_MODEL_CACHE=directory;
  globalThis.fetch=async()=>{requests++;return new Response('test model bytes');};
  try {
    process.env.VOICE_VOTE_MODEL_OFFLINE='true';
    await assert.rejects(modelAsset('/modelviewer/classicplus/m2/1.m2'),/missing from offline cache/);
    assert.equal(requests,0);
    process.env.VOICE_VOTE_MODEL_OFFLINE='false';
    assert.equal((await modelAsset('/modelviewer/classicplus/m2/1.m2')).toString(),'test model bytes');
    assert.equal(requests,1);
    assert.deepEqual(fs.readdirSync(path.join(directory,'modelviewer/classicplus/m2')),['1.m2']);
    process.env.VOICE_VOTE_MODEL_OFFLINE='true';
    assert.equal((await modelAsset('/modelviewer/classicplus/m2/1.m2')).toString(),'test model bytes');
    assert.equal(requests,1);
    await assert.rejects(modelAsset('/modelviewer/classicplus/../secret'),/Invalid model path/);
  } finally {
    globalThis.fetch=fetchOriginal;
    if(previousCache===undefined) delete process.env.VOICE_VOTE_MODEL_CACHE;else process.env.VOICE_VOTE_MODEL_CACHE=previousCache;
    if(previousOffline===undefined) delete process.env.VOICE_VOTE_MODEL_OFFLINE;else process.env.VOICE_VOTE_MODEL_OFFLINE=previousOffline;
    fs.rmSync(directory,{recursive:true,force:true});
  }
});

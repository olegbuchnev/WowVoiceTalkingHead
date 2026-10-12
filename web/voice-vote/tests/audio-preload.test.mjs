import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createAudioPreloader} from '../src/audio-preload.js';

const tick=()=>new Promise(resolve=>setImmediate(resolve));
test('preloads every variant, reuses bytes, and releases obsolete recordings',async()=>{
  const calls=[],revoked=[];
  const cache=createAudioPreloader({
    fetcher:async(url)=>{calls.push(url);return {ok:true,blob:async()=>url};},
    createURL:blob=>`blob:${blob}`,revokeURL:url=>revoked.push(url),
  });
  try {
    const variants=['a','b','c','next-a','next-b'].map(url=>({url}));
    cache.retain(variants);await tick();
    assert.deepEqual(calls,variants.map(v=>v.url));
    for(const v of variants) assert.equal(cache.source(v),`blob:${v.url}`);
    cache.retain(variants);await tick();assert.equal(calls.length,5);
    cache.retain([{url:'next-a'},{url:'next-b'},{url:'new-version'}]);await tick();
    assert.deepEqual(revoked,['blob:a','blob:b','blob:c']);
    assert.equal(cache.source({url:'new-version'}),'blob:new-version');
  } finally {cache.dispose();}
  assert.equal(revoked.length,6);
});
test('early clicks stream immediately and cancelled downloads cannot repopulate the cache',async()=>{
  const response=Promise.withResolvers();let signal,created=0;
  const cache=createAudioPreloader({fetcher:(_url,options)=>{signal=options.signal;return response.promise;},createURL:()=>{created++;return 'blob:test';}});
  cache.retain([{url:'a'}]);await tick();
  assert.equal(cache.source({url:'a'}),'a');
  cache.retain([]);assert.equal(signal.aborted,true);
  response.resolve({ok:true,blob:async()=>new Blob(['test'])});await tick();
  assert.equal(created,0);cache.dispose();
});
test('failed preload falls back to streaming and can be retried',async()=>{
  let attempts=0;
  const cache=createAudioPreloader({fetcher:async()=>{attempts++;return {ok:false,status:503};}});
  try {
    cache.retain([{url:'a'}]);await tick();assert.equal(cache.source({url:'a'}),'a');
    cache.retain([{url:'a'}]);await tick();assert.equal(attempts,2);
  } finally {cache.dispose();}
});

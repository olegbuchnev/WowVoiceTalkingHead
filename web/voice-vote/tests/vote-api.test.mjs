import {test} from 'node:test';
import assert from 'node:assert/strict';
import {migrateLocalVotes,submitVote} from '../src/vote-api.js';
import {voteStorageKey} from '../src/vote-history.js';

test('legacy migration removes only acknowledged votes and retries safely after failure',async t=>{
  const votes=[1,2,3].map(questID=>({questID,selected:'chosen',candidates:[{id:'chosen'},{id:'other'}]}));
  const storage=new Map([[voteStorageKey,JSON.stringify(votes)]]);
  t.mock.method(globalThis,'fetch',async (_url,options)=>{
    const vote=JSON.parse(options.body);
    return new Response(JSON.stringify({error:'Unavailable'}),{status:vote.questID===1 ? 200 : vote.questID===2 ? 409 : 503});
  });
  globalThis.localStorage={getItem:key=>storage.get(key),setItem:(key,value)=>storage.set(key,value),removeItem:key=>storage.delete(key)};
  try {
    await assert.rejects(migrateLocalVotes());
    assert.deepEqual(JSON.parse(storage.get(voteStorageKey)).map(v=>v.questID),[2,3]);
    globalThis.fetch=async()=>new Response('{}',{status:200});
    await migrateLocalVotes();assert(!storage.has(voteStorageKey));
  } finally {delete globalThis.localStorage;}
});

test('ballots submit only comparison identity, leaving trusted metadata to the server',async t=>{
  t.mock.method(globalThis,'fetch',async(url,options)=>{
    assert.equal(url,'/api/votes');assert.equal(options.method,'POST');
    assert.deepEqual(JSON.parse(options.body),{questID:179,selectedId:'first',variantIds:['first','second']});
    return new Response(JSON.stringify({selected:'CatQuest',total:1}));
  });
  assert.equal((await submitVote(179,'first',['first','second'])).total,1);
});

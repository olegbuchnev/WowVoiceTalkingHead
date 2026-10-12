import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {localApi} from '../server.mjs';
import {createCatalogueClient,questKey,refreshComparisons,withLocalRatings} from '../src/catalogue-refresh.js';

const quest=(id,revision=1)=>({questID:id,npc:{displayID:100},text:'Description',variants:[
  {id:`${id}-a-${revision}`,source:'CatQuest',url:`/audio/${revision}`},
  {id:`${id}-b`,source:'WowVoice',url:'/audio/fixed'},
]});
const entry=q=>({key:q.questID,quest:q,variants:[...q.variants].reverse()});

test('refresh retains active comparison and portrait, replaces only unseen recording IDs/URLs in blind order',()=>{
  const entries=[entry(quest(1)),entry(quest(2)),entry(quest(3))];
  const fresh=[quest(1,2),quest(2,2),quest(3)];
  const updated=refreshComparisons(entries,fresh,1);
  assert.equal(updated[0],entries[0]);
  assert.equal(updated[1].key,entries[1].key);
  assert.deepEqual(updated[1].variants.map(v=>v.source),entries[1].variants.map(v=>v.source));
  assert.equal(updated[1].variants[1].id,'2-a-2');
  assert.equal(updated[1].variants[1].url,'/audio/2');
  assert.equal(updated[2],entries[2]);
  assert.equal(entries[1].variants[1].id,'2-a-1','refresh must not mutate an in-flight ballot');
});

test('reserve drops unavailable quests, accepts changed variant count and remounts a changed portrait',()=>{
  const q=quest(2,2);q.npc.displayID=200;q.variants.push({id:'wayfarer',source:'Wayfarer'});
  const updated=refreshComparisons([entry(quest(1)),entry(quest(2))],[q]);
  assert.equal(updated.length,1);assert.equal(updated[0].variants.length,3);
  assert.notEqual(updated[0].key,2);
});

test('optimistic local ratings do not hide a new recording revision',()=>{
  const local=new Set([questKey(quest(1)),questKey(quest(2))]);
  const priorities=[{questID:1,rated:false},{questID:2,rated:false},{questID:3,rated:true}];
  assert.deepEqual(withLocalRatings(priorities,[quest(1,2),quest(2),quest(3)],local).map(p=>p.rated),[false,true,true]);
});

test('conditional catalogue requests reuse snapshots and coalesce concurrent refreshes',async()=>{
  let data={quests:[quest(1)]};
  let handler=localApi({loadData:()=>({catalogue:data})});
  const server=createServer((req,res)=>handler(req,res,()=>res.writeHead(404).end()));
  server.listen(0,'127.0.0.1');await once(server,'listening');
  try {
    const responses=[];
    const client=createCatalogueClient({request:async(url,options)=>{
      const response=await fetch(`http://127.0.0.1:${server.address().port}${url}`,options);
      responses.push(response.status);return response;
    }});
    const first=client.load();assert.equal(client.load(),first);
    const snapshot=await first;
    assert.equal(await client.load(),snapshot);
    const url=`http://127.0.0.1:${server.address().port}/api/catalogue`;
    const etag=(await fetch(url)).headers.get('ETag');
    for(const tag of [`W/${etag}`,`"obsolete", W/${etag}`,'*']) {
      const response=await fetch(url,{headers:{'If-None-Match':tag}});
      assert.equal(response.status,304,'gzip proxies may return weak ETags');
      assert.equal(await response.text(),'');
    }
    data={quests:[quest(1,2)]};handler=localApi({loadData:()=>({catalogue:data})});
    assert.notEqual(await client.load(),snapshot);
    assert.deepEqual(responses,[200,304,200]);
    assert.equal(client.current().quests[0].variants[0].id,'1-a-2');
  } finally {await new Promise(resolve=>server.close(resolve));}
});

test('failed refresh keeps the previous snapshot and a subsequent load can recover',async()=>{
  let fail=false;
  const client=createCatalogueClient({request:async()=>{
    if(fail) throw Error('Offline');
    return new Response(JSON.stringify({quests:[quest(1)]}));
  }});
  const original=await client.load();fail=true;
  await assert.rejects(client.load(),/Offline/);
  assert.equal(client.current(),original);fail=false;
  assert.equal(await client.load(),original);
});

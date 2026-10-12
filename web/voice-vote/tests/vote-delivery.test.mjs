import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createVoteDelivery} from '../src/vote-delivery.js';
const tick=()=>new Promise(resolve=>setImmediate(resolve));
test('enqueue returns immediately and preserves request order until admission',async()=>{
  let release;const accepted=[],sent=[];
  const delivery=createVoteDelivery({identify:async()=>{},send:async ballot=>{sent.push(ballot);if(ballot.id===1)await new Promise(resolve=>{release=resolve;});return {};},onAccepted:ballot=>accepted.push(ballot.id)});
  delivery.enqueue({id:1});delivery.enqueue({id:2});
  await tick();assert.deepEqual(sent,[{id:1}]);assert.deepEqual(accepted,[]);
  release();await tick();assert.deepEqual(accepted,[1,2]);delivery.stop();
});
test('temporary admission failure retries in memory without advancing order',async()=>{
  let attempts=0;const accepted=[];
  const delivery=createVoteDelivery({identify:async()=>{},send:async()=>{if(!attempts++)throw Error('Offline');return {};},onAccepted:b=>accepted.push(b.id)});
  delivery.enqueue({id:1});await tick();assert.deepEqual(accepted,[]);
  delivery.retry();await tick();assert.deepEqual(accepted,[1]);delivery.stop();
});

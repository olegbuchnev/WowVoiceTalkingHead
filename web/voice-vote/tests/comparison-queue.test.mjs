import test from 'node:test';
import assert from 'node:assert/strict';
import {createComparisonQueue,createComparisonBatch} from '../src/comparison-queue.js';
const quests=[1,2,3].map(questID=>({questID,variants:[{id:'a'},{id:'b'},{id:'c'}]}));

test('batches cap at five, shrink to remaining unrated quests and require explicit replays',()=>{
  const catalogue=Array.from({length:8},(_,i)=>({...quests[0],questID:i+1}));
  const priorities=catalogue.map(q=>({questID:q.questID,rated:false}));
  assert.deepEqual(createComparisonBatch(catalogue,priorities).map(e=>e.quest.questID),[1,2,3,4,5]);
  priorities.forEach(p=>p.rated=p.questID<=6);
  assert.deepEqual(createComparisonBatch(catalogue,priorities).map(e=>e.quest.questID),[7,8]);
  priorities.forEach(p=>p.rated=true);
  assert.deepEqual(createComparisonBatch(catalogue,priorities),[]);
  const replay=createComparisonBatch(catalogue,priorities,{repeat:true,previousQuestID:1});
  assert.equal(replay.length,5); assert.notEqual(replay[0].quest.questID,1);
  assert.equal(new Set(replay.map(e=>e.quest.questID)).size,5);
  assert.equal(createComparisonBatch([quests[0]],[],{repeat:true}).length,1);
  assert.deepEqual(createComparisonBatch([],[]),[]);
});

test('reserved comparisons visit each quest once per round and do not repeat at round boundaries',()=>{
  const queue=createComparisonQueue(quests,()=>.5);
  const entries=Array.from({length:12},()=>queue.take());
  for(let i=0;i<12;i+=3) assert.equal(new Set(entries.slice(i,i+3).map(e=>e.quest.questID)).size,3);
  for(let i=1;i<12;i++) assert.notEqual(entries[i].quest.questID,entries[i-1].quest.questID);
  assert.equal(new Set(entries.map(e=>e.key)).size,12);
  assert.deepEqual(entries[0].variants.map(v=>v.id).sort(),['a','b','c']);
  const reserved=entries[1]; queue.take();
  assert.strictEqual(entries[1],reserved);
  assert.deepEqual(quests[0].variants.map(v=>v.id),['a','b','c']);
});

test('empty and single-quest catalogues are supported',()=>{
  assert.equal(createComparisonQueue([]).take(),null);
  const queue=createComparisonQueue([quests[0]]);
  assert.notEqual(queue.take().key,queue.take().key);
});

test('server priorities order current and preloaded quests without replacing reservations',()=>{
  const queue=createComparisonQueue(quests,()=>.5,[{questID:3},{questID:2},{questID:1}]);
  const current=queue.take(), reserve=queue.take();
  assert.equal(current.quest.questID,3);
  assert.equal(reserve.quest.questID,2);
  queue.updatePriority([{questID:2},{questID:3},{questID:1}]);
  assert.equal(queue.take().quest.questID,1);
  assert.equal(reserve.quest.questID,2);
  assert.equal(queue.take().quest.questID,2);
});

test('updated priorities reorder unreserved quests and ignore missing catalogue entries',()=>{
  const queue=createComparisonQueue(quests,()=>.999,[{questID:999},{questID:1},{questID:2},{questID:3}]);
  assert.equal(queue.take().quest.questID,1);
  queue.updatePriority([{questID:3},{questID:2},{questID:1}]);
  assert.equal(queue.take().quest.questID,3);
  assert.equal(queue.take().quest.questID,2);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import {countVotes,readVotes} from '../src/vote-history.js';
const vote=pack=>({selected:'chosen',candidates:[{id:'other',pack:'CatQuest_Voices'},{id:'chosen',pack}]});

test('personal chart groups chosen recordings by library, including all Wayfarer modules and old records',()=>{
  assert.deepEqual(countVotes([vote('WowVoiceSounds'),vote('CatQuest_Voices'),
    ...['Alliance','Horde','Shared'].map(name=>vote(`Wayfarer_Voices_${name}`)),
    null,{},vote('unknown')]),{WowVoice:1,CatQuest:1,Wayfarer:3});
  assert.equal(countVotes(Array.from({length:205},()=>vote('WowVoiceSounds'))).WowVoice,205);
});
test('history defaults to empty and rejects corrupt storage without overwriting it',()=>{
  assert.deepEqual(readVotes({getItem:()=>null}),[]);
  assert.throws(()=>readVotes({getItem:()=>'{'}));
  assert.throws(()=>readVotes({getItem:()=>'{"not":"an array"}'}));
});

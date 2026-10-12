import test from 'node:test';
import assert from 'node:assert/strict';
import {sessionSummary} from '../src/session-votes.js';

test('session counts replace repeated choices and start empty on a fresh page',()=>{
  const votes={first:'CatQuest',second:'WowVoice'};
  assert.deepEqual(sessionSummary(votes),{counts:{WowVoice:1,CatQuest:1,Wayfarer:0},total:2});
  votes.first='Wayfarer';
  assert.deepEqual(sessionSummary(votes),{counts:{WowVoice:1,CatQuest:0,Wayfarer:1},total:2});
  assert.deepEqual(sessionSummary({}),{counts:{WowVoice:0,CatQuest:0,Wayfarer:0},total:0});
});

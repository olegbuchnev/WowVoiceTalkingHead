import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createParticipationTracker} from '../src/participation.js';

test('playback stays local until a confirmed vote and deduplicates within the visit',async t=>{
  const events=[];
  t.mock.method(globalThis,'fetch',async (url,options)=>{events.push(JSON.parse(options.body));return {ok:true};});
  const tracker=createParticipationTracker();
  tracker.played(1479,'first');tracker.played(1479,'first');
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(events.length,0);
  tracker.confirmed();
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(events.length,1);
  assert.equal(events[0].visitID,tracker.visitID);
  tracker.played(1479,'first');tracker.played(1479,'second');
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(events.length,2);
  assert.notEqual(createParticipationTracker().visitID,tracker.visitID);
});

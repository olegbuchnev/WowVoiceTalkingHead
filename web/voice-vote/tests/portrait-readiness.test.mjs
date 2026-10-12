import {test} from 'node:test';
import assert from 'node:assert/strict';
import {watchPortraitReadiness} from '../src/portrait-readiness.js';

test('slow models remain eligible after 40 seconds and recover even after the soft timeout',t=>{
  t.mock.timers.enable({apis:['Date','setInterval']});
  let ready=false,shown=0,errors=0;
  const stop=watchPortraitReadiness({isReady:()=>ready,onReady:()=>shown++,onError:()=>errors++});
  t.mock.timers.tick(41000);assert.equal(errors,0);assert.equal(shown,0);
  t.mock.timers.tick(80000);assert.equal(errors,1);
  t.mock.timers.tick(10000);assert.equal(errors,1,'timeout is reported only once');
  ready=true;t.mock.timers.tick(200);assert.equal(shown,1);
  t.mock.timers.tick(10000);assert.equal(shown,1,'camera initialization runs once');stop();
});

test('already loaded models take precedence after a long background-tab timer delay',t=>{
  t.mock.timers.enable({apis:['Date','setInterval']});
  let shown=0,errors=0;
  watchPortraitReadiness({isReady:()=>true,onReady:()=>shown++,onError:()=>errors++});
  t.mock.timers.tick(200000);assert.equal(shown,1);assert.equal(errors,0);
});

test('unmounted portraits cancel readiness checks; unsupported viewers stop safely',t=>{
  t.mock.timers.enable({apis:['Date','setInterval']});
  let checks=0,errors=0;
  const stop=watchPortraitReadiness({isReady:()=>{checks++;return false;},onReady:()=>assert.fail(),onError:()=>errors++});
  stop();t.mock.timers.tick(200000);assert.equal(checks,0);assert.equal(errors,0);
  watchPortraitReadiness({isReady:()=>{checks++;throw Error('Unsupported viewer');},onReady:()=>assert.fail(),onError:()=>errors++});
  t.mock.timers.tick(1000);assert.equal(checks,1);assert.equal(errors,1);
});

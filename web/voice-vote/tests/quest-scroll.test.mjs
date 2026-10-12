import test from 'node:test';
import assert from 'node:assert/strict';
import {buildScrollPlan, scrollOffset, speechWeight} from '../src/quest-scroll.js';

function lines(count) {
  const text = Array(count).fill('word').join('\n');
  return buildScrollPlan({text, duration:100, lineHeight:13, visibleLines:7,
    textRange:Math.max(0, count - 7) * 13,
    prefixHeight:end => text.slice(0,end).split('\n').length * 13});
}

test('pages hold still, overlap two lines, ease through short moves, and hold the ending', () => {
  const plan = lines(17);
  assert.equal(plan.length,2);
  assert.deepEqual(plan.map(p=>[p.from,p.to]),[[0,65],[65,130]]);
  assert.equal(scrollOffset(plan,plan[0].start / 2),0);
  const move = plan[0], span = move.finish - move.start;
  assert(Math.abs(span - .65) < 1e-8);
  assert.equal(scrollOffset(plan,move.start + span / 2),32.5);
  const quarter = scrollOffset(plan,move.start + span / 4);
  assert(quarter > 0 && quarter < 65 / 4, 'ease in, not a constant-speed drift');
  assert.equal(scrollOffset(plan,(move.finish + plan[1].start)/2),65);
  assert.equal(scrollOffset(plan,100),130);
  assert.equal(scrollOffset(plan,110),130);
  assert.equal(scrollOffset(plan,0),0,'rewinding returns to the first page');
});

test('a short final shift waits for the same spoken boundary as a full page', () => {
  const plan = lines(9);
  assert.equal(plan[0].to,26);
  assert(plan[0].start > 50,'do not move early merely because only two lines overflow');
  assert.equal(scrollOffset(plan,plan[0].finish + 1),26);
  assert.deepEqual(lines(7),[]);
});

test('speech weights count Cyrillic characters and punctuation pauses', () => {
  assert.equal(speechWeight('привет'),7);
  assert.equal(speechWeight('привет,'),11);
  assert.equal(speechWeight('привет!'),14);
  assert.equal(speechWeight('|cffffffffпривет|r'),7);
});

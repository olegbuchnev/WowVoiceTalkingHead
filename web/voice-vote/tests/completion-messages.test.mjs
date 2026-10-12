import test from 'node:test';
import assert from 'node:assert/strict';
import {completionMessages,createCompletionMessages} from '../src/completion-messages.js';

test('completion messages do not repeat within a cycle or at its boundary',()=>{
  const deck=createCompletionMessages(()=>.5), n=completionMessages.length;
  const messages=Array.from({length:n*3},()=>deck.next());
  for(let i=0;i<messages.length;i+=n) assert.equal(new Set(messages.slice(i,i+n)).size,n);
  for(let i=1;i<messages.length;i++) assert.notEqual(messages[i],messages[i-1]);
});

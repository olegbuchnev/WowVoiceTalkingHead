const assert=require('assert/strict');
const {select,generate}=require('../tools/generate-voice-group-portraits');
const {dataTable}=require('../tools/import-forever-audio');
const database={npcs:{
  1:{race:'human',sex:'male',displayID:11,name:'A'},
  2:{race:'human',sex:'male',displayID:22,name:'B'},
  3:{race:'dragon',sex:'male',displayID:33,name:'C'},
  4:{race:'dragon',sex:'male',displayID:44,name:'D'},
  5:{race:'unknown',sex:'male',name:'No portrait'},
},givers:{1:{npcID:1},2:{npcID:1},3:{npcID:2},4:{npcID:3},5:{npcID:4},6:{npcID:4}}};
const votes=[{npcID:1,race:'human',sex:'male',votes:2},{npcID:2,race:'human',sex:'male',votes:8},
  {npcID:3,race:'skyborne',sex:'male',votes:100},{npcID:0,race:null,sex:null,votes:9}];
const initial=select(database,undefined,votes);
assert.equal(initial.groups['human/male'].npcID,2,'Most evaluated NPC wins over quest coverage');
assert.equal(initial.groups['dragon/male'].npcID,4,'Without eligible votes, use the NPC with most descriptions');
assert(!initial.groups['dragon/female'],'No portrait category without NPCs');
assert.equal(initial.groups['unknown/male'].displayID,null,'Unknown display must not become an invented portrait');
assert.deepEqual(select(database,initial,[{npcID:1,race:'human',sex:'male',votes:900}]),initial,'New votes do not change fixed portraits');
const next=structuredClone(database);
next.npcs[6]={race:'dragon',sex:'female',displayID:66};
const added=select(next,initial);
assert.equal(added.groups['dragon/female'].npcID,6,'New populated category receives a portrait automatically');
assert.deepEqual(added.groups['human/male'],initial.groups['human/male']);
delete next.npcs[2];
assert.equal(select(next,initial).groups['human/male'].npcID,1,'Removed representative is replaced');
next.npcs[2]={race:'elf',sex:'male',displayID:22};
assert.equal(select(next,initial).groups['human/male'].npcID,1,'Reclassified representative cannot leak to old category');
next.npcs[7]={race:'unknown',sex:'male',displayID:77};
assert.equal(select(next,initial).groups['unknown/male'].npcID,7,'Newly available real portrait replaces the missing-display fallback');
const current=generate(dataTable(require('path').join(__dirname,'../src/Speakers.lua')),true);
assert(Object.values(current.groups).every(n=>n.displayID>0),'Every current category has a real portrait');
console.log('PASS: fixed popular NPC portraits, safe fallbacks, no empty groups, automatic additions and reclassification.');

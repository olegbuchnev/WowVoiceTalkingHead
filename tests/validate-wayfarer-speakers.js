const assert = require('assert/strict'), fs = require('fs'), os = require('os'), path = require('path');
const {collect} = require('../tools/import-wayfarer-speakers');
const {literal} = require('../tools/generate-wayfarer-metadata');
const directory = fs.mkdtempSync(path.join(os.tmpdir(),'wowvoice-wayfarer-speakers-'));
function pack(name, data, model='v4') {
  const dir = path.join(directory,name); fs.mkdirSync(dir,{recursive:true});
  fs.writeFileSync(path.join(dir,name+'.toc'),'## Version: 1.0\n');
  fs.writeFileSync(path.join(dir,'Index.lua'),'Wayfarer:RegisterPack('+literal({name,format:1,version:'1.0',model,...data})+')');
}
try {
  pack('Wayfarer_Voices_A', {qg:{1:10,2:20}, npc:{10:{n:'Имя',d:111},20:{n:'Другой NPC'}},
    q:{1:{a:{s:10},p:{s:11},c:{s:11}},2:{a:{s:21}},3:{a:{v:'narrator'},c:{s:30}},4:{p:{s:40},c:{s:41}}}});
  pack('Wayfarer_Voices_B', {qg:{1:10},npc:{10:{n:'Name',d:222},20:{n:'Other',d:333}},q:{}},'v3');
  const r=collect(directory);
  assert.equal(r.givers[1],10);
  assert.equal(r.givers[2],false,'Inconsistent qg/description identity stays ambiguous');
  assert.equal(r.givers[3],undefined,'Narrator must not become the receiver NPC');
  assert.equal(r.finishers[1],11);
  assert.equal(r.finishers[3],30);
  assert.equal(r.finishers[4],false,'Conflicting progress/completion identities must not be guessed');
  assert.deepEqual(r.npcs[10],{displayID:111,name:'Имя'});
  assert.equal(r.npcs[20].displayID,333);
  assert(r.conflicts.some(c=>c.npcID===10));
  assert.match(r.packs.Wayfarer_Voices_A.indexSha256,/^[a-f0-9]{64}$/);
  // No audio files exist in this fixture; NPC import remains independent of playback.
  fs.appendFileSync(path.join(directory,'Wayfarer_Voices_A/Index.lua'),'\nWayfarer:RegisterPack({})');
  assert.throws(()=>collect(directory),/Expected one/);
  pack('Wayfarer_Voices_A',{q:{1:{a:{s:-1}}}});
  assert.throws(()=>collect(directory));
  console.log('PASS: Wayfarer NPC data-only import, separate roles, narration, ambiguity, model/name merge, pack priority and validation');
} finally {
  fs.rmSync(directory,{recursive:true,force:true});
}

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
  assert.equal(r.givers[3],'narrator','Explicit narrator must survive import');
  assert.equal(r.finishers[1],11);
  assert.equal(r.finishers[3],30);
  assert.equal(r.finishers[4],false,'Conflicting progress/completion identities must not be guessed');
  assert.deepEqual(r.npcs[10],{displayID:111,name:'Имя'});
  assert.equal(r.npcs[20].displayID,333);
  assert(r.conflicts.some(c=>c.npcID===10));
  assert.match(r.packs.Wayfarer_Voices_A.indexSha256,/^[a-f0-9]{64}$/);
  pack('Wayfarer_Voices_B',{qg:{5:50},q:{5:{a:{v:'narrator'},c:{s:51}},6:{a:{}}}});
  const narrated=collect(directory);
  assert.equal(narrated.givers[5],'narrator','Description narration overrides generic qg in the same pack');
  assert.equal(narrated.finishers[5],51,'Narration must not erase the completion NPC');
  assert.equal(narrated.givers[6],undefined,'Missing voice and speaker remain unknown');
  pack('Wayfarer_Voices_B',{qg:{7:70,8:80,10:100,12:120},q:{
    7:{a:{v:'child-female',m:'7a.ogg'},c:{s:71,v:'child-male'}},
    8:{a:{v:'child-male'},c:{v:'child-female'}},
    9:{a:{v:'child-female'}},
    10:{a:{s:101,v:'child-female'}},
    11:{a:{s:70,v:'child-female'}},
    12:{a:{v:'child-female'},c:{s:120,v:'human-female'}},
  }});
  const children=collect(directory);
  assert.deepEqual(children.npcs[70],{ageGroup:'child',sex:'female'},'Voice sex is independent of male-player recording');
  assert.deepEqual(children.npcs[71],{ageGroup:'child',sex:'male'},'Receiver keeps its own voice metadata');
  assert.deepEqual(children.npcs[80],{ageGroup:'child',sex:'male'},'Unknown completion speaker cannot overwrite the giver');
  assert.equal(children.npcs[100],undefined);
  assert.equal(children.npcs[101],undefined,'Ambiguous role cannot supply child metadata');
  assert.equal(children.npcs[120],undefined,'Conflicting child/adult voices are not NPC metadata');
  assert.equal(children.npcs.undefined,undefined,'Missing NPC identity must not be invented');
  pack('Wayfarer_Voices_B',{qg:{20:200,21:201},q:{
    20:{a:{v:'ancient-male'},c:{s:202,v:'furbolg-male'}},
    21:{a:{s:211,v:'ancient-male'}},
  }});
  const creatures=collect(directory);
  assert.equal(creatures.npcs[200].voiceRace,'ancient');
  assert.equal(creatures.npcs[202].voiceRace,'furbolg');
  assert.equal(creatures.npcs[211],undefined,'Conflicting speaker identity cannot supply a creature category');
  // No audio files exist in this fixture; NPC import remains independent of playback.
  fs.appendFileSync(path.join(directory,'Wayfarer_Voices_A/Index.lua'),'\nWayfarer:RegisterPack({})');
  assert.throws(()=>collect(directory),/Expected one/);
  pack('Wayfarer_Voices_A',{q:{1:{a:{s:-1}}}});
  assert.throws(()=>collect(directory));
  console.log('PASS: Wayfarer NPC data-only import, separate roles, narration, ambiguity, model/name merge, pack priority and validation');
} finally {
  fs.rmSync(directory,{recursive:true,force:true});
}

const assert = require('assert/strict');
const {merge,generate,POLICY} = require('../tools/generate-speakers');
const inputs = {
  classic:{First:{1:{q:1,i:10,n:'Имя',ei:20,en:'Получатель'}}, Item:{1:{q:2,i:99}},
    Priority:{1:{q:7,i:70,n:'Классическое имя'},2:{q:8,i:80},3:{q:9,i:90}},
    Conflict:{1:{q:4,i:30},2:{q:4,i:40}}},
  pins:{givers:{1:998,2:false,3:30,5:false,7:70,10:false,11:false,12:121}},
  wayfarer:{givers:{1:998,2:99,12:120},finishers:{1:21,12:121},npcs:{10:{displayID:112,name:'Wayfarer English'},
    20:{name:'Имя Wayfarer'},30:{displayID:334},70:{displayID:700,name:'Имя Wayfarer'},120:{name:'Новый NPC'}}},
  cat:{tables:{NpcData:{10:{1:'human',2:'male',3:111,4:'Name'},20:{3:222,4:'Новое имя'},30:{3:333},70:{4:'Новое русское имя'}},
    QuestGiver:{1:999,2:99,4:30,5:30,6:30},QuestFinisher:{1:20}}},
  supplements:{schemaVersion:1,npcs:Object.fromEntries([10,70,90].map(id=>[id,{
    displayID:900,source:`https://www.wowhead.com/forever/npc=${id}`,
    verifiedOn:'2026-10-13',evidence:'Exact NPC display ID on its page',
  }]))}
};
const result = merge(inputs);
const db = result.database;
assert.deepEqual(POLICY.givers,['catquest','wayfarer','pins','classic']);
assert.equal(db.givers[1].npcID,999,'CatQuest wins over Pins and Classic');
assert.equal(db.npcs[10].displayID,111,'Model enriches the same NPC chosen by another source');
assert.equal(db.npcs[10].name,'Имя','Russian name wins even when a higher-priority source only has English');
assert.equal(db.npcs[20].name,'Новое имя','CatQuest Russian name wins over Classic Russian name');
assert.equal(db.givers[7].npcID,70,'Pins wins over Classic');
assert.equal(db.givers[7].name,'Новое русское имя');
assert.equal(db.givers[8].npcID,80,'Classic fills gaps after current Pins');
assert.equal(db.givers[9].npcID,90,'Classic remains the final fallback');
assert.equal(db.givers[10],false,'Ambiguous Pins starter must not turn into an NPC');
assert.equal(db.givers[11],false,'Multiple current Pins starters must not turn into one NPC');
assert.equal(db.givers[12].npcID,120,'Wayfarer wins over Pins');
assert.equal(db.finishers[12].npcID,121,'Wayfarer supplies a distinct receiver');
assert.equal(db.npcs[70].displayID,700,'Wayfarer fills a missing CatQuest model');
assert.equal(db.npcs[30].displayID,333,'CatQuest model wins over Wayfarer');
assert(result.appearanceConflicts.some(c=>c.npcID===30 && c.selected==='catquest'));
assert.equal(db.finishers[1].npcID,20);
assert.equal(db.npcs[20].displayID,222);
assert.equal(db.givers[2],false,'Explicit non-NPC starter blocks all lower sources');
assert.equal(db.givers[3].npcID,30,'Current Pins fills absent detailed data');
assert.equal(db.givers[4],false,'Ambiguous Classic identities must not become a guessed NPC');
assert.equal(db.givers[5],false,'Multiple Pins starters block lower sources');
assert.equal(db.givers[6].npcID,30);
assert(result.conflicts.some(c=>c.questId===1&&c.selected==='catquest'&&c.rejected==='pins'));
assert.equal(result.exclusions[2].reason,'multiple-or-conflicting-starters');
assert.equal(db.npcs[999]?.displayID,undefined,'No appearance transfer across different IDs');
assert.equal(db.npcs[90].displayID,900,'Verified evidence fills a missing exact-NPC appearance');
assert.equal(result.origins.npcs[90].displayID,'verified-supplement');
assert.equal(db.givers[9].npcID,90,'Appearance supplements do not change quest roles');
assert.throws(()=>merge({...inputs,supplements:{schemaVersion:1,npcs:{90:{
  ...inputs.supplements.npcs[90],source:'https://www.wowhead.com/forever/npc=91',
}}}}),/Invalid appearance supplement/,'Reject evidence for another NPC');
const report=generate(true);
const children=merge({...inputs,cat:{tables:{
  NpcData:{101:{1:'orc',2:'male'},102:{1:'child',2:'female'}},
  QuestGiver:{21:100,22:101,23:102,24:103},QuestFinisher:{21:104},
}},catAudio:{entries:{'21a':{voice:'child-female'},'21c':{voice:'child-male'},
  '22a':{voice:'child-male'},'23a':{voice:'child-male'},'24a':{voice:'child-female'},
  '24p':{voice:'child-male'},'25a':{voice:'child-female'}}},
  wayfarer:{givers:{25:105},finishers:{},npcs:{100:{ageGroup:'child',sex:'male'},106:{ageGroup:'child',sex:'female'}}},
}).database;
assert.deepEqual(children.npcs[100],{ageGroup:'child',sex:'female'},'CatQuest child voice wins over Wayfarer fallback');
assert.equal(children.npcs[101].race,'orc','Child voice is not proof of human race');
assert.equal(children.npcs[101].ageGroup,'child','Age is independent of the known orc race');
assert.equal(children.npcs[100].race,undefined,'Unknown race stays unknown for a child voice');
assert.equal(children.npcs[102].sex,'female','Explicit NPC sex wins over voice label');
assert.equal(children.npcs[103].sex,'female','Unknown progress speaker cannot alter the giver');
assert.deepEqual(children.npcs[104],{ageGroup:'child',sex:'male'});
assert.deepEqual(children.npcs[105],{},'No voice transfer to another source\'s NPC');
assert.deepEqual(children.npcs[106],{ageGroup:'child',sex:'female'},'Wayfarer child metadata fills missing facts');
const narrated=merge({...inputs,
  catAudio:{entries:{'7a':{voice:'narrator'},'8c':{voice:'narrator'}}},
  wayfarer:{...inputs.wayfarer,givers:{...inputs.wayfarer.givers,1:'narrator',9:'narrator',12:'narrator'}},
});
assert.deepEqual(narrated.database.givers[7],{narrator:true},'CatQuest narrator blocks Pins/Classic NPCs');
assert.equal(narrated.database.givers[1].npcID,999,'Lower-priority narrator cannot replace a known CatQuest speaker');
assert.deepEqual(narrated.database.givers[9],{narrator:true},'Wayfarer narrator blocks Classic');
assert.deepEqual(narrated.database.givers[12],{narrator:true},'Wayfarer narrator blocks Pins');
assert.equal(narrated.database.finishers[12].npcID,121,'Description narration keeps the receiving NPC');
assert.equal(narrated.database.givers[8].npcID,80,'Completion narration does not change the description speaker');
assert(!('undefined' in narrated.database.npcs));
const {dataTable}=require('../tools/import-forever-audio');
const current=dataTable(require('path').join(__dirname,'../src/Speakers.lua'));
assert.equal(current.givers[940].npcID,3519,'Quest 940 uses Arynia from maintained sources');
assert(current.npcs[3519].displayID>0,'Arynia has a portrait');
assert.equal(current.givers[99260].npcID,253285,'Fillion quest keeps its distinct NPC ID');
assert.equal(current.npcs[253285].displayID,137707,'Fillion portrait is confirmed by its exact Wowhead page');
assert.deepEqual(current.givers[98247],{narrator:true},'Shipping label has a narrator');
assert.equal(current.finishers[98247].npcID,256390,'Marcy remains the shipping label receiver');
assert.equal(current.givers[94007].npcID,254084,'Elayaa is the hunter quest starter');
assert.equal(current.npcs[254084].displayID,137999,'Elayaa portrait is verified by exact NPC ID');
assert(!('forever' in report.sources));
assert(!('forever' in report.inputHashes));
assert(!Object.values(report.origins.givers).includes('forever'));
console.log('PASS: unified NPC models, distinct roles, source conflicts, exclusions, Russian names and reproducible metadata');

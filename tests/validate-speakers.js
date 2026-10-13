const assert = require('assert/strict');
const {merge,generate,POLICY} = require('../tools/generate-speakers');
const {creatureVoiceMetadata} = require('../tools/creature-voice-metadata');
assert.deepEqual(creatureVoiceMetadata([
  {npcID:1,voice:'creature/ancient'},{npcID:1,voice:'ancient-male'},
  {npcID:2,voice:'furbolg-male'},{npcID:2,voice:'furbolg-female'},
  {npcID:3,voice:'ancient-male'},{npcID:3,voice:'furbolg-male'},
  {npcID:4,voice:'ancient-male'},{npcID:4,voice:'skyborne-male'},
  {npcID:0,voice:'furbolg-male'},{voice:'ancient-male'},
  {npcID:5,voice:'creature/banshee'},
]),{1:{voiceRace:'ancient'},2:{voiceRace:'furbolg'},5:{voiceRace:'banshee'}},'Exact creature labels normalize without guessing ambiguous speakers');
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
const classifiedInputs=structuredClone(inputs);
classifiedInputs.cat.tables.NpcData[10]={1:'tauren',2:'female',3:111};
classifiedInputs.cat.tables.NpcData[20]={1:'tauren',2:'male',3:222};
classifiedInputs.raceClassifications={schemaVersion:1,appearances:{111:{race:'furbolg',modelFileID:124118}},
  models:{124118:{race:'furbolg',file:'creature/furbolg/furbolg.m2',source:'https://example.org/listfile'}}};
const classified=merge(classifiedInputs);
assert.equal(classified.database.npcs[10].race,'furbolg','A verified furbolg appearance overrides a tauren voice category');
assert.equal(classified.database.npcs[10].sex,'male','Furbolg voting has a single canonical sex group');
assert.equal(classified.database.npcs[20].race,'tauren','Other tauren remain tauren');
assert.equal(classified.origins.npcs[10].race,'verified-appearance');
classifiedInputs.cat.tables.NpcData[10][3]=333;
assert.equal(merge(classifiedInputs).database.npcs[10].race,'tauren','A changed appearance must not inherit a stale correction');
classifiedInputs.raceClassifications.appearances[111].race='orc';
assert.throws(()=>merge(classifiedInputs),/Invalid NPC race classification/,'Classification must match its model evidence');
const db = result.database;
const creatureInputs=structuredClone(inputs);
creatureInputs.cat.tables.QuestGiver[50]=500;
creatureInputs.cat.tables.QuestFinisher[50]=501;
creatureInputs.cat.tables.NpcData[500]={1:'skyborne',2:'female'};
creatureInputs.cat.tables.QuestGiver[52]=504;
creatureInputs.cat.tables.NpcData[504]={1:'troll',2:'female'};
creatureInputs.catAudio={entries:{'50a':{voice:'creature/ancient'},'50c':{voice:'creature/furbolg'},'51a':{voice:'creature/ancient'}}};
creatureInputs.catAudio.entries['52a']={voice:'creature/banshee'};
creatureInputs.wayfarer.givers[51]=502;
creatureInputs.wayfarer.npcs[500]={voiceRace:'furbolg'};
creatureInputs.wayfarer.npcs[503]={voiceRace:'ancient'};
creatureInputs.wayfarer.npcs[504]={voiceRace:'furbolg'};
const creatures=merge(creatureInputs);
assert.equal(creatures.database.npcs[500].race,'ancient','CatQuest explicit creature label wins over broad NPC and Wayfarer categories');
assert.equal(creatures.database.npcs[500].sex,'male','Ancients do not split by legacy NPC sex');
assert.equal(creatures.database.npcs[501].race,'furbolg','Completion speaker has its own category');
assert.equal(creatures.database.npcs[502].race,undefined,'No voice transfer to another source\'s giver');
assert.equal(creatures.database.npcs[503].race,'ancient','Wayfarer explicit creature category is preserved');
assert.equal(creatures.database.npcs[504].race,'banshee','CatQuest banshee label wins even over a conflicting Wayfarer creature category');
assert.equal(creatures.database.npcs[504].sex,'female','Banshee does not use the unsexed male group');
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
const localizedInputs=structuredClone(inputs);
localizedInputs.cat.tables.NpcData[90]={4:'English name'};
localizedInputs.cat.tables.QuestFinisher[9]=90;
for (const id of [10,70,90]) Object.assign(localizedInputs.supplements.npcs[id],{
  nameRu:'Имя с Wowhead',source:`https://www.wowhead.com/forever/ru/npc=${id}`,
});
const localized=merge(localizedInputs);
assert.equal(localized.database.npcs[90].name,'Имя с Wowhead','Verified Russian name replaces English');
assert.equal(localized.database.givers[9].name,'Имя с Wowhead','Giver receives the localized name');
assert.equal(localized.database.finishers[9].name,'Имя с Wowhead','Finisher receives the localized name');
assert.equal(localized.origins.npcs[90].name,'verified-supplement');
assert.equal(localized.database.npcs[10].name,'Имя','Existing Russian library name keeps priority');
assert.equal(localized.database.npcs[70].name,'Новое русское имя');
assert.equal(localized.database.npcs[10].displayID,111,'Localization cannot override a library appearance');
localizedInputs.supplements.npcs[90].source='https://www.wowhead.com/forever/npc=90';
assert.throws(()=>merge(localizedInputs),/Invalid Russian name supplement/,'Russian name requires the exact localized source');
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
const current=dataTable(require('path').join(__dirname,'../src/Speakers.lua'),'TalkingHeadRuSpeakers');
assert.equal(current.npcs[4606].race,'banshee','A banshee voice category must not become a troll');
assert.equal(current.npcs[4606].sex,'female','Banshee keeps the female speaker metadata');
for (const id of [3897,8405,11554,11555,11556,11557,15395])
  assert(current.npcs[id].race==='furbolg' && current.npcs[id].sex==='male','Known furbolg NPCs have one shared category');
for (const id of [1244,3616,9598,14524,14525,14526,270269])
  assert(current.npcs[id].race==='ancient' && current.npcs[id].sex==='male','Ancients form one category independent of elf and tauren voices');
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

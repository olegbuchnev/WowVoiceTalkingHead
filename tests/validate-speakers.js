const assert = require('assert/strict');
const {merge,generate,POLICY} = require('../tools/generate-speakers');
const result = merge({
  classic:{First:{1:{q:1,i:10,n:'Имя',ei:20,en:'Получатель'}}, Item:{1:{q:2,i:99}},
    Priority:{1:{q:7,i:70,n:'Классическое имя'},2:{q:8,i:80},3:{q:9,i:90}},
    Conflict:{1:{q:4,i:30},2:{q:4,i:40}}},
  forever:{quests:[{questId:1,starters:[{kind:'npc',id:10,name:'Name'}]},
    {questId:2,starters:[{kind:'item',id:100,name:'Item'}]},
    {questId:3,starters:[]}, {questId:7,starters:[{kind:'npc',id:71,name:'Old'}]},
    {questId:8,starters:[{kind:'npc',id:81,name:'Old'}]},
    {questId:10,starters:[{kind:'object',id:100,name:'Object'}]},
    {questId:11,starters:[{kind:'npc',id:10,name:'One'},{kind:'npc',id:20,name:'Two'}]}]},
  pins:{givers:{1:998,2:99,3:30,5:false,7:70,10:10,11:10,12:121}},
  wayfarer:{givers:{1:998,2:99,12:120},finishers:{1:21,12:121},npcs:{10:{displayID:112,name:'Wayfarer English'},
    20:{name:'Имя Wayfarer'},30:{displayID:334},70:{displayID:700,name:'Имя Wayfarer'},120:{name:'Новый NPC'}}},
  cat:{tables:{NpcData:{10:{1:'human',2:'male',3:111,4:'Name'},20:{3:222,4:'Новое имя'},30:{3:333},70:{4:'Новое русское имя'}},
    QuestGiver:{1:999,2:99,4:30,5:30,6:30},QuestFinisher:{1:20}}}
});
const db = result.database;
assert.deepEqual(POLICY.givers,['catquest','wayfarer','pins','forever','classic']);
assert.equal(db.givers[1].npcID,999,'CatQuest wins over Pins, historical Forever and Classic');
assert.equal(db.npcs[10].displayID,111,'Model enriches the same NPC chosen by another source');
assert.equal(db.npcs[10].name,'Имя','Russian name wins even when a higher-priority source only has English');
assert.equal(db.npcs[20].name,'Новое имя','CatQuest Russian name wins over Classic Russian name');
assert.equal(db.givers[7].npcID,70,'Pins wins over old Forever and Classic');
assert.equal(db.givers[7].name,'Новое русское имя');
assert.equal(db.givers[8].npcID,81,'Old Forever fills gaps before Classic');
assert.equal(db.givers[9].npcID,90,'Classic remains the final fallback');
assert.equal(db.givers[10],false,'Explicit object must not turn into an NPC');
assert.equal(db.givers[11],false,'Multiple historical starters must not turn into one NPC');
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
assert.equal(result.exclusions[2].reason,'item');
assert.equal(db.npcs[999]?.displayID,undefined,'No appearance transfer across different IDs');
generate(true);
console.log('PASS: unified NPC models, distinct roles, source conflicts, exclusions, Russian names and reproducible metadata');

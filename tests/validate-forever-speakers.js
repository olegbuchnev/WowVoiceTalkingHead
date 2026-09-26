const assert = require('assert/strict');
const fs = require('fs');
const path = require('path');
const {questRecord,render} = require('../tools/import-forever-speakers');
const base = 'https://github.com/TylerAkins/forever-quest-markers';
function page(markup, points=[], type=5, id=97250) {
  return {questId:id,pageInfo:{type,typeId:id},infoboxMarkup:'[ul][li]'+markup.replaceAll('[/icon][icon','[/icon][/li][li][icon')+'[/li][/ul]',
    mapper:{objectives:{17:{levels:[points]}}}};
}
const npc='[icon name=quest-start]Начало: [url=/forever/ru/npc=5911]Рубака Логмар[/url][/icon]';
const end='[icon name=quest-end]Конец: [url=/forever/ru/npc=999]Получатель[/url][/icon]';
const records = questRecord(page(npc+end,[{type:1,point:'start',id:5911,name:'Рубака Логмар'},
  {type:1,point:'end',id:999,name:'Получатель'}, {type:1,point:'requirement',id:777,name:'Враг'}]),97250);
assert.deepEqual(records.starters,[{kind:'npc',id:5911,name:'Рубака Логмар'}]);
const multiple=questRecord(page(npc,[{type:1,point:'start',id:123,name:'Другой квестодатель'}]),97250);
assert.equal(multiple.starters.length,2);
const item=questRecord(page('[icon name=quest-start]Начало: [url=/forever/ru/item=123]Письмо[/url][/icon]'+end),97250);
assert.equal(item.starters[0].kind,'item');
const object=questRecord(page('[icon name=quest-start]Начало: [url=/forever/ru/object=456]Объявление[/url][/icon]'),97250);
assert.equal(object.starters[0].kind,'object');
assert.deepEqual(questRecord(page(end),97250).starters,[]);
assert.equal(questRecord(page(npc.replace('quest-start','quest-start-daily')),97250).starters[0].id,5911);
assert.deepEqual(questRecord(page('[icon name=quest-start]Start: Object #665289[/icon]'+end),97250).starters,
  [{kind:'object',id:665289,name:'Object #665289'}]);
const collapsed=npc+'[br][span=invisible][icon name=quest-start]Start: [/icon][/span]'
  +'[url=/forever/npc=123/another-npc]Another NPC[/url]';
assert.equal(questRecord(page(collapsed),97250).starters.length,2);
assert.throws(()=>questRecord(page(npc,[],1),97250));
assert.throws(()=>questRecord(page(npc,[],5,179),97250));
assert.throws(()=>questRecord({},97250));
assert.throws(()=>questRecord(page('[icon name=quest-start]Unknown markup[/icon]'),97250));
for(const record of [multiple,item,object]) {
  assert.match(render({source:base,quests:[record]}).lua,/\[97250\] = false/);
}
assert.throws(()=>render({source:base,quests:[records,records]}));
const manifest=JSON.parse(fs.readFileSync(path.join(__dirname,'../docs/internal/forever-speakers-manifest.json'),'utf8'));
const generated=render(manifest);
assert.equal(generated.lua,fs.readFileSync(path.join(__dirname,'../src/ForeverSpeakers.lua'),'utf8'));
const logmar=manifest.quests.find(q=>q.questId===97250);
assert.equal(logmar.starters.length,1);
assert.equal(logmar.starters[0].id,5911);
assert.equal(logmar.starters[0].nameRU,'Рубака Логмар');
assert.equal(manifest.quests.length, new Set(manifest.quests.map(q=>q.questId)).size);
assert(manifest.quests.every(q=>/^[a-f0-9]{64}$/.test(q.sha256)));
assert.equal(manifest.quests.length+manifest.missing.length+manifest.rejected.length,manifest.catalogCount);
console.log('PASS: Forever starter parsing, exact IDs, distinct giver/receiver, ambiguous/item/object handling and reproducible bundled index');

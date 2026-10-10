const assert = require('assert/strict');
const fs = require('fs'), path = require('path'), os = require('os');
const {merge, cueText, importTexts} = require('../tools/import-quest-texts');
const {dataTable} = require('../tools/import-forever-audio');
const merged = merge({
  wowvoice: {'1a':{common:'WowVoice'}, '2a':{male:'Wow male'}},
  catquest: {'1a':{common:'CatQuest'}, '2a':{female:'Cat female'}, '3a':{common:'Cat common'}, '4a':{male:'Cat male'}},
  wayfarer: {'1a':{common:'Wayfarer'}, '2a':{common:'Way common'}, '3a':{male:'Way male',female:'Way female'},
    '4a':{female:'Way female'}, '5p':{common:'Progress'}, '5c':{common:'Completion'}},
});
assert.deepEqual(merged.entries, {'1a':{common:'WowVoice'},'2a':{male:'Wow male',female:'Cat female'},
  '3a':{common:'Cat common'},'4a':{male:'Cat male',female:'Way female'},
  '5c':{common:'Completion'},'5p':{common:'Progress'}});
assert.deepEqual(merged.provenance['4a'], {male:'catquest',female:'wayfarer'});
assert.equal(cueText([[0,'  First  '],[1,'Second']]),'First Second');
assert.equal(cueText([[0,'First'],[1,' ']]),undefined);
assert.equal(cueText({1:{1:0,2:'First'},2:{1:1,2:false}}),undefined);
const fixture = fs.mkdtempSync(path.join(os.tmpdir(),'wowvoice-text-import-'));
try {
  const addons = path.join(fixture,'AddOns'), root = path.join(fixture,'repo');
  const cat = path.join(addons,'CatQuest_Voices'), name = 'Wayfarer_Voices_Horde';
  fs.mkdirSync(cat,{recursive:true}); fs.mkdirSync(path.join(addons,name));
  fs.writeFileSync(path.join(cat,'CatQuest_Voices.toc'),'## Version: 0.5.0\n');
  // No audio files or durations: these texts must still be imported.
  fs.writeFileSync(path.join(cat,'Index.lua'),'CatQuestVoicePack = {quests={}}\nCatQuestVoicePack.quests = {[1]={c={x={{0,"Cat text"}}}},[2]={c={m={{0,"Male Lua"}}}},[4]={c={x={{0,"Valid"},{1,false}}}}}');
  fs.writeFileSync(path.join(cat,'index.json'),JSON.stringify({
    1:{c:{x:[[0,'JSON conflict']]}},2:{c:{m:[[0,'Male JSON']],f:[[0,'Female JSON']]}},
    3:{c:{x:[[0,'JSON-only description']]}},4:{c:{x:[[0,'Complete JSON fallback']]}},
  }));
  const index = path.join(addons,name,'Index.lua');
  fs.writeFileSync(index,`Wayfarer.RegisterPack({name="${name}",format=1,version="3.1.0",model="v4",q={
    [1]={a={t={{0,"Way conflict"}}},p={t={{0,"Progress"}}}},
    [5]={a={tm={{0,[=[Герой "один".]=]}},tf={{0,"Героиня."}}},c={t={{0,"Спасибо."}}}}
  }})`);
  const report = importTexts(addons,root);
  const db = dataTable(path.join(root,'src/QuestTexts.lua'));
  assert.deepEqual(db.entries['1a'],{common:'Cat text'});
  assert.deepEqual(db.entries['2a'],{male:'Male Lua',female:'Female JSON'});
  assert.deepEqual(db.entries['3a'],{common:'JSON-only description'});
  assert.deepEqual(db.entries['4a'],{common:'Complete JSON fallback'});
  assert.deepEqual(db.entries['5a'],{male:'Герой "один".',female:'Героиня.'});
  assert.equal(db.entries['1p'].common,'Progress');
  assert.deepEqual(report.merged.sections,{a:5,p:1,c:1});
  assert.equal(report.sources.wowvoice.quests,0);
  const before = fs.readFileSync(path.join(root,'src/QuestTexts.lua'),'utf8');
  importTexts(addons,root);
  assert.equal(fs.readFileSync(path.join(root,'src/QuestTexts.lua'),'utf8'),before);
  fs.writeFileSync(index,'Wayfarer.RegisterPack(os.execute("never run this"))');
  assert.throws(() => importTexts(addons,root), /Unsupported data expression/);
  assert.equal(fs.readFileSync(path.join(root,'src/QuestTexts.lua'),'utf8'),before);
  console.log('PASS: fixed text priority, stages, common/gender fallback, Lua/JSON union, UTF-8, audio independence, deterministic safe import');
} finally {
  assert.equal(path.dirname(fixture),path.resolve(os.tmpdir()));
  assert(path.basename(fixture).startsWith('wowvoice-text-import-'));
  fs.rmSync(fixture,{recursive:true,force:true});
}

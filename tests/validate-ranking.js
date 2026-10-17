const fs=require('fs'),path=require('path'),crypto=require('crypto'),assert=require('assert');
const {lua,lauxlib,lualib,to_luastring,to_jsstring}=require('fengari');
const root=process.argv[2] || path.resolve(__dirname,'../src');
const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
function code(text,name='ranking-fixtures') {
  let status=lauxlib.luaL_loadbuffer(L,to_luastring(text),null,to_luastring('@'+name));
  if(status===lua.LUA_OK)status=lua.lua_pcall(L,0,0,0);
  if(status!==lua.LUA_OK)throw Error(to_jsstring(lua.lua_tostring(L,-1)));
}
function run(file){code(fs.readFileSync(file,'utf8'),file);}
function string(name,value){lua.lua_pushstring(L,to_luastring(value));lua.lua_setglobal(L,to_luastring(name));}
// WoW exposes bit operations; emulate their signed 32-bit results, independently of the codec.
lua.lua_newtable(L);
for(const [name,operation] of Object.entries({band:(a,b)=>a&b,bxor:(a,b)=>a^b})) {
  lua.lua_pushcfunction(L,state=>{lua.lua_pushinteger(state,operation(lua.lua_tonumber(state,1),lua.lua_tonumber(state,2)));return 1;});
  lua.lua_setfield(L,-2,to_luastring(name));
}
lua.lua_setglobal(L,to_luastring('bit'));
for(const file of ['mock.lua','journal-mock.lua','portrait-mock.lua','local-debug-mock.lua'])run(path.join(__dirname,file));
for(const file of fs.readFileSync(path.join(root,'TalkingHeadRu.toc'),'utf8').split(/\r?\n/).filter(s=>s.endsWith('.lua')))run(path.join(root,file));
run(path.join(__dirname,'catquest-pack-mock.lua'));
// Validate the actual release data before replacing it with scenario fixtures.
code(`
  local record=TalkingHeadRuBuiltinRanking
  assert(type(record)=='table' and type(record.json)=='string','Missing bundled ranking')
  assert(#record.json<=65536,'Bundled ranking exceeds the import limit')
  assert(TalkingHeadRuRankingCodec.SHA256(record.json)==record.sha256,'Bundled ranking checksum mismatch')
  local snapshot=TalkingHeadRuVoiceRanking.Validate(TalkingHeadRuRankingCodec.JSON(record.json))
  assert(#snapshot.groups>0,'Bundled ranking is empty')
  local current,_,origin=TalkingHeadRuVoiceRanking.Current()
  assert(current and origin=='builtin' and current.generatedAt==snapshot.generatedAt,
    'Bundled ranking cannot be selected by the addon')
`,'bundled-ranking-validation');
console.log('PASS: shipped ranking checksum, schema, nonempty groups and addon loading.');
code('savedSnapshotDate=date');
for(const zone of ['UTC','Europe/Bucharest','America/New_York','Asia/Kathmandu']) {
  for(const timestamp of ['1970-01-01T00:00:00Z','2000-02-29T23:45:12Z','2026-03-29T00:59:59Z',
    '2026-03-29T01:00:00Z','2026-10-17T07:52:13.593570647Z','2026-10-25T00:59:59Z',
    '2026-10-25T01:00:00Z','2026-12-31T23:30:00Z','2040-01-01T00:00:00Z','2100-03-01T00:00:00Z']) {
    const epoch=Math.floor(Date.parse(timestamp)/1000);
    const expected=new Date(epoch*1000).toLocaleString('ru-RU',{timeZone:zone});
    lua.lua_pushcfunction(L,state=>{
      assert.equal(to_jsstring(lua.lua_tostring(state,1)),'%d.%m.%Y, %H:%M:%S');
      assert.equal(lua.lua_tonumber(state,2),epoch,'UTC conversion must not depend on the local timezone');
      lua.lua_pushstring(state,to_luastring(expected));return 1;
    });
    lua.lua_setglobal(L,to_luastring('date'));
    string('snapshotTimestamp',timestamp);string('snapshotExpected',expected);
    code('assert(TalkingHeadRuVoiceRanking.FormatSnapshotTime(snapshotTimestamp)==snapshotExpected,"Local snapshot time differs from website")');
  }
}
code('date=savedSnapshotDate');
for(const text of ['', 'abc','a'.repeat(64),'a'.repeat(65536)]) {
  string('hashInput',text);string('hashExpected',crypto.createHash('sha256').update(text).digest('hex'));
  code('assert(TalkingHeadRuRankingCodec.SHA256(hashInput)==hashExpected,"SHA256 vector mismatch")');
}
// The codec captures bit at load time, so reload to exercise the arithmetic fallback.
code('savedBit=bit; savedCodec=TalkingHeadRuRankingCodec; bit=nil');run(path.join(root,'RankingCodec.lua'));
code('assert(TalkingHeadRuRankingCodec.SHA256("abc")=="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"); bit=savedBit; TalkingHeadRuRankingCodec=savedCodec');
const sample=(date='2026-10-18T10:00:00Z')=>({schemaVersion:1,generatedAt:date,groups:[{
  speakerType:'npc',race:'dwarf',sex:'male',status:'ranked',ranking:[
    {rank:1,source:'CatQuest',basis:'votes',tieGroup:null},
    {rank:2,source:'WowVoice',basis:'votes',tieGroup:2},
    {rank:3,source:'Wayfarer',basis:'votes',tieGroup:2}]}]});
const encode=raw=>'THR1:'+Buffer.from(raw).toString('base64url')+'.'+crypto.createHash('sha256').update(raw).digest('hex');
const fixtures={builtin:sample('2026-10-17T10:00:00Z'),valid:sample(),older:sample('2026-10-16T10:00:00Z'),newer:sample('2026-10-19T10:00:00Z'),noTie:sample(),noData:sample(),partial:sample(),unknownRace:sample(),narrator:sample(),allTied:sample(),legacy:sample()};
fixtures.allTied.groups[0].ranking.forEach(p=>p.tieGroup=1);
fixtures.legacy.groups[0].ranking.forEach(p=>delete p.tieGroup);
fixtures.noTie.groups[0].ranking.forEach(p=>p.tieGroup=null);
fixtures.noData.groups[0].status='no_data';fixtures.noData.groups[0].ranking=['WowVoice','CatQuest','Wayfarer'].map((source,i)=>({rank:i+1,source,basis:'fallback',tieGroup:null}));
fixtures.partial.groups[0].status='partial';fixtures.partial.groups[0].ranking[0].tieGroup=1;fixtures.partial.groups[0].ranking[1].tieGroup=1;fixtures.partial.groups[0].ranking[2].tieGroup=null;fixtures.partial.groups[0].ranking[2].basis='fallback';
fixtures.unknownRace.groups[0].race='future_race';
fixtures.narrator.groups[0].speakerType='narrator';fixtures.narrator.groups[0].race=null;fixtures.narrator.groups[0].sex=null;
for(const [name,value] of Object.entries(fixtures))string('rankingFixture_'+name,encode(JSON.stringify(value)));
// Relative-age scenarios must not depend on the release snapshot's date or votes.
// This changes only the in-memory Lua global, never src/BuiltinRanking.lua.
code('TalkingHeadRuBuiltinRanking=assert(TalkingHeadRuVoiceRanking.Prepare(rankingFixture_builtin))');
run(path.join(__dirname,'ranking-scenarios.lua'));
run(path.join(__dirname,'voice-group-scenarios.lua'));
const invalid=[];
function invalidMutation(change){const s=sample();change(s);invalid.push(JSON.stringify(s));}
invalidMutation(s=>s.schemaVersion=2);
invalidMutation(s=>s.groups.push(s.groups[0]));
invalidMutation(s=>s.groups[0].ranking[1].source='CatQuest');
invalidMutation(s=>s.groups[0].ranking[2].rank=2);
invalidMutation(s=>s.groups[0].ranking[2].tieGroup=null);
invalidMutation(s=>s.groups[0].ranking[1].tieGroup='2');
invalidMutation(s=>s.groups[0].ranking[0].tieGroup=2);
invalidMutation(s=>s.groups[0].ranking[2].basis='fallback');
invalidMutation(s=>s.groups[0].sex='unknown');
invalidMutation(s=>s.groups[0].race='|Hbad|h');
invalidMutation(s=>s.generatedAt='2026-02-30T10:00:00Z');
invalidMutation(s=>s.groups={});
invalidMutation(s=>s.groups[0].ranking={});
invalidMutation(s=>s.groups[0].extra=true);
invalid.push(JSON.stringify(sample()).replace('"schemaVersion":1','"schemaVersion":1,"schemaVersion":1'));
invalid.push(JSON.stringify(sample()).replace('"schemaVersion":1','"schemaVersion":01'));
invalid.push(JSON.stringify(sample())+' trailing');
invalid.push(JSON.stringify(sample()).replace('"rank":1','"rank":1e999'));
invalid.push('['.repeat(20)+'0'+']'.repeat(20));
invalid.push('return os.execute("echo unexpected")');
for(const raw of invalid){string('badRanking',encode(raw));code('local before=TalkingHeadRuDB.voiceRanking; assert(not TalkingHeadRuVoiceRanking.Import(badRanking)); assert(TalkingHeadRuDB.voiceRanking==before,"Invalid import replaced data")');}
for(const raw of ['THR2:aaa.'+'0'.repeat(64),'THR1:abc.'+'0'.repeat(64),encode(JSON.stringify(sample())).slice(0,-2),'x'.repeat(87517)]){
  string('badRanking',raw);code('assert(not TalkingHeadRuVoiceRanking.Import(badRanking))');
}
const large=sample();large.groups=Array.from({length:180},(_,i)=>({...sample().groups[0],race:`race_${i}`}));
code("assert(TalkingHeadRuVoiceRanking.SetOverride('npc:dwarf:male',{'wayfarer','catquest','wowvoice'}))");
assert(Buffer.byteLength(JSON.stringify(large))<65536);
string('largeRanking',encode(JSON.stringify(large)));code('assert(TalkingHeadRuVoiceRanking.Import(largeRanking)); assert(#TalkingHeadRuVoiceRanking.Current().groups==180)');
run(path.join(root,'VoiceRanking.lua'));
code('assert(#TalkingHeadRuVoiceRanking.Current().groups==180,"Saved import lost after module reload")');
code("assert(table.concat(TalkingHeadRuVoiceRanking.Override('npc:dwarf:male'),',')=='wayfarer,catquest,wowvoice','Import/reload erased private order')");
console.log('PASS: THR1/SHA256, bounded atomic imports, newest snapshot, ties, private orders/resets/reload, speaker selection, sample bags, availability, UI drag/navigation and preview ownership.');

// Verify installed files and the Lua resolver against the measured snapshot.
const fs=require('fs'),path=require('path'),crypto=require('crypto'),assert=require('assert/strict');
const {lua,lauxlib,lualib,to_luastring,to_jsstring}=require('fengari');
const {readPack,literal}=require('./generate-wayfarer-metadata');
const root=path.resolve(__dirname,'..'),source=process.argv[2];
if(!source) throw Error('Usage: node tools/check-wayfarer-compatibility.js <AddOns directory>');
const manifest=JSON.parse(fs.readFileSync(path.join(root,'docs/internal/wayfarer-audio-manifest.json'),'utf8'));
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const state=lauxlib.luaL_newstate(); lualib.luaL_openlibs(state);
function run(code) {
  let status=lauxlib.luaL_loadbuffer(state,to_luastring(code),null,to_luastring('wayfarer-audit'));
  if(status===lua.LUA_OK) status=lua.lua_pcall(state,0,0,0);
  if(status!==lua.LUA_OK) throw Error(to_jsstring(lua.lua_tostring(state,-1)));
}
let files=0,checks=0;
try {
  for(const file of ['WayfarerAudio.lua','WayfarerSource.lua','AudioSources.lua']) run(fs.readFileSync(path.join(root,'src',file),'utf8'));
  for(const [name,expected] of Object.entries(manifest.packs)) {
    const dir=path.join(source,name),index=fs.readFileSync(path.join(dir,'Index.lua'));
    assert.equal(hash(index),expected.indexSha256,`${name}: changed index; regenerate metadata`);
    assert.equal(hash(fs.readFileSync(path.join(dir,name+'.toc'))),expected.tocSha256,`${name}: changed TOC`);
    for(const [file,record] of Object.entries(expected.files)) {
      const bytes=fs.readFileSync(path.join(dir,file));
      assert.equal(bytes.length,record.bytes,`${name}/${file}: changed size`);
      assert.equal(hash(bytes),record.sha256,`${name}/${file}: changed audio`);
      files++;
    }
    const pack=readPack(index);
    // Timing verification does not require sending large subtitle tables to Lua.
    for(const quest of Object.values(pack.q)) for(const [section,entry] of Object.entries(quest)) {
      quest[section]=Object.fromEntries(['d','m','f','v','s'].filter(k=>entry[k]!=null).map(k=>[k,entry[k]]));
      checks+=2;
    }
    const data=Object.fromEntries(['name','version','format','model','q'].map(k=>[k,pack[k]]));
    run(`local pack=${literal(data)}
      Wayfarer={Packs={list={pack}}}
      C_AddOns={IsAddOnLoaded=function() return true,true end,
        GetAddOnMetadata=function() return pack.version end}
      for id,quest in pairs(pack.q) do for section,entry in pairs(quest) do
        for _,sex in ipairs({2,3}) do
          UnitSex=function() return sex end
          local record=WowVoiceAudioSources.Resolve(id,section,'wayfarer')
          assert(record and record.verified,pack.name..':'..id..section..': unverified')
          local audio=WowVoiceWayfarerAudio.packs[pack.name].entries[id..section].audio[record.variant]
          assert(record.duration==audio.duration)
          assert(record.path=='Interface\\\\AddOns\\\\'..pack.name..'\\\\'..audio.file:gsub('/','\\\\'))
        end
      end end`);
  }
  console.log(JSON.stringify({filesVerified:files,resolverChecks:checks,mainDescriptions:manifest.mainDescriptions}));
} finally {lua.lua_close(state);}

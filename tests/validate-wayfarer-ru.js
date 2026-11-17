const fs=require('fs'),path=require('path');
const {lua,lauxlib,lualib,to_luastring,to_jsstring}=require('fengari');
const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
function run(s){if(lauxlib.luaL_dostring(L,to_luastring(s))!==lua.LUA_OK)throw Error(to_jsstring(lua.lua_tostring(L,-1)));}
try{
run(`WowVoice={}; TalkingHeadRuDB={enabled=true};
local loaded={WayfarerRU=true,Wayfarer=true,Wayfarer_Voices_Alliance=true}
C_AddOns={IsAddOnLoaded=function(n)return loaded[n] end,GetAddOnMetadata=function(n)if n=='WayfarerRU' then return '1.2.1' elseif n=='Wayfarer_Voices_Alliance' then return '3.3.0' end end}
function unrelatedPrint() error('unrelated addon called') end
Wayfarer={Util={Print=unrelatedPrint},db={zoneMode='always',questButtons=true}}
function ruPrint() end
WayfarerRU={Packs={list={{name='Wayfarer_Voices_Alliance',version='3.3.0',format=1,q={[5]={a={d=2}}}}}},Util={Print=ruPrint},db={zoneMode='always',questButtons=true,playBarks=true}}
`);
for(const f of ['WayfarerSource.lua','AudioSources.lua','LibraryIntegration.lua','WayfarerIntegration.lua'])run(fs.readFileSync(path.join(__dirname,'../src',f),'utf8'));
run(`assert(WowVoiceWayfarerSource.CoreAddon()=='WayfarerRU');assert(WowVoiceWayfarerSource.Resolve(5,'a'))
for _, change in ipairs(WowVoiceWayfarerSource.VersionChanges()) do assert(change.addon~='WayfarerRU') end
WowVoice:UpdateWayfarerIntegration()
assert(WayfarerRU.db.zoneMode=='never' and WayfarerRU.db.questButtons==false)
assert(WayfarerRU.db.playBarks==false)
assert(WayfarerRU.Util.Print~=ruPrint)
assert(Wayfarer.db.zoneMode=='always' and Wayfarer.db.questButtons==true and Wayfarer.Util.Print==unrelatedPrint)
WowVoice:UpdateWayfarerIntegration(true)
assert(WayfarerRU.db.zoneMode=='always' and WayfarerRU.db.questButtons==true and WayfarerRU.Util.Print==ruPrint)
assert(WayfarerRU.db.playBarks==true)
WayfarerRU=nil
WowVoice:UpdateWayfarerIntegration()
assert(not WowVoiceWayfarerSource.Status())
assert(Wayfarer.db.zoneMode=='always' and Wayfarer.db.questButtons==true and Wayfarer.Util.Print==unrelatedPrint)
`);console.log('PASS: WayfarerRU resolution, reversible suppression and isolation from unrelated Wayfarer');
}finally{lua.lua_close(L);}

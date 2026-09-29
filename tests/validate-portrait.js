const fs=require('fs'),path=require('path');
const {lua,lauxlib,lualib,to_luastring,to_jsstring}=require('fengari');
const root=process.argv[2], L=lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
function run(file) {
    let s=lauxlib.luaL_loadbuffer(L,to_luastring(fs.readFileSync(file,'utf8')),null,to_luastring('@'+file));
    if(s===lua.LUA_OK) s=lua.lua_pcall(L,0,0,0);
    if(s!==lua.LUA_OK) throw Error(to_jsstring(lua.lua_tostring(L,-1)));
}
function load() {
    for(const file of ['mock.lua','journal-mock.lua','portrait-mock.lua']) run(path.join(__dirname,file));
    for(const file of ['License.lua','Index.lua','Durations.lua','CatQuestAudio.lua','CatQuestTexts.lua','AudioSources.lua','Core.lua','Work.lua','CameraModels.lua','CameraProfiles.lua','UI.lua','Portrait.lua']) run(path.join(root,file));
}
load(); run(path.join(__dirname,'portrait-scenarios.lua'));
load(); run(path.join(__dirname,'portrait-reload.lua'));
load(); run(path.join(__dirname,'portrait-recovery-scenarios.lua'));
load(); run(path.join(__dirname,'portrait-recovery-reload.lua'));
load(); run(path.join(__dirname,'portrait-warmup-scenarios.lua'));
load(); run(path.join(__dirname,'camera-profile-scenarios.lua'));

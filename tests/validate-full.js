const fs=require('fs'),path=require('path');
const {lua,lauxlib,lualib,to_luastring,to_jsstring}=require('fengari');
const root=process.argv[2];
for (const scenario of ['scenarios.lua','journal-scenarios.lua','tracker-scenarios.lua','tracker-progress-scenarios.lua','unavailable-audio-scenarios.lua','background-audio-scenarios.lua','retail-head-scenarios.lua','forever-audio-scenarios.lua','head-transition-scenarios.lua','head-visibility-scenarios.lua','accept-autoplay-scenarios.lua','turnin-autoplay-scenarios.lua','portrait-position-scenarios.lua']) {
    const L=lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
    function run(file) {
        let s=lauxlib.luaL_loadbuffer(L,to_luastring(fs.readFileSync(file,'utf8')),null,to_luastring('@'+file));
        if(s===lua.LUA_OK) s=lua.lua_pcall(L,0,0,0);
        if(s!==lua.LUA_OK) throw Error(to_jsstring(lua.lua_tostring(L,-1)));
    }
    for (const file of ['mock.lua','journal-mock.lua','portrait-mock.lua']) run(path.join(__dirname,file));
    const toc=fs.readFileSync(path.join(root,'WowVoiceTalkingHead.toc'),'utf8');
    for (const file of toc.split(/\r?\n/).filter(s=>s.endsWith('.lua'))) run(path.join(root,file));
    run(path.join(__dirname,scenario));
    lua.lua_close(L);
}

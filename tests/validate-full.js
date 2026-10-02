const fs=require('fs'),path=require('path');
const {lua,lauxlib,lualib,to_luastring,to_jsstring}=require('fengari');
const root=process.argv[2];
const scenarios = ['catquest-speakers-scenarios.lua','audio-sources-scenarios.lua','questie-tracker-scenarios.lua','catquest-scenarios.lua','work-scenarios.lua','startup-work-scenarios.lua','scenarios.lua','journal-scenarios.lua','tracker-scenarios.lua','tracker-progress-scenarios.lua','quest-reminder-preview-scenarios.lua','unavailable-audio-scenarios.lua','background-audio-scenarios.lua','retail-head-scenarios.lua','forever-audio-scenarios.lua','gossip-quest-speaker-scenarios.lua','head-transition-scenarios.lua','head-visibility-scenarios.lua','accept-autoplay-scenarios.lua','turnin-autoplay-scenarios.lua','portrait-position-scenarios.lua'];
scenarios.push('disabled-sounds-scenarios.lua');
scenarios.push('silent-playback-scenarios.lua');
scenarios.push('release-commands-scenarios.lua', 'dev-commands-scenarios.lua');
scenarios.push('catquest-update-lab-scenarios.lua');
for (const locale of ['enUS', 'enGB']) {
    scenarios.push({file:'catquest-scenarios.lua',locale});
}
for (const mode of ['old-login','old-late','current','newer','double-digit','unknown','missing','absent']) {
    scenarios.push({file:'catquest-version-warning-scenarios.lua',mode});
}
for (const entry of scenarios) {
    const scenario = typeof entry === 'string' ? entry : entry.file;
    const L=lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
    function run(file) {
        let s=lauxlib.luaL_loadbuffer(L,to_luastring(fs.readFileSync(file,'utf8')),null,to_luastring('@'+file));
        if(s===lua.LUA_OK) s=lua.lua_pcall(L,0,0,0);
        if(s!==lua.LUA_OK) throw Error(to_jsstring(lua.lua_tostring(L,-1)));
    }
    for (const file of ['mock.lua','journal-mock.lua','portrait-mock.lua']) run(path.join(__dirname,file));
    if (entry.locale) {
        const status = lauxlib.luaL_dostring(L, to_luastring(`function GetLocale() return '${entry.locale}' end`));
        if (status !== lua.LUA_OK) throw Error(to_jsstring(lua.lua_tostring(L,-1)));
    }
    if (scenario === 'retail-head-scenarios.lua') run(path.join(__dirname, 'queue-lab-mock.lua'));
    const toc=fs.readFileSync(path.join(root,'WowVoiceTalkingHead.toc'),'utf8');
    for (const file of toc.split(/\r?\n/).filter(s=>s.endsWith('.lua'))) run(path.join(root,file));
    run(path.join(__dirname, "catquest-pack-mock.lua"));
    if (['scenarios.lua', 'catquest-scenarios.lua', 'work-scenarios.lua', 'quest-reminder-preview-scenarios.lua', 'dev-commands-scenarios.lua'].includes(scenario)) {
        run(path.resolve(root, '..', 'dev/queue-lab/Commands.lua'));
    }
    if (scenario === 'catquest-update-lab-scenarios.lua') {
        run(path.resolve(root, '..', 'dev', 'catquest-update-lab', 'Lab.lua'));
    }
    if (entry.mode) {
        lua.lua_pushstring(L, to_luastring(entry.mode));
        lua.lua_setglobal(L, to_luastring('catquestWarningTestMode'));
    }
    run(path.join(__dirname,scenario));
    if (scenario === 'audio-sources-scenarios.lua') run(path.join(__dirname, 'catquest-update-scenarios.lua'));
    lua.lua_close(L);
}

const fs = require('fs'), path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const source = process.argv[2];
for (const mode of ['loaded', 'disabled', 'absent', 'legacy', 'cvar', 'early-login']) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  function run(file) {
    let status = lauxlib.luaL_loadbuffer(L, to_luastring(fs.readFileSync(file, 'utf8')), null, to_luastring('@' + file));
    if (status === lua.LUA_OK) status = lua.lua_pcall(L, 0, 0, 0);
    if (status !== lua.LUA_OK) throw Error(to_jsstring(lua.lua_tostring(L, -1)));
  }
  for (const file of ['mock.lua', 'journal-mock.lua', 'portrait-mock.lua']) run(path.join(__dirname, file));
  lua.lua_pushstring(L, to_luastring(mode));
  lua.lua_setglobal(L, to_luastring('upstreamTestMode'));
  run(path.join(__dirname, 'wowvoice-integration-setup.lua'));
  for (const file of fs.readFileSync(path.join(source, 'WowVoiceTalkingHead.toc'), 'utf8')
    .split(/\r?\n/).filter(line => line.endsWith('.lua'))) run(path.join(source, file));
  run(path.join(__dirname, 'wowvoice-integration-scenarios.lua'));
  lua.lua_close(L);
}

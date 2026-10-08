const fs = require('fs'), path = require('path');
const {lua, lauxlib, lualib, to_luastring, to_jsstring} = require('fengari');
const root = process.argv[2], L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
function run(file) {
  let status = lauxlib.luaL_loadbuffer(L, to_luastring(fs.readFileSync(file, 'utf8')), null, to_luastring('@' + file));
  if (status === lua.LUA_OK) status = lua.lua_pcall(L, 0, 0, 0);
  if (status !== lua.LUA_OK) throw Error(to_jsstring(lua.lua_tostring(L, -1)));
}
for (const file of ['mock.lua', 'journal-mock.lua', 'portrait-mock.lua', 'local-debug-mock.lua']) run(path.join(__dirname, file));
for (const file of fs.readFileSync(path.join(root, 'TalkingHeadRu.toc'), 'utf8').split(/\r?\n/).filter(s => s.endsWith('.lua'))) run(path.join(root, file));
run(path.join(__dirname, 'catquest-pack-mock.lua'));
run(path.join(__dirname, 'local-debug-release-scenarios.lua'));
run(path.join(__dirname, 'local-debug-scenarios.lua'));
run(path.join(__dirname, 'local-debug-suggestions-scenarios.lua'));
run(path.join(__dirname, 'local-debug-comparison-scenarios.lua'));

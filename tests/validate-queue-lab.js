const fs = require('fs');
const path = require('path');
const luaparse = require('luaparse');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const root = path.resolve(__dirname, '..');
const source = process.argv[2] || path.join(root, 'src');
const lab = path.join(root, 'dev/queue-lab');
let L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
function run(file) {
  const code = fs.readFileSync(file, 'utf8');
  luaparse.parse(code, { luaVersion: '5.1' });
  let status = lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring('@' + file));
  if (status === lua.LUA_OK) status = lua.lua_pcall(L, 0, 0, 0);
  if (status !== lua.LUA_OK) throw Error(to_jsstring(lua.lua_tostring(L, -1)));
}
for (const file of ['mock.lua', 'journal-mock.lua', 'portrait-mock.lua', 'queue-lab-mock.lua']) run(path.join(__dirname, file));
for (const file of fs.readFileSync(path.join(source, 'TalkingHeadRu.toc'), 'utf8').split(/\r?\n/).filter(s => s.endsWith('.lua'))) {
  if (/QueueLab/i.test(file)) throw Error('Development module in release TOC');
  run(path.join(source, file));
}
for (const file of fs.readdirSync(source).filter(name => name.endsWith('.toc'))) {
  if (!fs.readFileSync(path.join(source, file), 'utf8').includes('## SavedVariablesPerCharacter: TalkingHeadRuQueueDB')) {
    throw Error('Queue persistence missing from ' + file);
  }
}
run(path.join(__dirname, 'queue-session-scenarios.lua'));
for (const file of ['State.lua', 'Runtime.lua', 'Window.lua', 'Commands.lua']) run(path.join(lab, file));
run(path.join(__dirname, 'queue-lab-scenarios.lua'));
run(path.join(__dirname, 'queue-settings-scenarios.lua'));
run(path.join(__dirname, 'queue-auto-preview-scenarios.lua'));

// Fresh Lua states exercise login event order, both transports and silent mode.
for (const testCase of ['sound', 'music', 'silent', 'disabled-first', 'paused', 'legacy',
  'stale-sound', 'stale-music', 'stale-silent']) {
  L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  lua.lua_pushstring(L, to_luastring(testCase));
  lua.lua_setglobal(L, to_luastring('restoreTestCase'));
  for (const file of ['mock.lua', 'journal-mock.lua', 'portrait-mock.lua', 'queue-lab-mock.lua']) run(path.join(__dirname, file));
  run(path.join(__dirname, 'queue-loading-setup.lua'));
  for (const file of fs.readFileSync(path.join(source, 'TalkingHeadRu.toc'), 'utf8').split(/\r?\n/).filter(s => s.endsWith('.lua'))) {
    run(path.join(source, file));
  }
  run(path.join(__dirname, 'queue-loading-scenarios.lua'));
  lua.lua_close(L);
}

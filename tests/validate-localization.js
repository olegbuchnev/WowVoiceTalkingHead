const fs = require('fs'), path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const root = path.resolve(__dirname, '..');
for (const locale of ['enUS', 'enGB', 'ruRU']) {
  const state = lauxlib.luaL_newstate(); lualib.luaL_openlibs(state);
  function code(text, label) {
    const status = lauxlib.luaL_dostring(state, to_luastring(text));
    if (status !== lua.LUA_OK) throw Error(`${locale} ${label}: ${to_jsstring(lua.lua_tostring(state, -1))}`);
  }
  function run(file) { code(fs.readFileSync(path.join(root, file), 'utf8'), file); }
  for (const name of ['mock.lua', 'journal-mock.lua', 'portrait-mock.lua', 'queue-lab-mock.lua']) run('tests/' + name);
  code(`function GetLocale() return '${locale}' end
    local russian = GetLocale() == 'ruRU'
    mockFontFiles = setmetatable({
      QuestTitleFont = russian and 'Fonts\\\\MORPHEUS_CYR.TTF' or 'Fonts\\\\MORPHEUS.ttf',
    }, { __index = function() return russian and 'Fonts\\\\FRIZQT___CYR.TTF' or 'Fonts\\\\FRIZQT__.TTF' end })
  `, 'locale');
  for (const file of fs.readFileSync(path.join(root, 'src/TalkingHeadRu.toc'), 'utf8')
    .split(/\r?\n/).filter(line => line.endsWith('.lua'))) run('src/' + file);
  run('tests/catquest-pack-mock.lua');
  run('tests/localization-scenarios.lua');
  run('tests/options-tooltip-localization-scenarios.lua');
  run('tests/quest-text-locale-scenarios.lua');
  run('tests/reminder-localization-scenarios.lua');
  run('tests/startup-links-scenarios.lua');
  lua.lua_close(state);
}

const fs = require('fs'), path = require('path');
const {lua, lauxlib, lualib, to_luastring, to_jsstring} = require('fengari');
const source = process.argv[2] || path.join(__dirname, '../src');
for (const mode of ['early', 'late', 'disabled', 'read']) {
  const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
  function run(code) {
    if (lauxlib.luaL_dostring(L, to_luastring(code)) !== lua.LUA_OK)
      throw Error(mode + ': ' + to_jsstring(lua.lua_tostring(L, -1)));
  }
  try {
    run(`
      WowVoice={};TalkingHeadRuDB={enabled=${mode !== 'disabled'}}
      CatQuestDB={newsSeen={old='1'},welcomeSeen='old'};shown=0
      ${mode === 'read' ? "CatQuestDB.newsSeen.current='2'" : ''}
      function makeCore()
        return {
          NewsMarkSeen=function() CatQuestDB.newsSeen.current='2' end,
          ShowNews=function() shown=shown+1 end,
          ShowWelcome=function() shown=shown+1 end,
          ShowWelcomeOnce=function(version)
            CatQuestDB.welcomeSeen=version;CatQuestCore.ShowWelcome()
          end,
          NewsCheck=function()
            if CatQuestDB.newsSeen.current=='2' then return false end
            CatQuestCore.ShowNews();return true
          end,
        }
      end
      ${mode === 'late' ? '' : 'CatQuestCore=makeCore()'}
      -- Hiding an already open news window calls the real OnHide entry point.
      CatQuestNewsFrame={Hide=function() CatQuestCore.NewsMarkSeen() end}
    `);
    run(fs.readFileSync(path.join(source, 'LibraryIntegration.lua'), 'utf8'));
    if (mode === 'late') run('CatQuestCore=makeCore();WowVoice:UpdateCatQuestPlayback(true)');
    if (mode === 'disabled') {
      run("assert(CatQuestCore.NewsCheck());assert(shown==1);CatQuestCore.NewsMarkSeen();assert(CatQuestDB.newsSeen.current=='2')");
    } else {
      run(`
        -- Startup's first-run branch marks news seen before offering Welcome.
        CatQuestCore.NewsMarkSeen();CatQuestCore.ShowWelcomeOnce('new')
        -- Update branch and delayed post-combat callbacks use these entry points.
        assert(not CatQuestCore.NewsCheck());CatQuestCore.ShowNews()
        WowVoice:UpdateCatQuestPlayback(true)
        assert(shown==0 and CatQuestDB.welcomeSeen=='old')
        assert(CatQuestDB.newsSeen.old=='1')
        assert(CatQuestDB.newsSeen.current==${mode === 'read' ? "'2'" : 'nil'})
        WowVoice:UpdateCatQuestPlayback(false)
        assert(CatQuestCore.NewsCheck()==${mode !== 'read'})
        CatQuestCore.ShowWelcomeOnce('new');assert(CatQuestDB.welcomeSeen=='new')
        CatQuestCore.NewsMarkSeen();assert(CatQuestDB.newsSeen.current=='2')
      `);
    }
  } finally { lua.lua_close(L); }
}
console.log('PASS: CatQuest popup suppression preserves unread news and welcome version, including OnHide; standalone functions restored');

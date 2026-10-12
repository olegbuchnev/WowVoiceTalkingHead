const fs = require('fs'), path = require('path');
const {lua,lauxlib,lualib,to_luastring,to_jsstring} = require('fengari');
const source = process.argv[2] || path.join(__dirname,'../src');
for (const mode of ['early','late','disabled','no-chat-removal']) {
  const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
  function run(code) {
    const status = lauxlib.luaL_dostring(L,to_luastring(code));
    if (status !== lua.LUA_OK) throw Error(`${mode}: ${to_jsstring(lua.lua_tostring(L,-1))}`);
  }
  run(`
    WowVoice = {}
    calls = 0
    function originalPrint(...) calls = calls+1 end
    globalPrint = print
    ${mode === 'late' ? '' : 'Wayfarer = {Util={Print=originalPrint}}'}
    TalkingHeadRuDB = {enabled=${mode !== 'disabled'}}
    DEFAULT_CHAT_FRAME = {}
    removed = 0
    ${mode === 'no-chat-removal' ? '' : `
      function DEFAULT_CHAT_FRAME:RemoveMessagesByPredicate(predicate)
        assert(predicate('|cffd4af37Wayfarer:|r old startup notice'))
        assert(predicate('Wayfarer: pack error'))
        assert(not predicate('Player: Wayfarer: quoted text'))
        assert(not predicate('TalkingHead Ru: message'))
        assert(not predicate(nil))
        removed = removed+1
      end
    `}
  `);
  run(fs.readFileSync(path.join(source,'LibraryIntegration.lua'),'utf8'));
  run(fs.readFileSync(path.join(source,'WayfarerIntegration.lua'),'utf8'));
  if (mode === 'late') run(`
    WowVoice:UpdateWayfarerIntegration()
    Wayfarer = {Util={}}
    WowVoice:UpdateWayfarerIntegration()
    Wayfarer.Util.Print = originalPrint
    WowVoice:UpdateWayfarerIntegration()
  `);
  run(`
    -- All notification text/format arguments are ignored, even before DB init.
    Wayfarer.Util.Print('missing narrator: %s', 'Narrator')
    Wayfarer.Util.Print('пакет %s: формат %s — пропущен', 'TestPack', 2)
    Wayfarer.Util.Print('звук не запускается (%s)', 'missing.ogg')
    Wayfarer.Util.Print('future notification without a known prefix')
    assert(calls == ${mode === 'disabled' ? 4 : 0} and print == globalPrint)
    local wrapper = Wayfarer.Util.Print
    for i=1,3 do WowVoice:UpdateWayfarerIntegration() end
    assert(Wayfarer.Util.Print == wrapper, 'refresh must not stack wrappers')
    assert(removed == ${mode === 'no-chat-removal' || mode === 'disabled' ? 0 : 1})
    TalkingHeadRuDB = {enabled=false}
    WowVoice:UpdateWayfarerIntegration(true)
    assert(Wayfarer.Util.Print == originalPrint, 'disabled integration restores notifications')
    Wayfarer.Util.Print('Restored')
    assert(calls == ${mode === 'disabled' ? 5 : 1})
    TalkingHeadRuDB.enabled = true
    -- Reinitialized upstream APIs are suppressed again on integration refresh.
    Wayfarer.Util = {Print=originalPrint}
    WowVoice:UpdateWayfarerIntegration()
    Wayfarer.Util.Print('Reinitialized')
    assert(calls == ${mode === 'disabled' ? 5 : 1})
  `);
  lua.lua_close(L);
}
// Wayfarer 0.7's questButtons contract covers rows, details and both trackers.
for (const initial of ['true', 'false', 'nil']) {
  const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
  function run(code) {
    const status = lauxlib.luaL_dostring(L,to_luastring(code));
    if (status !== lua.LUA_OK) throw Error(`buttons/${initial}: ${to_jsstring(lua.lua_tostring(L,-1))}`);
  }
  run(`
    WowVoice = {}
    TalkingHeadRuDB = {enabled=false}
    hookCount = 0
    function hooksecurefunc(object, method, callback)
      hookCount = hookCount+1
      local original = object[method]
      object[method] = function(...) original(...); callback(...) end
    end
    Wayfarer = {db={questButtons=${initial}, playBooks=true, gossipMode='once'}, QuestLog={}}
    local log = Wayfarer.QuestLog
    function log:Refresh()
      local enabled = Wayfarer.db.questButtons ~= false
      self.rowQuestID = enabled and 179 or nil
      self.detailsShown = enabled
      self.trackerShown = enabled
      self.campaignShown = enabled
    end
    function log:HoverRow() self.rowShown = self.rowQuestID ~= nil end
    log:Refresh()
    function assertHidden()
      log:HoverRow()
      assert(not log.rowShown and not log.detailsShown and not log.trackerShown and not log.campaignShown)
      assert(not Wayfarer.db.playBooks and Wayfarer.db.gossipMode == 'never')
    end
  `);
  run(fs.readFileSync(path.join(source,'LibraryIntegration.lua'),'utf8'));
  run(fs.readFileSync(path.join(source,'WayfarerIntegration.lua'),'utf8'));
  run(`
    WowVoice:UpdateWayfarerIntegration()
    assert(Wayfarer.db.questButtons == ${initial}, 'disabled player preserves original setting')
    TalkingHeadRuDB.enabled = true
    WowVoice:UpdateWayfarerIntegration()
    assertHidden()
    for i=1,3 do
      WowVoice:UpdateWayfarerIntegration()
      Wayfarer.QuestLog:Refresh()
      assertHidden()
    end
    assert(hookCount == 1, 'refresh must not stack hooks')
    TalkingHeadRuDB.enabled = false
    WowVoice:UpdateWayfarerIntegration()
    assert(Wayfarer.db.questButtons == ${initial}, 'restore true, false and absent values exactly')
    assert(Wayfarer.QuestLog.detailsShown == (${initial} ~= false))
    TalkingHeadRuDB.enabled = true
    WowVoice:UpdateWayfarerIntegration()
    assertHidden()
    WowVoice:UpdateWayfarerIntegration(true)
    assert(Wayfarer.db.questButtons == ${initial}, 'logout restores saved preference despite enabled player')
    WowVoice:UpdateWayfarerIntegration()
    -- A user enables the upstream buttons while our player owns quests.
    Wayfarer.db.questButtons = true
    Wayfarer.QuestLog:Refresh()
    assertHidden()
    WowVoice:UpdateWayfarerIntegration(true)
    assert(Wayfarer.db.questButtons == true, 'preserve the upstream preference on release')
    -- Reinitialization and late DB/QuestLog creation must not lose the override.
    WowVoice:UpdateWayfarerIntegration()
    local oldDB = Wayfarer.db
    Wayfarer.db = nil
    -- The old UI is gone too, as it would be for a replaced namespace.
    local oldLog = Wayfarer.QuestLog
    oldLog.Refresh = nil
    Wayfarer.QuestLog = nil
    WowVoice:UpdateWayfarerIntegration()
    assert(oldDB.questButtons == true)
    Wayfarer.db = {questButtons=true, playBooks=true, gossipMode='once'}
    WowVoice:UpdateWayfarerIntegration()
    assert(Wayfarer.db.questButtons == false)
    local fresh = {Refresh=function(self) self.shown = Wayfarer.db.questButtons ~= false end}
    Wayfarer.QuestLog = fresh
    WowVoice:UpdateWayfarerIntegration()
    assert(fresh.shown == false)
    WowVoice:UpdateWayfarerIntegration(true)
    assert(fresh.shown and Wayfarer.db.questButtons)
  `);
  lua.lua_close(L);
}
for (const late of [false,true]) {
  const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
  function run(code) {
    const status = lauxlib.luaL_dostring(L,to_luastring(code));
    if (status !== lua.LUA_OK) throw Error(`zone-lore/${late}: ${to_jsstring(lua.lua_tostring(L,-1))}`);
  }
  run(`
    WowVoice = {}
    TalkingHeadRuDB = {enabled=true}
    Wayfarer = {db={zoneMode='once',zoneSubzones=true},charDB={zones={}},Books={}}
    calls = 0
    sound, options = {}, {}
    function originalPlay(self, audio, key, force, opts)
      assert(self == Wayfarer.Zones and audio == sound and key == '85')
      assert(opts == options)
      calls = calls+1
      Wayfarer.charDB.zones[key] = true
      return 'manual', opts
    end
    ${late ? '' : 'Wayfarer.Zones = {Play=originalPlay}'}
  `);
  run(fs.readFileSync(path.join(source,'LibraryIntegration.lua'),'utf8'));
  run(fs.readFileSync(path.join(source,'WayfarerIntegration.lua'),'utf8'));
  if (late) run(`Wayfarer.Zones = {Play=originalPlay}; WowVoice:UpdateWayfarerIntegration()`);
  run(`
    local zones = Wayfarer.Zones
    local wrapped = zones.Play
    -- Model the login timer and zone-change/pending checks via their live method.
    local delayed = function() return zones:Play(sound, '85', nil, options) end
    assert(delayed() == false)
    assert(zones:Play(sound, '85', false, options) == false)
    assert(calls == 0 and next(Wayfarer.charDB.zones) == nil)
    for i=1,3 do WowVoice:UpdateWayfarerIntegration() end
    assert(zones.Play == wrapped, 'zone guards must not stack')
    local result, returned = zones:Play(sound, '85', true, options)
    assert(result == 'manual' and returned == options and calls == 1)
    assert(Wayfarer.db.zoneMode == 'never' and Wayfarer.db.zoneSubzones)
    TalkingHeadRuDB.enabled = true
    WowVoice:UpdateWayfarerIntegration(true)
    assert(zones.Play == originalPlay and Wayfarer.db.zoneMode == 'once', 'release restores automatic lore')
    assert(delayed() == 'manual' and calls == 2)
    calls = 1
    zones.Play = originalPlay
    WowVoice:UpdateWayfarerIntegration()
    assert(zones:Play(sound, '85', nil, options) == false)
    Wayfarer.Zones = {Play=originalPlay}
    WowVoice:UpdateWayfarerIntegration()
    assert(Wayfarer.Zones:Play(sound, '85', nil, options) == false)
    assert(Wayfarer.Zones:Play(sound, '85', true, options) == 'manual')
    assert(calls == 2)
    -- A user re-enables zone lore, after our initial suppression.
    Wayfarer.db.zoneMode = 'always'
    WowVoice:UpdateWayfarerIntegration()
    assert(Wayfarer.db.zoneMode == 'always')
    assert(Wayfarer.Zones:Play(sound, '85', nil, options) == 'manual')
    WowVoice:UpdateWayfarerIntegration(true)
    WowVoice:UpdateWayfarerIntegration()
    assert(Wayfarer.db.zoneMode == 'always')
    assert(Wayfarer.Zones:Play(sound, '85', nil, options) == 'manual')
  `);
  lua.lua_close(L);
}
console.log('PASS: Wayfarer notifications, automatic zone lore and quest buttons suppressed; manual lore, reversible settings, late loading and idempotence');

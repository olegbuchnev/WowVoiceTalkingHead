const fs = require('fs'), path = require('path');
const {lua, lauxlib, lualib, to_luastring, to_jsstring} = require('fengari');
for (const mode of ['absent', 'disabled', 'loaded', 'late', 'early-login', 'legacy-api',
  'ignored-early', 'reenabled', 'disable-failed', 'unknown-player', 'already-disabled', 'legacy-state-api']) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  function code(text) {
    let status = lauxlib.luaL_loadbuffer(L, to_luastring(text), null, to_luastring(mode));
    if (status === lua.LUA_OK) status = lua.lua_pcall(L, 0, 0, 0);
    if (status !== lua.LUA_OK) throw Error(to_jsstring(lua.lua_tostring(L, -1)));
  }
  code(fs.readFileSync(path.join(__dirname, 'mock.lua'), 'utf8'));
  code(`
mode = '${mode}'
local create = CreateFrame
function CreateFrame(...)
    local frame = create(...)
    function frame:UnregisterAllEvents() self.events = {} end
    return frame
end
disabled, saved, shown, reloaded = 0, 0, 0, 0
enable = mode == 'already-disabled' and 0 or 2
chatMessages = 0
DEFAULT_CHAT_FRAME.AddMessage = function() chatMessages = chatMessages + 1 end
ready = mode ~= 'early-login'
oldLoaded = mode ~= 'absent' and mode ~= 'disabled' and mode ~= 'late' and mode ~= 'already-disabled'
UNKNOWNOBJECT = 'Unknown'
function UnitName()
    if mode == 'unknown-player' and not loggedIn then return UNKNOWNOBJECT end
    if ready then return 'Player' end
end
C_AddOns.DoesAddOnExist = function(name) assert(name == 'WowVoiceTalkingHead'); return mode ~= 'absent' end
C_AddOns.DisableAddOn = function(name, character)
    assert(name == 'WowVoiceTalkingHead' and character == 'Player', 'only disable the old addon for this character')
    disabled = disabled + 1
    if mode ~= 'disable-failed' and not (mode == 'ignored-early' and not loggedIn) then enable = 0 end
end
C_AddOns.GetAddOnEnableState = function(name, character)
    assert(name == 'WowVoiceTalkingHead' and character == 'Player')
    return enable
end
C_AddOns.SaveAddOns = function() saved = saved + 1 end
C_AddOns.IsAddOnLoaded = function(name) assert(name == 'WowVoiceTalkingHead'); return oldLoaded end
function StaticPopup_Show(name) assert(name == 'TALKINGHEADRU_LEGACY_RELOAD'); shown = shown + 1 end
function ReloadUI() reloaded = reloaded + 1 end
if mode == 'legacy-api' or mode == 'legacy-state-api' then
    GetAddOnInfo = function(name) assert(name == 'WowVoiceTalkingHead'); return name end
    DisableAddOn, IsAddOnLoaded = C_AddOns.DisableAddOn, C_AddOns.IsAddOnLoaded
    C_AddOns = nil
    if mode == 'legacy-state-api' then
        function GetAddOnEnableState(character, name)
            assert(character == 'Player' and name == 'WowVoiceTalkingHead', 'legacy state API argument order')
            return enable
        end
    end
else
    C_UI = {Reload = ReloadUI}
    ReloadUI = function() error('prefer modern Reload API') end
end
`);
  code(fs.readFileSync(path.join(process.argv[2], 'LegacyAddonBlocker.lua'), 'utf8'));
  code(`
assert(shown == 0 and reloaded == 0, 'never force a reload during loading')
if mode == 'absent' then
    assert(disabled == 0 and saved == 0 and frames.TalkingHeadRuLegacyBlocker == nil)
else
    assert(disabled == (ready and mode ~= 'unknown-player' and mode ~= 'already-disabled' and 1 or 0))
    ready = true
    loggedIn = true
    if mode == 'reenabled' then enable = 2 end
    local frame = frames.TalkingHeadRuLegacyBlocker
    local callback = frame.scripts.OnEvent
    callback(frame, 'PLAYER_LOGIN')
    local attempts = (mode == 'ignored-early' or mode == 'reenabled' or mode == 'disable-failed') and 2
        or mode == 'already-disabled' and 0 or 1
    assert(disabled == attempts and saved == ((mode == 'legacy-api' or mode == 'legacy-state-api') and 0 or attempts))
    if mode == 'late' then
        assert(shown == 0)
        callback(frame, 'ADDON_LOADED', 'UnrelatedAddon')
        assert(shown == 0)
        oldLoaded = true
        callback(frame, 'ADDON_LOADED', 'WowVoiceTalkingHead')
    end
    if mode == 'disable-failed' then
        assert(shown == 0 and reloaded == 0 and enable == 2, 'never claim success or suggest a reload loop after failed disable')
        assert(chatMessages == 1 and frame.scripts.OnEvent, 'report failure once and allow later retry')
        callback(frame, 'ADDON_LOADED', 'UnrelatedAddon')
        assert(chatMessages == 1 and shown == 0, 'do not spam the failure warning')
    elseif mode == 'disabled' or mode == 'already-disabled' then
        assert(shown == 0, 'disabled old folder needs no reload prompt')
    else
        assert(shown == 1 and reloaded == 0)
        callback(frame, 'PLAYER_LOGIN')
        assert(shown == 1 and disabled == attempts, 'notification and disable are idempotent')
        assert(next(frame.events) == nil and not frame.scripts.OnEvent)
        StaticPopupDialogs.TALKINGHEADRU_LEGACY_RELOAD.OnAccept()
        assert(reloaded == 1)
    end
end
print('PASS: old addon blocker: ' .. mode)
`);
  if (!['absent','disable-failed','legacy-api'].includes(mode)) {
    code('oldLoaded=false; shown=0');
    code(fs.readFileSync(path.join(process.argv[2], 'LegacyAddonBlocker.lua'), 'utf8'));
    code(`
      local frame=frames.TalkingHeadRuLegacyBlocker
      frame.scripts.OnEvent(frame,'PLAYER_LOGIN')
      assert(enable==0 and shown==0,
        'A reload with the old addon disabled must not repeat the migration prompt')
    `);
  }
  lua.lua_close(L);
}

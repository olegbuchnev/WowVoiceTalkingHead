const fs = require('fs'), path = require('path');
const {lua, lauxlib, lualib, to_luastring, to_jsstring} = require('fengari');
for (const mode of ['absent', 'disabled', 'loaded', 'late', 'early-login', 'legacy-api']) {
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
ready = mode ~= 'early-login'
oldLoaded = mode == 'loaded' or mode == 'early-login' or mode == 'legacy-api'
function UnitName() if ready then return 'Player' end end
C_AddOns.DoesAddOnExist = function(name) assert(name == 'WowVoiceTalkingHead'); return mode ~= 'absent' end
C_AddOns.DisableAddOn = function(name, character)
    assert(name == 'WowVoiceTalkingHead' and character == 'Player', 'only disable the old addon for this character')
    disabled = disabled + 1
end
C_AddOns.SaveAddOns = function() saved = saved + 1 end
C_AddOns.IsAddOnLoaded = function(name) assert(name == 'WowVoiceTalkingHead'); return oldLoaded end
function StaticPopup_Show(name) assert(name == 'TALKINGHEADRU_LEGACY_RELOAD'); shown = shown + 1 end
function ReloadUI() reloaded = reloaded + 1 end
if mode == 'legacy-api' then
    GetAddOnInfo = function(name) assert(name == 'WowVoiceTalkingHead'); return name end
    DisableAddOn, IsAddOnLoaded = C_AddOns.DisableAddOn, C_AddOns.IsAddOnLoaded
    C_AddOns = nil
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
    assert(disabled == (ready and 1 or 0))
    ready = true
    local frame = frames.TalkingHeadRuLegacyBlocker
    local callback = frame.scripts.OnEvent
    callback(frame, 'PLAYER_LOGIN')
    assert(disabled == 1 and saved == (mode == 'legacy-api' and 0 or 1))
    if mode == 'late' then
        assert(shown == 0)
        callback(frame, 'ADDON_LOADED', 'UnrelatedAddon')
        assert(shown == 0)
        oldLoaded = true
        callback(frame, 'ADDON_LOADED', 'WowVoiceTalkingHead')
    end
    if mode == 'disabled' then
        assert(shown == 0, 'disabled old folder needs no reload prompt')
    else
        assert(shown == 1 and reloaded == 0)
        callback(frame, 'PLAYER_LOGIN')
        assert(shown == 1 and disabled == 1, 'notification and disable are idempotent')
        assert(next(frame.events) == nil and not frame.scripts.OnEvent)
        StaticPopupDialogs.TALKINGHEADRU_LEGACY_RELOAD.OnAccept()
        assert(reloaded == 1)
    end
end
print('PASS: old addon blocker: ' .. mode)
`);
  lua.lua_close(L);
}

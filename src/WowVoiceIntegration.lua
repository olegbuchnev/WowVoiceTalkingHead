-- OptionalDeps loads an enabled upstream WowVoice before this file. Run before
-- our index and Core replace its globals: disabling an addon only affects the
-- next UI load, so its existing event handlers must also be detached now.
local addon = "WowVoice"
local api = C_AddOns or {}
local exists = api.DoesAddOnExist
local info = api.GetAddOnInfo or GetAddOnInfo
if not (exists and exists(addon) or not exists and info and info(addon)) then return end

local disable = api.DisableAddOn or DisableAddOn
local function disableForCharacter()
    local character = UnitName("player")
    if not character then return false end
    disable(addon, character)
    if api.SaveAddOns then api.SaveAddOns() end
    return true
end
if disable and not disableForCharacter() then
    -- The player name can be unavailable early in the initial login.
    local login = CreateFrame("Frame", "WowVoiceDisableUpstream")
    login:RegisterEvent("PLAYER_LOGIN")
    login:SetScript("OnEvent", function(self)
        if disableForCharacter() then
            self:UnregisterAllEvents()
            self:SetScript("OnEvent", nil)
        end
    end)
end

local upstream = _G.WowVoice
if not upstream or upstream.displayName == "TalkingHead Ru"
    or upstream.displayName == "WowVoice TalkingHead" then return end

-- Upstream already printed these during its ADDON_LOADED, before our files
-- could run. Remove only its startup notices; keep errors and other chat.
local chat = DEFAULT_CHAT_FRAME
if chat and chat.RemoveMessagesByPredicate then
    chat:RemoveMessagesByPredicate(function(text)
        if type(text) ~= "string" then return false end
        text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        return text:match("^WowVoice: загружен%. Квестов в индексе: %d+%. Команды: /wv$") ~= nil
            or text == "WowVoice: Понравился WowVoice? Угости разработчика пивом на Boosty — набери /wv boosty"
    end)
end

-- At startup upstream has not received PLAYER_LOGIN or quest events yet.
-- Silence also restores audio settings if it was started before our load.
-- Avoid its deferred CVar restore, since we are retiring its timer below.
local stopmode = WowVoiceDB and WowVoiceDB.stopmode
if stopmode == "cvar" then WowVoiceDB.stopmode = "stopmusic" end
if upstream.Silence then upstream:Silence() end
if stopmode == "cvar" then WowVoiceDB.stopmode = stopmode end

local frame = _G.WowVoiceFrame
if frame then
    frame:UnregisterAllEvents()
    frame:SetScript("OnEvent", nil)
end
local ticker = _G.WowVoiceTicker
if ticker then
    ticker:SetScript("OnUpdate", nil)
    ticker:Hide()
end
local button = _G.WowVoiceStopButton
if button then
    button:SetScript("OnClick", nil)
    button:Hide()
end

-- Do not leave commands that can restart upstream or change our shared DB.
SlashCmdList.WOWVOICE = nil
SLASH_WOWVOICE1, SLASH_WOWVOICE2 = nil, nil

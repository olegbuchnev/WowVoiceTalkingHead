-- Disabling an addon takes effect on the next UI load. Do not force-load the
-- old player or try to unload its frames/hooks; offer a reload if it is running.
local legacy = "WowVoiceTalkingHead"
local api = C_AddOns or {}
local exists = api.DoesAddOnExist
local info = api.GetAddOnInfo or GetAddOnInfo
if not (exists and exists(legacy) or not exists and info and info(legacy)) then return end

local disable = api.DisableAddOn or DisableAddOn
if not disable then return end
local loaded = api.IsAddOnLoaded or IsAddOnLoaded
local disabled, loginReady, notified = false, false, false
local function disableLegacy()
    local character = UnitName("player")
    if disabled or not character then return end
    disable(legacy, character)
    if api.SaveAddOns then api.SaveAddOns() end
    disabled = true
end

local function notifyReload()
    if not disabled or not loginReady or notified then return end
    notified = true
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffTalkingHead Ru|r: старый WowVoiceTalkingHead отключён. Выполните /reload, чтобы завершить переключение.")
    StaticPopupDialogs.TALKINGHEADRU_LEGACY_RELOAD = {
        text = "TalkingHead Ru отключил старый WowVoiceTalkingHead.\n\nПерезагрузите интерфейс, чтобы завершить переключение на новую версию.",
        button1 = "Перезагрузить интерфейс",
        button2 = "Позже",
        OnAccept = function()
            if C_UI and C_UI.Reload then C_UI.Reload() else ReloadUI() end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("TALKINGHEADRU_LEGACY_RELOAD")
end

disableLegacy()
local legacyLoaded = loaded and loaded(legacy)
local events = CreateFrame("Frame", "TalkingHeadRuLegacyBlocker")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == legacy then legacyLoaded = true end
    if event == "PLAYER_LOGIN" then loginReady = true end
    disableLegacy()
    if legacyLoaded or loaded and loaded(legacy) then notifyReload() end
    if notified then
        self:UnregisterAllEvents()
        self:SetScript("OnEvent", nil)
    end
end)

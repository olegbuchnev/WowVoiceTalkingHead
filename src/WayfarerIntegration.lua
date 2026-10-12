-- Take over automatic quest events and journal/tracker play buttons.
-- Restore upstream behavior when TalkingHead Ru is disabled or logging out.
local WV = WowVoice
local zoneGuard
local function suppressAutomaticZoneLore(active)
    local zones = type(_G.Wayfarer) == "table" and Wayfarer.Zones
    if zoneGuard and (not active or zoneGuard.zones ~= zones) then
        if zoneGuard.zones.Play == zoneGuard.wrapper then zoneGuard.zones.Play = zoneGuard.original end
        zoneGuard = nil
    end
    if not active or type(zones) ~= "table" or type(zones.Play) ~= "function" then return end
    if zoneGuard and zoneGuard.wrapper == zones.Play then return end
    local original = zones.Play
    local function guarded(self, sound, key, force, ...)
        -- Login, zone changes and delayed checks pass no force flag. Manual
        -- /wf zone and map/minimap controls pass true and remain available.
        if not force and not WV:IsLibraryPreferenceCustomized("WAYFARER_", "zoneMode") then return false end
        return original(self, sound, key, force, ...)
    end
    zoneGuard = {zones=zones, original=original, wrapper=guarded}
    zones.Play = guarded
end
local function silentPrint() end
local printGuard
local function suppressNotifications(active)
    local util = type(_G.Wayfarer) == "table" and Wayfarer.Util
    if printGuard and (not active or printGuard.util ~= util) then
        if printGuard.util.Print == silentPrint then printGuard.util.Print = printGuard.original end
        printGuard = nil
    end
    if not active then return end
    if type(util) ~= "table" or type(util.Print) ~= "function" or util.Print == silentPrint then return end
    -- Wayfarer's notification/debug helpers all route through Util.Print.
    -- Do not intercept global print or mutate the external addon files/settings.
    printGuard = {util=util, original=util.Print}
    util.Print = silentPrint
    -- Optional dependencies can emit messages while registering their packs,
    -- before our files run. Remove those already printed by Wayfarer as well.
    local chat = DEFAULT_CHAT_FRAME
    if chat and chat.RemoveMessagesByPredicate then
        chat:RemoveMessagesByPredicate(function(text)
            if type(text) ~= "string" then return false end
            if issecretvalue and issecretvalue(text) then return false end
            text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            return text:match("^Wayfarer:") ~= nil
        end)
    end
end
-- OptionalDeps loads Wayfarer first. Silence notifications before PLAYER_LOGIN
-- and before our saved settings initialize; an explicitly disabled player opts out.
local initiallyActive = not TalkingHeadRuDB or TalkingHeadRuDB.enabled ~= false
suppressNotifications(initiallyActive)
-- Install before PLAYER_ENTERING_WORLD and its delayed narration callback.
suppressAutomaticZoneLore(initiallyActive)
local buttonOverride, buttonsActive
local buttonHooks = {}
local function refreshButtons(log)
    if log and type(log.Refresh) == "function" then log:Refresh() end
end
local function updateButtons(active)
    buttonsActive = active == true
    local wayfarer = type(_G.Wayfarer) == "table" and Wayfarer
    local db = wayfarer and wayfarer.db
    local log = wayfarer and wayfarer.QuestLog
    if buttonOverride and (not active or buttonOverride.db ~= db or buttonOverride.log ~= log) then
        local previous = buttonOverride
        buttonOverride = nil
        if previous.db.questButtons == false then previous.db.questButtons = previous.value end
        -- A hooked Refresh must not reapply the override during restoration.
        buttonsActive = false
        refreshButtons(previous.log)
        buttonsActive = active == true
    end
    if not active or type(db) ~= "table" then return end
    if log and type(log.Refresh) == "function" and hooksecurefunc and not buttonHooks[log] then
        buttonHooks[log] = true
        hooksecurefunc(log, "Refresh", function()
            -- Wayfarer's settings call Refresh after changing questButtons.
            -- Enforce ownership again, including newly created journal rows.
            if buttonsActive then updateButtons(true) end
        end)
    end
    local changed = not buttonOverride or db.questButtons ~= false
    if not buttonOverride then buttonOverride = {db=db, log=log, value=db.questButtons} end
    if db.questButtons ~= false then buttonOverride.value = db.questButtons end
    db.questButtons = false
    if changed then refreshButtons(log) end
end
local override
local events = {"QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE"}
local preferences = {playAccept=false, playProgress=false, playComplete=false,
    playBooks=false, gossipMode="never", zoneMode="never"}
function WV:UpdateWayfarerIntegration(release)
    local enabled = not release and TalkingHeadRuDB and TalkingHeadRuDB.enabled == true
    suppressNotifications(enabled)
    suppressAutomaticZoneLore(enabled)
    local db = type(_G.Wayfarer) == "table" and Wayfarer.db
    self:UpdateLibraryPreferences("WAYFARER_", db, preferences, enabled, nil, {zoneMode=true})
    updateButtons(enabled)
    local core = type(_G.Wayfarer) == "table" and Wayfarer.Core
    local active = not release and TalkingHeadRuDB and TalkingHeadRuDB.enabled
        and core and core.IsEventRegistered and core.UnregisterEvent and core.RegisterEvent
    if override and (not active or override.core ~= core) then
        for event in pairs(override.events) do override.core:RegisterEvent(event) end
        override = nil
    end
    if not active then return end
    override = override or {core=core, events={}}
    for _, event in ipairs(events) do
        if core:IsEventRegistered(event) then
            override.events[event] = true
            core:UnregisterEvent(event)
        end
    end
end

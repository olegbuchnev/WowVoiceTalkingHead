-- Take over automatic quest events and journal/tracker play buttons.
-- Restore upstream behavior when TalkingHead Ru is disabled or logging out.
local WV = WowVoice
local function namespace()
    if WowVoiceWayfarerSource then return WowVoiceWayfarerSource.Namespace() end
    return type(_G.WayfarerRU) == "table" and _G.WayfarerRU or _G.Wayfarer
end
local offerGuards = {}
local function suppressOffers(active)
    local ns = namespace()
    for _, entry in ipairs({{"QuestZones", "Offer"}, {"Zones", "OfferKnown"}}) do
        local component, method = entry[1], entry[2]
        local owner = type(ns) == "table" and ns[component]
        local guard = offerGuards[component]
        if guard and (not active or guard.owner ~= owner) then
            if guard.owner[method] == guard.wrapper then guard.owner[method] = guard.original end
            offerGuards[component], guard = nil, nil
        end
        if active and type(owner) == "table" and type(owner[method]) == "function"
            and (not guard or owner[method] ~= guard.wrapper) then
            -- Block before qzAsked/knownAsked, post-combat retries or history
            -- changes. Standalone Wayfarer can still offer both choices later.
            local wrapper = function() end
            offerGuards[component] = {owner=owner, original=owner[method], wrapper=wrapper}
            owner[method] = wrapper
        end
    end
end
local radioGuard
local function suppressAutomaticRadio(active)
    local ns = namespace()
    local radio = type(ns) == "table" and ns.Radio
    if radioGuard and (not active or radioGuard.radio ~= radio) then
        if radioGuard.radio.Start == radioGuard.wrapper then radioGuard.radio.Start = radioGuard.original end
        radioGuard = nil
    end
    if not active or type(radio) ~= "table" or type(radio.Start) ~= "function" then return end
    if not radioGuard or radioGuard.wrapper ~= radio.Start then
        local original = radio.Start
        local function guarded(self, kind, opts, ...)
            -- Tick marks both taxi chronicles and running radio as automatic.
            -- Reject before Start creates a session, queues audio or shows UI.
            if type(opts) == "table" and opts.auto then return false end
            return original(self, kind, opts, ...)
        end
        radioGuard = {radio=radio, original=original, wrapper=guarded}
        radio.Start = guarded
    end
    -- Also silence an automatic session already running when we take over.
    -- Stop only removes radio entries, leaving the upstream quest queue intact.
    if type(radio.session) == "table" and radio.session.auto and type(radio.Stop) == "function" then
        radio:Stop(true)
    end
end
local zoneGuard
local function suppressAutomaticZoneLore(active)
    local zones = type(namespace()) == "table" and namespace().Zones
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
    local util = type(namespace()) == "table" and namespace().Util
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
suppressOffers(initiallyActive)
-- Install before PLAYER_ENTERING_WORLD and its delayed narration callback.
suppressAutomaticZoneLore(initiallyActive)
suppressAutomaticRadio(initiallyActive)
local buttonOverride, buttonsActive
local buttonHooks = {}
local function refreshButtons(log)
    if log and type(log.Refresh) == "function" then log:Refresh() end
end
local function updateButtons(active)
    buttonsActive = active == true
    local wayfarer = namespace()
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
local events = {"QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_ACCEPTED"}
local preferences = {playAccept=false, playProgress=false, playComplete=false,
    playBooks=false, playBarks=false, gossipMode="never", zoneMode="never"}
function WV:UpdateWayfarerIntegration(release)
    local enabled = not release and TalkingHeadRuDB and TalkingHeadRuDB.enabled == true
    suppressNotifications(enabled)
    suppressOffers(enabled)
    suppressAutomaticZoneLore(enabled)
    suppressAutomaticRadio(enabled)
    local db = type(namespace()) == "table" and namespace().db
    self:UpdateLibraryPreferences("WAYFARER_", db, preferences, enabled, nil, {zoneMode=true})
    updateButtons(enabled)
    local core = type(namespace()) == "table" and namespace().Core
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

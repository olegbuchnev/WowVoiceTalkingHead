-- Take over automatic quest events and journal/tracker play buttons.
-- Preserve gossip/lore/books, registered packs and saved preferences on release.
local WV = WowVoice
local function silentPrint() end
local function suppressNotifications()
    local util = type(_G.Wayfarer) == "table" and Wayfarer.Util
    if type(util) ~= "table" or type(util.Print) ~= "function" or util.Print == silentPrint then return end
    -- Wayfarer's notification/debug helpers all route through Util.Print.
    -- Do not intercept global print or mutate the external addon files/settings.
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
-- and before our saved settings initialize. This follows addon loading, not
-- the user's quest-playback toggle. /reload without TalkingHeadRu restores it.
suppressNotifications()
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
function WV:UpdateWayfarerIntegration(release)
    suppressNotifications()
    updateButtons(not release and TalkingHeadRuDB and TalkingHeadRuDB.enabled == true)
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

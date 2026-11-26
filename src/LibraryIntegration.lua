-- Temporary upstream preferences. Restore only values still owned by us.
local WV = WowVoice
local overrides, hooks = {}, {}
local function userPreferences(id)
    if not TalkingHeadRuDB then return {} end
    TalkingHeadRuDB.libraryPreferences = TalkingHeadRuDB.libraryPreferences or {}
    local all = TalkingHeadRuDB.libraryPreferences
    all[id] = all[id] or {}
    return all[id]
end
function WV:IsLibraryPreferenceCustomized(id, key)
    local all = TalkingHeadRuDB and TalkingHeadRuDB.libraryPreferences
    return all and all[id] and all[id][key] ~= nil or false
end
function WV:UpdateLibraryPreferences(id, db, desired, active, refresh, customizable, implicitDefaults)
    local state = overrides[id]
    if state and (not active or state.db ~= db) then
        overrides[id] = nil
        for key, entry in pairs(state.values) do
            if state.db[key] == entry.forced then state.db[key] = entry.value end
        end
        if state.refresh then state.refresh() end
        state = nil
    end
    if not active or type(db) ~= "table" then return end
    state = state or {db=db, values={}, observed={}}
    state.refresh = refresh
    overrides[id] = state
    local saved = userPreferences(id)
    local changed = false
    for key, forced in pairs(desired) do
        if type(db[key]) == type(forced) or (db[key] == nil and implicitDefaults and implicitDefaults[key]) then
            local editable = customizable and customizable[key]
            -- A direct edit after our first application also relinquishes ownership.
            if editable and state.observed[key] ~= nil and db[key] ~= state.observed[key] then
                saved[key], state.values[key] = true, nil
            end
            if editable and saved[key] then
                state.values[key] = nil
            else
                local entry = state.values[key]
                if not entry then
                    entry = {value=db[key], forced=forced}
                    state.values[key] = entry
                elseif db[key] ~= forced then
                    entry.value = db[key]
                end
                if db[key] ~= forced then db[key], changed = forced, true end
            end
            state.observed[key] = db[key]
            -- SetValue also observes an explicit choice equal to our override.
            local setting = Settings and Settings.GetSetting and Settings.GetSetting(id .. key)
            if setting and type(setting.SetValue) == "function" and hooksecurefunc then
                if not hooks[setting] then
                    hooksecurefunc(setting, "SetValue", function(_, value)
                        local current = hooks[setting]
                        if overrides[current.id] ~= current.state or type(value) ~= type(current.forced) then return end
                        local currentState = current.state
                        if current.editable then
                            userPreferences(current.id)[current.key] = true
                            currentState.values[current.key] = nil
                            currentState.db[current.key] = value
                        else
                            local entry = currentState.values[current.key]
                            if entry then entry.value = value end
                            currentState.db[current.key] = current.forced
                        end
                        currentState.observed[current.key] = currentState.db[current.key]
                        if currentState.refresh then currentState.refresh() end
                    end)
                end
                hooks[setting] = {id=id, state=state, key=key, forced=forced, editable=editable}
            end
        end
    end
    if changed and refresh then refresh() end
end

-- Do not replace chat-frame methods to silence CatQuest's private Print.
-- Forwarding even an uninspected secret message through our Lua wrapper runs
-- the native chat handler in addon-tainted execution. Suppress library entry
-- points below instead; private informational chat notices may remain visible.

-- CatQuest is a data provider while our player is enabled. Guard entry points
-- before they enqueue, alter history, duck game audio, or start file/TTS/bridge
-- playback. Never wrap the game's shared audio APIs: our CatQuest source uses
-- those same recording paths directly.
local catQuestPlayback, catQuestGuards = nil, {}
local function releaseCatQuestGuards()
    for _, guard in ipairs(catQuestGuards) do
        if guard.owner[guard.key] == guard.wrapper then guard.owner[guard.key] = guard.original end
    end
    catQuestGuards = {}
    catQuestPlayback = nil
end
local function guardCatQuest(owner, key, replacement)
    if type(owner) ~= "table" or type(owner[key]) ~= "function" then return end
    for _, guard in ipairs(catQuestGuards) do
        if guard.owner == owner and guard.key == key and owner[key] == guard.wrapper then return end
    end
    local original = owner[key]
    local guard = {owner=owner, key=key, original=original}
    guard.wrapper = function(...)
        if not catQuestPlayback then return original(...) end
        return replacement(...)
    end
    catQuestGuards[#catQuestGuards + 1] = guard
    owner[key] = guard.wrapper
end
local function silent() return false end
local catQuestPlaybackCommands = {test=true, tts=true, bridge=true, pack=true}
function WV:UpdateCatQuestPlayback(active)
    local core = _G.CatQuestCore
    if catQuestPlayback and (not active or catQuestPlayback ~= core) then releaseCatQuestGuards() end
    if not active or type(core) ~= "table" then return end
    if catQuestPlayback ~= core then
        -- Stop an already running/paused session once, not on every refresh.
        local state = core.state
        if type(state) == "table" and (state.playing or state.pending or state.paused
            or type(core.queue) == "table" and #core.queue > 0) then
            if type(core.ClearQueue) == "function" then core.ClearQueue()
            elseif type(core.Stop) == "function" then core.Stop() end
        end
        -- Preferences are captured by UpdateLibraryPreferences before this call.
        if type(core.WorldSlash) == "function" and type(_G.CatQuestDB) == "table" then
            local previous = CatQuestDB.world
            core.WorldSlash("world test stop")
            core.WorldSlash("world off")
            CatQuestDB.world = previous
        end
        if type(core.Unduck) == "function" then core.Unduck() end
        catQuestPlayback = core
    end
    for _, key in ipairs({"Speak", "Enqueue", "PlayNext", "Resume", "PlayQueued",
        "BridgeSpeak", "SelfTest", "ShowNews", "NewsCheck", "NewsMarkSeen", "ShowWelcome",
        "ShowWelcomeOnce", "NoVoiceHint", "DungeonCommand", "LoreCommand"}) do guardCatQuest(core, key, silent) end
    guardCatQuest(core, "WorldSlash", function(cmd)
        return type(cmd) == "string" and cmd:match("^world") ~= nil
    end)
    guardCatQuest(core.WorldQueue, "Take", silent)
    guardCatQuest(_G, "CatQuest_Toggle", silent)
    -- These commands call private local playback functions, bypassing ns.Speak.
    if type(SlashCmdList) == "table" and type(SlashCmdList.CATQUEST) == "function" then
        local original = SlashCmdList.CATQUEST
        guardCatQuest(SlashCmdList, "CATQUEST", function(msg)
            local cmd = type(msg) == "string" and msg:match("^%s*(%S+)") or ""
            cmd = cmd:lower()
            if catQuestPlaybackCommands[cmd] then return false end
            return original(msg)
        end)
    end
    -- NewsMarkSeen is guarded before Hide: the news frame's OnHide would
    -- otherwise consume unread updates even though our player hid the window.
    for _, name in ipairs({"CatQuestNewsFrame", "CatQuestWelcome", "CatQuestBar"}) do
        local frame = _G[name]
        if frame and type(frame.Hide) == "function" then frame:Hide() end
    end
end
WV:UpdateCatQuestPlayback(not TalkingHeadRuDB or TalkingHeadRuDB.enabled ~= false)

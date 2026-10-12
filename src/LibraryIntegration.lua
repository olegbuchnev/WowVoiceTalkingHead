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
function WV:UpdateLibraryPreferences(id, db, desired, active, refresh, customizable)
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
        if type(db[key]) == type(forced) then
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

-- CatQuest's private Print closes over DEFAULT_CHAT_FRAME:AddMessage. Limit
-- filtering to its prefix; other chat messages and global print are untouched.
local chatGuard, chatActive
function WV:UpdateCatQuestNotifications(active)
    chatActive = active == true
    local chat = DEFAULT_CHAT_FRAME
    if chatGuard and (not chatActive or chatGuard.chat ~= chat) then
        if chatGuard.chat.AddMessage == chatGuard.wrapper then
            chatGuard.chat.AddMessage = chatGuard.original
        end
        chatGuard = nil
    end
    if not chatActive or not chat or type(chat.AddMessage) ~= "function" then return end
    if chatGuard and chat.AddMessage == chatGuard.wrapper then return end
    local original = chat.AddMessage
    local function wrapper(self, text, ...)
        if chatActive and type(text) == "string" and not (issecretvalue and issecretvalue(text))
            and text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^CatQuest:") then return end
        return original(self, text, ...)
    end
    chatGuard = {chat=chat, original=original, wrapper=wrapper}
    chat.AddMessage = wrapper
end
WV:UpdateCatQuestNotifications(not TalkingHeadRuDB or TalkingHeadRuDB.enabled ~= false)

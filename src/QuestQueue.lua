-- Shared gameplay queue, also used by the optional development harness.
local WV = WowVoice
local Q = { enabled = true, groups = {}, offers = {}, paused = false, completed = {}, removals = {} }
WV.questQueue = Q
local driver = CreateFrame("Frame", "WowVoiceQuestQueueDriver")
driver:Hide()

local function key(context)
    return tostring(context.queueOwner or "game") .. ":" .. context.questId .. ":" .. context.section
end

local function questKey(id, owner)
    return tostring(owner or "game") .. ":" .. id
end

local function speakerKey(context)
    local s = context.speaker or {}
    return tostring(context.queueOwner or "game") .. ":" ..
        (s.npcID and "npc:" .. s.npcID or s.objectID and "object:" .. s.objectID
        or s.itemID and "item:" .. s.itemID or "quest:" .. context.questId)
end

local function groupContext(record)
    local context = record.context
    local intro = Q.offers[questKey(context.questId, context.queueOwner) .. ":a"]
    if intro then return intro.context end
    if context.section == "a" then return context end
    -- The root belongs to the giver, even when only turn-in audio is queued.
    -- Never replace the actual speaker used by the talking head.
    if not record.giverContext then
        local replay = WV.GetReplaySpeaker and WV:GetReplaySpeaker(context.questId)
        record.giverContext = { questId = context.questId, queueOwner = context.queueOwner,
            speaker = replay and replay.speaker or {} }
    end
    return record.giverContext
end

function Q:Changed(layoutMode)
    if self.gap and not self:Waiting() then
        self:Remove(self.current, "done")
        self.current, self.gap = nil, nil
        driver:Hide()
        if WV.FinishTalkingHead then WV:FinishTalkingHead(true) end
    end
    if WV.RefreshHeadQueueButton then WV:RefreshHeadQueueButton() end
    if WV.PrepareQuestQueuePortraits then WV:PrepareQuestQueuePortraits(self.groups) end
    if WV.RefreshQuestQueuePlayer then WV:RefreshQuestQueuePlayer(layoutMode) end
    if self.observer then self.observer() end
end

function Q:Count()
    local count = 0
    for _, group in ipairs(self.groups) do count = count + #group.records end
    return count
end

function Q:Add(record, first)
    if record.group then return end
    local context = groupContext(record)
    local id, group = speakerKey(context)
    for _, item in ipairs(self.groups) do
        -- A manual "next" choice must stay ahead of newly accepted lines.
        if item.key == id
            and not (not first and self.nextRecord and self.current and item == self.current.group) then
            group = item; break
        end
    end
    if not group then
        group = { key = id, speaker = context.speaker or {}, records = {} }
        if first then table.insert(self.groups, 1, group) else self.groups[#self.groups + 1] = group end
    elseif first then
        for i, item in ipairs(self.groups) do if item == group then table.remove(self.groups, i); break end end
        table.insert(self.groups, 1, group)
    end
    record.group, record.status = group, "waiting"
    if first then table.insert(group.records, 1, record) else group.records[#group.records + 1] = record end
end

function Q:Remove(record, status)
    local group = record and record.group
    if not record then return end
    if group then
        for i, item in ipairs(group.records) do if item == record then table.remove(group.records, i); break end end
        if #group.records == 0 then
            for i, item in ipairs(self.groups) do if item == group then table.remove(self.groups, i); break end end
        end
    end
    record.group, record.status = nil, status or "skipped"
    if self.nextRecord == record then self.nextRecord = nil end
end

function Q:Waiting()
    for _, group in ipairs(self.groups) do
        for _, record in ipairs(group.records) do if record ~= self.current then return self:ReadyRecord(record) end end
    end
end

function Q:NextQuest()
    local currentId = self.current and questKey(self.current.context.questId, self.current.context.queueOwner)
    for _, group in ipairs(self.groups) do
        for _, record in ipairs(group.records) do
            if questKey(record.context.questId, record.context.queueOwner) ~= currentId then
                return self:ReadyRecord(record)
            end
        end
    end
end

function Q:CanPlayNext(record)
    return self:CanSelect(record) and record ~= self:NextQuest()
end

function Q:ReadyRecord(record)
    if not record then return end
    local prefix = questKey(record.context.questId, record.context.queueOwner)
    for _, section in ipairs({ "a", "p", "c" }) do
        if section == record.context.section then break end
        local earlier = self.offers[prefix .. ":" .. section]
        if earlier and earlier.group and earlier ~= self.current then return earlier end
    end
    return record
end

function Q:CanSelect(record)
    if not record or not record.group or record == self.current then return false end
    if self.current and questKey(record.context.questId, record.context.queueOwner)
        == questKey(self.current.context.questId, self.current.context.queueOwner) then return false end
    return self:ReadyRecord(record) == record
end

function Q:OrderQuestStages(record)
    local sequence, others, stages = {}, {}, {}
    local position
    local identity = questKey(record.context.questId, record.context.queueOwner)
    for _, group in ipairs(self.groups) do
        for _, item in ipairs(group.records) do
            sequence[#sequence + 1] = item
            if questKey(item.context.questId, item.context.queueOwner) == identity then
                position = position or (#others + 1)
                stages[#stages + 1] = item
            else
                others[#others + 1] = item
            end
        end
    end
    local rank = { a = 1, p = 2, c = 3 }
    table.sort(stages, function(a, b)
        if a == b then return false end
        if a == self.current then return true end
        if b == self.current then return false end
        return rank[a.context.section] < rank[b.context.section]
    end)
    if not position then return end
    for i = #stages, 1, -1 do table.insert(others, position, stages[i]) end
    local changed = false
    for i, item in ipairs(others) do
        if sequence[i] ~= item or item.group.key ~= speakerKey(groupContext(item)) then changed = true; break end
    end
    if not changed then return end
    -- Keep a quest's lines together at its earliest position, even when the
    -- receiver differs from the giver. Other quests retain their relative order.
    self.groups = {}
    local group
    for _, item in ipairs(others) do
        local context = groupContext(item)
        local id = speakerKey(context)
        if not group or group.key ~= id then
            group = { key = id, speaker = context.speaker or {}, records = {} }
            self.groups[#self.groups + 1] = group
        end
        group.records[#group.records + 1], item.group = item, group
    end
end

function Q:Schedule()
    if self.enabled and not self.paused and (self.gap or not self.current) and self:Waiting() then driver:Show() end
end

function Q:Start(record)
    if not record then return false end
    record = self:ReadyRecord(record)
    self.gap = nil
    self.paused, self.starting = false, record
    driver:Hide()
    local ok = WV:PlayQueuedQuest(record)
    self.starting = nil
    if not ok then
        if self.current and self.current.status == "done" then
            self:Remove(self.current, "done")
            self.current = nil
            if WV.StopTalkingHead then WV:StopTalkingHead() end
        end
        self:Remove(record, "failed")
        self:Schedule()
    end
    self:Changed()
    return ok
end

function Q:Offer(context)
    if WowVoiceDB and WowVoiceDB.autoPlay == false then return end
    if WowVoiceDB and (context.section == "a" and WowVoiceDB.autoPlayAccept ~= true
        or context.section ~= "a" and WowVoiceDB.autoPlayTurnIn == false) then return end
    if WowVoiceDB and WowVoiceDB.queueDescriptionsOnly and context.section ~= "a" then return end
    local id = key(context)
    if context.section == "p" then
        local completion = self.offers[questKey(context.questId, context.queueOwner) .. ":c"]
        -- A delayed/repeated progress event cannot run after completion started.
        if completion and completion.started then return end
    end
    local previous = self.offers[id]
    if previous and (previous.group or previous == self.current) then return end
    local record = { context = context }
    self.offers[id] = record
    if context.section == "a" then
        -- Opening a description is not accepting it. Only the visible preview
        -- can start immediately; a busy/paused player waits for acceptance.
        if not self.current and not self.paused and not self:Waiting() then self:Start(record) end
    else
        self:Add(record)
        self:OrderQuestStages(record)
        if not self.current and not self.paused then self:Next() end
    end
    self:Changed()
end

function Q:Accept(id, owner)
    if WowVoiceDB and WowVoiceDB.autoPlay == false then return end
    local identity = questKey(id, owner)
    self.completed[identity], self.removals[identity] = nil, nil
    local record = self.offers[tostring(owner or "game") .. ":" .. id .. ":a"]
    if not record or record.status == "done" or record.status == "skipped" or record.status == "failed" then return end
    -- A description merely opened before disabling autoplay is not queued yet.
    if WowVoiceDB and WowVoiceDB.autoPlayAccept ~= true and not record.group then return end
    record.accepted = true
    self:Add(record)
    self:OrderQuestStages(record)
    if record == self.current then record.status = "playing" end
    if not self.current and not self.paused then self:Next() end
    self:Changed()
end

function Q:Abandon(id, owner)
    local prefix = questKey(id, owner)
    for _, section in ipairs({ "a", "p", "c" }) do
        local record = self.offers[prefix .. ":" .. section]
        if record and record ~= self.current then self:Remove(record); self.offers[key(record.context)] = nil end
    end
    self:Changed()
end

function Q:DeleteMatching(matches)
    local removed = {}
    local wasPaused = self.paused
    for _, group in ipairs(self.groups) do
        for _, record in ipairs(group.records) do
            if matches(record) then removed[#removed + 1] = record end
        end
    end
    local stop
    for _, record in ipairs(removed) do
        if record == self.current then stop = true else self:Remove(record) end
    end
    if stop then WV:Silence("queue delete") end
    self.paused = wasPaused and self:Waiting() ~= nil
    if not self.current then self:Schedule() end
    self.forceRefresh = true
    self:Changed()
    self.forceRefresh = nil
end

function Q:DeleteQuest(record)
    if not record or not record.group then return end
    local identity = questKey(record.context.questId, record.context.queueOwner)
    self:DeleteMatching(function(item)
        return questKey(item.context.questId, item.context.queueOwner) == identity
    end)
end

function Q:DeleteNPC(id)
    if not id then return end
    self:DeleteMatching(function(item) return speakerKey(groupContext(item)) == id end)
end

function Q:PlaybackStarted(context)
    if WowVoiceDB and WowVoiceDB.autoPlay == false and not self.starting then return end
    if not context then return end
    self.gap = nil
    local record = self.starting
    if not record then
        record = self.offers[key(context)]
        if not record or not record.group then record = { context = context } end
    end
    if self.current and self.current ~= record then self:Remove(self.current) end
    -- Explicit playback replaces the current line but preserves waiting lines.
    if record.group then
        -- Preserve blocks split by an explicit playback priority.
        local group = record.group
        for i, item in ipairs(group.records) do if item == record then table.remove(group.records, i); break end end
        table.insert(group.records, 1, record)
        for i, item in ipairs(self.groups) do if item == group then table.remove(self.groups, i); break end end
        table.insert(self.groups, 1, group)
    else self:Add(record, true) end
    self.current, record.status, record.started = record, "playing", true
    self:OrderQuestStages(record)
    if self.nextRecord == record then self.nextRecord = nil end
    self.paused = false
    local previousRefresh = self.forceRefresh
    self.forceRefresh = true
    self:Changed("advance")
    self.forceRefresh = previousRefresh
end

function Q:PlaybackStopped(reason)
    local hadCurrent = self.current ~= nil
    local nextRecord = self:Waiting()
    if reason == "duration timer" and self.current and nextRecord then
        local sameQuest = questKey(self.current.context.questId, self.current.context.queueOwner)
            == questKey(nextRecord.context.questId, nextRecord.context.queueOwner)
        self.current.status = "done"
        self.gap = { deadline = GetTime() + (sameQuest and 0.4 or 1), fadeDuration = not sameQuest and 0.7 or nil }
        self:Schedule()
        self:Changed()
        return
    end
    self.gap = nil
    if self.current then self:Remove(self.current,
        (reason == "duration timer" or self.current.status == "done") and "done" or "skipped") end
    self.current = nil
    if reason == "duration timer" then self:Schedule()
    elseif reason ~= "new playback" then self.paused = self:Waiting() ~= nil; driver:Hide() end
    self:Changed((reason == "duration timer" or (hadCurrent and reason == "new playback")) and "advance"
        or (hadCurrent or reason ~= "new playback") and "instant" or nil)
end

function Q:Next()
    local record = self:Waiting()
    if record then return self:Start(record) end
end

function Q:PlayNext(record)
    if not record or not record.group or record == self.current then return end
    record = self:ReadyRecord(record)
    if not self:CanPlayNext(record) then return end
    -- Move whole quests, keeping every remaining stage of the current quest first.
    local selectedId = questKey(record.context.questId, record.context.queueOwner)
    local currentId = self.current and questKey(self.current.context.questId, self.current.context.queueOwner)
    local current, selected, rest = {}, {}, {}
    for _, group in ipairs(self.groups) do
        for _, item in ipairs(group.records) do
            local id = questKey(item.context.questId, item.context.queueOwner)
            local destination = id == currentId and current or id == selectedId and selected or rest
            destination[#destination + 1] = item
        end
    end
    self.groups = {}
    local group
    for _, records in ipairs({ current, selected, rest }) do
        for _, item in ipairs(records) do
            local context = groupContext(item)
            local id = speakerKey(context)
            if not group or group.key ~= id then
                group = { key = id, speaker = context.speaker or {}, records = {} }
                self.groups[#self.groups + 1] = group
            end
            group.records[#group.records + 1], item.group = item, group
        end
    end
    self.nextRecord = record
    local previousRefresh = self.forceRefresh
    self.forceRefresh = true
    self:Changed("instant")
    self.forceRefresh = previousRefresh
end

function Q:Clear(owner)
    local stop = self.current and (not owner or self.current.context.queueOwner == owner)
    if stop then WV:Silence("queue clear") end
    for i = #self.groups, 1, -1 do
        local group = self.groups[i]
        for j = #group.records, 1, -1 do
            local record = group.records[j]
            if not owner or record.context.queueOwner == owner then self:Remove(record) end
        end
    end
    for id, record in pairs(self.offers) do
        if not owner or record.context.queueOwner == owner then self.offers[id] = nil end
    end
    local prefix = owner and (tostring(owner) .. ":")
    for _, map in ipairs({ self.completed, self.removals }) do
        for id in pairs(map) do
            if not prefix or id:sub(1, #prefix) == prefix then map[id] = nil end
        end
    end
    if self:Count() == 0 then self.paused = false; self.nextRecord = nil end
    self:Changed()
end

-- Persist only plain playback data, never frames, audio handles or live unit tokens.
local function copySpeaker(speaker)
    local result = {}
    if type(speaker) ~= "table" then return result end
    for _, field in ipairs({ "npcID", "objectID", "itemID", "displayID", "icon", "name", "title" }) do
        local value = speaker[field]
        if type(value) == "string" or type(value) == "number" then result[field] = value end
    end
    return result
end

local function copyContext(context)
    if type(context) ~= "table" or type(context.questId) ~= "number" or context.questId <= 0
        or context.questId % 1 ~= 0 or not ({ a = true, p = true, c = true })[context.section] then return end
    return { questId = context.questId, section = context.section,
        title = type(context.title) == "string" and context.title or nil,
        text = type(context.text) == "string" and context.text or nil,
        speaker = copySpeaker(context.speaker) }
end

function Q:SaveSession()
    -- Core calls this before stopping audio on PLAYER_LOGOUT (also /reload).
    if self.loggingOut then return end
    self.loggingOut = true
    WowVoiceQueueDB = nil
    if not WowVoiceDB or not WowVoiceDB.enabled then return end
    local saved = { version = 1, savedAt = GetServerTime(), paused = self.paused, records = {}, completed = {} }
    for _, group in ipairs(self.groups) do
        for _, record in ipairs(group.records) do
            local context = record.context
            -- Simulated quests belong to the stand and must never survive it.
            if not context.queueOwner and record.status ~= "done" then
                local entry = { context = copyContext(context), giver = copySpeaker(group.speaker),
                    accepted = record.accepted == true, started = record.started == true }
                saved.records[#saved.records + 1] = entry
                if record == self.nextRecord then saved.nextIndex = #saved.records end
                if self.completed[questKey(context.questId)] then saved.completed[context.questId] = true end
            end
        end
    end
    if #saved.records > 0 then WowVoiceQueueDB = saved end
end

function Q:RestoreSession()
    local saved = WowVoiceQueueDB
    WowVoiceQueueDB = nil -- Consume once; zoning or login must not extend the saved deadline.
    if type(saved) ~= "table" or saved.version ~= 1 or type(saved.savedAt) ~= "number"
        or type(saved.records) ~= "table" then return end
    local elapsed = GetServerTime() - saved.savedAt
    if elapsed < 0 or elapsed >= 300 or not WowVoiceDB or not WowVoiceDB.enabled
        or self:Count() > 0 then return end
    self.paused = saved.paused == true
    local group
    for index, entry in ipairs(saved.records) do
        local context = type(entry) == "table" and copyContext(entry.context)
        if context and not self.offers[key(context)] then
            local giverContext = { questId = context.questId, speaker = copySpeaker(entry.giver) }
            local groupID = speakerKey(giverContext)
            if not group or group.key ~= groupID then
                group = { key = groupID, speaker = giverContext.speaker, records = {} }
                self.groups[#self.groups + 1] = group
            end
            local record = { context = context, giverContext = giverContext, group = group,
                accepted = entry.accepted == true, started = entry.started == true, status = "waiting" }
            group.records[#group.records + 1] = record
            self.offers[key(context)] = record
            if index == saved.nextIndex then self.nextRecord = record end
            if type(saved.completed) == "table" and saved.completed[context.questId] then
                self.completed[questKey(context.questId)] = true
            end
        end
    end
    if self:Count() == 0 then self.paused = false
    elseif WV.GetHeadSettings then WV:GetHeadSettings() end -- Paused restore needs geometry, not playback.
    self:Changed("instant")
    self:Schedule() -- Start after entering the world, with current audio sources.
end

function WV:SetQueueDescriptionsOnly(enabled)
    WowVoiceDB.queueDescriptionsOnly = enabled == true
    if self.RefreshHeadOptions then self:RefreshHeadOptions() end
end

function Q:Event(event, id, owner)
    if not self.enabled then return end
    if event == "QUEST_ACCEPTED" then self:Accept(id, owner)
    elseif event == "QUEST_TURNED_IN" then
        local identity = questKey(id, owner)
        self.completed[identity], self.removals[identity] = true, nil
    elseif event == "QUEST_REMOVED" then
        local identity = questKey(id, owner)
        if not self.completed[identity] then
            -- Removal and successful turn-in can arrive in either order in one
            -- event cycle. Resolve abandonment after those events have settled.
            self.removals[identity] = { id = id, owner = owner }
            driver:Show()
        end
    end
end

local events = CreateFrame("Frame", "WowVoiceQuestQueueEvents")
events:RegisterEvent("QUEST_ACCEPTED")
events:RegisterEvent("QUEST_REMOVED")
events:RegisterEvent("QUEST_TURNED_IN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
local restorePending = true
events:SetScript("OnEvent", function(_, event, id, legacyID)
    if event == "PLAYER_ENTERING_WORLD" then
        if restorePending then restorePending = false; Q:RestoreSession() end
        return
    end
    Q:Event(event, event == "QUEST_ACCEPTED" and (legacyID or id) or id)
end)
driver:SetScript("OnUpdate", function()
    driver:Hide()
    local removed = Q.removals
    Q.removals = {}
    for identity, quest in pairs(removed) do
        if not Q.completed[identity] then Q:Abandon(quest.id, quest.owner) end
    end
    if Q.gap and not Q.paused then
        if GetTime() < Q.gap.deadline then driver:Show()
        else Q:Next() end
    elseif not Q.paused and not Q.current then Q:Next() end
end)

-- Loaded only by build.ps1 -QueueLab, after the public addon.
local Lab, WV = WowVoiceQueueLab, WowVoice
local Sources = WowVoiceAudioSources
local pool
local Q = WV.questQueue

function Lab:Changed(message)
    if message then self.message = message end
    local record = Q.current
    local quest = record and record.context.queueOwner == "lab" and self.state.quests[record.context.questId]
    self.state.current = quest and (record.context.section == "a" and quest.intro
        or record.context.section == "p" and quest.progress or quest.completion) or nil
    if self.Refresh then self:Refresh() end
end

function Lab:Pool()
    if pool then return pool end
    pool = {}
    local titles, entries = {}, {}
    for title, variants in pairs(WowVoiceIndex or {}) do
        for _, entry in ipairs(variants) do
            if not titles[entry.q] or title < titles[entry.q] then
                titles[entry.q], entries[entry.q] = title, entry
            end
        end
    end
    -- Pair descriptions and turn-ins so every accepted test quest can be submitted.
    for key in pairs(WowVoiceDur or {}) do
        local id = tonumber(key:match("^(%d+)a$"))
        if id and WowVoiceDur[id .. "c"] and titles[id] then
            pool[#pool + 1] = { id = id, title = titles[id], entry = entries[id] }
        end
    end
    table.sort(pool, function(a, b) return a.id < b.id end)
    return pool
end

local function makeRecord(candidate, section)
    local path, duration = WV:SoundPath(candidate.id, section)
    if not path or type(duration) ~= "number" or duration <= 0 then return end
    local context = WV:GetReplaySpeaker(candidate.id)
    context.questId, context.title, context.section = candidate.id, candidate.title, section
    context.queueOwner = "lab"
    local text = Sources.Text(candidate.id, section)
    context.text = text or (section == "a" and context.text) or ""
    -- GetReplaySpeaker resolves the giver. Turn-ins can belong to another NPC.
    local entry = candidate.entry
    if section ~= "a" then
        if entry.ei and entry.ei ~= (context.speaker and context.speaker.npcID) then
            context.speaker = { npcID = entry.ei, name = entry.en, title = candidate.title }
        elseif not entry.ei then
            context.speaker = { name = "Получатель задания неизвестен" }
        end
    end
    return { id = candidate.id, section = section, title = candidate.title,
        npc = context.speaker and context.speaker.name or "Неизвестный NPC",
        context = context, path = path, duration = duration }
end

-- Only fixture data and persistent observations are substituted. The normal
-- QUEST_DETAIL / QUEST_PROGRESS / QUEST_COMPLETE handlers make every playback decision.
function Lab:Start(record)
    local frame = WowVoiceFrame
    local handler = frame and frame:GetScript("OnEvent")
    if not handler then self:Changed("Не найден обработчик событий аддона."); return false end
    local replacements = {
        { _G, "GetQuestID", function() return record.id end },
        { _G, "GetTitleText", function() return record.title end },
        { _G, "GetQuestText", function() return record.context.text end },
        { _G, "GetProgressText", function() return record.context.text end },
        { _G, "GetRewardText", function() return record.context.text end },
        -- A fake NPC must not be cached as the real NPC standing nearby.
        { WV, "CaptureQuestSpeaker", function() return record.context end },
        { WV, "MarkQuestListened", function() end },
        { WV, "SetQuestAudioAvailable", function() end },
    }
    for _, item in ipairs(replacements) do
        item[4] = item[1][item[2]]
        item[1][item[2]] = item[3]
    end
    local event = record.section == "a" and "QUEST_DETAIL" or record.section == "p" and "QUEST_PROGRESS" or "QUEST_COMPLETE"
    local ok, err = pcall(handler, frame, event)
    for _, item in ipairs(replacements) do item[1][item[2]] = item[4] end
    if not ok then self:Changed("Ошибка штатного обработчика: " .. tostring(err)); return false end
    self:Changed("")
    return self.state.current == record
end

function Lab:Accept(id)
    local choices = {}
    for _, candidate in ipairs(self:Pool()) do
        if not self.state.quests[candidate.id] and (not id or id == candidate.id) then
            choices[#choices + 1] = candidate
        end
    end
    if #choices == 0 then
        self:Changed(id and "Этот ID уже принят или не имеет обеих записей WowVoice."
            or "Нет новых заданий. Очистите стенд, чтобы начать заново.")
        return false
    end
    local candidate = choices[math.random(#choices)]
    local intro, completion = makeRecord(candidate, "a"), makeRecord(candidate, "c")
    if not intro or not completion then self:Changed("Одна из записей недоступна."); return false end
    self.state:Accept({ id = candidate.id, title = candidate.title, intro = intro,
        progress = makeRecord(candidate, "p"), completion = completion })
    self:Start(intro)
    Q:Event("QUEST_ACCEPTED", candidate.id, "lab")
    return true
end

function Lab:TurnIn(id)
    if not self.state:TurnIn(id) then return false end
    local progress = self.state.quests[id].progress
    if progress then self:Start(progress) end
    self:Start(self.state.quests[id].completion)
    Q:Event("QUEST_TURNED_IN", id, "lab")
    return true
end

function Lab:Abandon(id)
    if not self.state:TurnIn(id) then return false end
    -- This button is an explicit abandonment, unlike an ambiguous journal event.
    Q:Abandon(id, "lab")
    self:Changed("")
    return true
end

function Lab:Reset()
    Q:Clear("lab")
    self.state = self.NewState()
    self:Changed("Тестовые задания очищены.")
end

-- Observe the same queue that handles real dialogs; no playback hooks here.
Q.observer = function() Lab:Changed() end

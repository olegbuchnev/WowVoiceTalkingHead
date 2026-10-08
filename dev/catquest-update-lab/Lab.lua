-- Development addon, installed separately and excluded from release packages.
-- Simulate upstream changes in memory; map test records to existing OGG files.
local WV, S = WowVoice, WowVoiceAudioSources
local NEW_ID, OWNER, FUTURE = 99998, "catquest-update-lab", "0.5.0"
local BUILD = "20261002-3"
local baseline, mode, routes = nil, "reset", {}
local trace, traceOn, traceLog = nil, nil, {}
local function say(text) DEFAULT_CHAT_FRAME:AddMessage("CatQuest Update Lab: " .. text) end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function capture()
    if baseline then return true end
    local status = S.Status()
    if not status or status.updated or not WowVoiceCatQuestAudio then
        say("Нужен установленный CatQuest Voices, совпадающий с проверенной версией наших метаданных. Сначала /wvcqupdate reset.")
        return false
    end
    local quests = CatQuestVoicePack.quests
    if quests[NEW_ID] or not quests[5] or not quests[6] or not quests[179] then
        say("Индекс не подходит для теста: нужны 5, 6, 179 и свободный ID 99998.")
        return false
    end
    baseline = {quests=quests, shared=quests[179], metadata=S.Metadata, resolve=S.Resolve,
        audio=WowVoiceCatQuestAudio, preference=TalkingHeadRuDB.sharedQuestVoice,
        version=status.version}
    return true
end

local function clear()
    WV.questQueue:DeleteMatching(function(record) return record.context.queueOwner == OWNER end)
    for key, record in pairs(WV.questQueue.offers) do
        if record.context.queueOwner == OWNER then WV.questQueue.offers[key] = nil end
    end
end

-- Experimental one-shot Music playback, restricted to lab-owned queue starts.
-- Keep production timing/CVar handling so the client test isolates the API.
local oneShot, traceOff
local function oneShotOff()
    if not oneShot then return end
    local state = oneShot
    state.enabled = false
    if state.handle then StopSound(state.handle); state.handle = nil end
    for _, hook in ipairs(state.hooks) do
        if _G[hook.key] == hook.wrapper then _G[hook.key] = hook.original end
    end
    oneShot = nil
end

local function oneShotOn()
    if mode ~= "changed" and mode ~= "audited" then
        say("Сначала /wvcqupdate changed или /wvcqupdate audited.")
        return
    end
    if type(StopSound) ~= "function" or type(PlaySoundFile) ~= "function" then
        say("Для теста нужны PlaySoundFile и StopSound.")
        return
    end
    clear()
    traceOff()
    oneShotOff()
    local state = {enabled=true,hooks={}}
    oneShot = state
    local function stop()
        if state.handle then StopSound(state.handle); state.handle = nil end
    end
    local function hook(key, callback)
        local original = _G[key]
        local wrapper = function(...)
            if not state.enabled then return original(...) end
            return callback(original, ...)
        end
        state.hooks[#state.hooks + 1] = {key=key,original=original,wrapper=wrapper}
        _G[key] = wrapper
    end
    hook("PlayMusic", function(original, path)
        local starting = WV.questQueue.starting
        local context = starting and starting.context
        local recording = context and context.queueOwner == OWNER and S.Resolve(context.questId, context.section)
        local hadHandle = state.handle ~= nil
        stop() -- Preserve Music's replacement semantics, including manual stops.
        if recording and path == recording.path then
            local ok, handle = PlaySoundFile(path, "Music")
            state.handle = handle
            local result = string.format("ONESHOT RESULT id=%s channel=Music ok=%s handle=%s",
                tostring(context.questId), tostring(ok), tostring(handle))
            if trace then trace.log(result) else say(result) end
            if not ok or not handle then
                stop()
                say("ONESHOT: PlaySoundFile не вернул успешный запуск с handle.")
                return false
            end
            return true
        end
        if hadHandle and path == "Interface\\AddOns\\TalkingHeadRu\\Media\\silence.ogg" then return true end
        return original(path)
    end)
    hook("StopMusic", function(original, ...)
        stop()
        return original(...)
    end)
    say("ONESHOT включён только для queue/solo: PlaySoundFile(..., Music). Установите /thead channel music.")
    return true
end

local function restore()
    if not baseline then return end
    clear()
    if oneShot then traceOff() end
    oneShotOff()
    baseline.quests[179], baseline.quests[NEW_ID] = baseline.shared, nil
    S.Metadata, S.Resolve, WowVoiceCatQuestAudio = baseline.metadata, baseline.resolve, baseline.audio
    TalkingHeadRuDB.sharedQuestVoice = baseline.preference
    if baseline.testChannel ~= nil then
        if TalkingHeadRuDB.channel == "auto" then TalkingHeadRuDB.channel = baseline.testChannel end
        baseline.testChannel = nil
    end
    routes, mode = {}, "reset"
    WV:RefreshAudioSources()
end

local function future(changed)
    if not capture() then return false end
    restore()
    S.Metadata = function(name, field)
        if name == "CatQuest_Voices" and field == "Version" then return FUTURE end
        return baseline.metadata(name, field)
    end
    if changed then
        local shared, added = copy(baseline.quests[6]), copy(baseline.quests[5])
        shared.d, shared.v, shared.t = shared.d + 3, "test-new-voice", nil
        added.t = nil
        for _, record in ipairs({shared, added}) do
            for _, cues in pairs(record.c or {}) do
                if cues[1] then cues[1][2] = "[ТЕСТ ОБНОВЛЕНИЯ] " .. cues[1][2] end
            end
        end
        baseline.quests[179], baseline.quests[NEW_ID] = shared, added
        -- No third-party file edits: changed 179 uses existing quest 6 OGGs;
        -- new 99998 uses quest 5. Production resolver still constructs its path.
        routes[179], routes[NEW_ID] = 6, 5
        S.Resolve = function(id, section)
            local recording = baseline.resolve(id, section)
            local target = routes[id]
            if recording and target then
                local stem = target .. (section == "c" and "_t" or "")
                local suffix = recording.variant == "x" and "" or "_" .. recording.variant
                recording.path = "Interface\\AddOns\\CatQuest_Voices\\Sounds\\q\\" .. stem .. suffix .. ".ogg"
            end
            return recording
        end
    end
    mode = changed and "changed" or "future"
    TalkingHeadRuDB.sharedQuestVoice = "catquest"
    WV:RefreshAudioSources()
    return true
end

local function audited()
    if not future(true) then return end
    local snapshot = copy(baseline.audio)
    snapshot.sourceVersion = FUTURE
    for id, target in pairs(routes) do
        local live = baseline.quests[id]
        local entry = copy(baseline.audio.entries[target .. "a"])
        entry.indexDuration, entry.voice = live.d, live.v or ""
        local function rename(audio, suffix)
            audio.file = id .. suffix .. ".ogg"
        end
        if entry.gender then rename(entry.audio.male, "_m"); rename(entry.audio.female, "_f")
        else rename(entry.audio, "") end
        snapshot.entries[id .. "a"] = entry
    end
    WowVoiceCatQuestAudio, mode = snapshot, "audited"
    WV:RefreshAudioSources()
end

local function status()
    local source, reason = S.Status()
    say("BUILD=" .. BUILD .. " oneshot=" .. tostring(oneShot ~= nil)
        .. " trace=" .. tostring(trace ~= nil) .. " lines=" .. #traceLog)
    say("Режим: " .. mode .. "; версия: " .. (source and source.version or tostring(reason)))
    for _, id in ipairs({179, 98430, NEW_ID}) do
        local record = S.Resolve(id, "a")
        say(id .. ": " .. (record and string.format("%s, %.3f с, %s", record.variant,
            record.duration, record.verified and "точный таймер" or "приблизительный таймер") or "нет записи CatQuest"))
    end
end

local function queueReady()
    local Q = WV.questQueue
    for _, group in ipairs(Q.groups) do
        for _, record in ipairs(group.records) do
            if record.context.queueOwner ~= OWNER then
                say("Сначала закончите или очистите обычную очередь; стенд её не заменяет.")
                return
            end
        end
    end
    if not TalkingHeadRuDB.enabled or not TalkingHeadRuDB.autoPlay or not TalkingHeadRuDB.autoPlayAccept
        or not TalkingHeadRuDB.queueAutoPlay then
        say("Включите озвучку, автозапуск, получение заданий и автовоспроизведение очереди.")
        return
    end
    return true
end

local function queue(ids)
    if not baseline or (mode ~= "changed" and mode ~= "audited") then
        say("Сначала /wvcqupdate changed или /wvcqupdate audited.")
        return
    end
    if not queueReady() then return end
    if not trace then traceOn() end
    clear()
    local Q = WV.questQueue
    ids = ids or {179, NEW_ID}
    for _, id in ipairs(ids) do
        local replay = WV:GetReplaySpeaker(id)
        Q:Offer({questId=id,section="a",title="ТЕСТ CatQuest " .. id,
            speaker=replay.speaker,queueOwner=OWNER})
        Q:Accept(id, OWNER)
    end
    say("Тестовая очередь: " .. table.concat(ids, " → ") .. ". Реальные задания и журнал не меняются.")
end

-- Temporary diagnostics only: observe calls without changing playback timers.
traceOff = function()
    if not trace then return end
    trace.enabled = false
    for _, hook in ipairs(trace.hooks) do
        if hook.object[hook.key] == hook.wrapper then hook.object[hook.key] = hook.original end
    end
    trace = nil
end

traceOn = function()
    traceOff()
    traceLog = {}
    local state = {enabled=true, started=GetTime(), hooks={}}
    trace = state
    local function log(text)
        if not state.enabled then return end
        local line = string.format("TRACE +%.3f %s", GetTime() - state.started, text)
        if #traceLog >= 100 then table.remove(traceLog, 1) end
        traceLog[#traceLog + 1] = line
        say(line)
    end
    state.log = log
    local function hook(object, key, observe, result)
        local original = object[key]
        local wrapper = function(...)
            if state.enabled then observe(...) end
            if result then
                local ok, handle = original(...)
                if state.enabled then result(ok, handle) end
                return ok, handle
            end
            return original(...)
        end
        state.hooks[#state.hooks + 1] = {object=object,key=key,original=original,wrapper=wrapper}
        object[key] = wrapper
    end
    hook(_G, "PlayMusic", function(path)
        log("PlayMusic " .. tostring(path))
    end)
    hook(_G, "StopMusic", function() log("StopMusic") end)
    hook(_G, "PlaySoundFile", function(path, channel)
        log("PlaySoundFile channel=" .. tostring(channel) .. " " .. tostring(path)
            .. " musicEnabled=" .. tostring(GetCVar("Sound_EnableMusic"))
            .. " musicVolume=" .. tostring(GetCVar("Sound_MusicVolume")))
    end, function(ok, handle)
        log("PlaySoundFile RESULT ok=" .. tostring(ok) .. " handle=" .. tostring(handle))
    end)
    if type(StopSound) == "function" then
        hook(_G, "StopSound", function(handle) log("StopSound handle=" .. tostring(handle)) end)
    end
    hook(WV.questQueue, "PlaybackStarted", function(_, context)
        if not context or context.queueOwner ~= OWNER then return end
        local id = context.questId
        local record = S.Resolve(id, context.section)
        local target = routes[id]
        local entry = baseline and target and baseline.audio.entries[target .. context.section]
        local audio = entry and entry.audio
        if entry and entry.gender and record then
            audio = audio[record.variant == "f" and "female" or "male"]
        end
        state.current = {id=id,started=GetTime()}
        log(string.format("START %s timer=%.3f tail=%.3f OGG=%s", tostring(id),
            record and record.duration or 0, tonumber(TalkingHeadRuDB.tail) or 0.05,
            audio and string.format("%.3f", audio.duration) or "unknown"))
    end)
    hook(WV.questQueue, "PlaybackStopped", function(_, reason)
        local current = state.current
        if current then
            log(string.format("STOP %s elapsed=%.3f reason=%s", tostring(current.id),
                GetTime() - current.started, tostring(reason)))
            state.current = nil
        end
    end)
    log("ON build=" .. BUILD .. " mode=" .. mode .. " channel=" .. tostring(TalkingHeadRuDB.channel)
        .. " stopmode=" .. tostring(TalkingHeadRuDB.stopmode)
        .. " oneshot=" .. tostring(oneShot ~= nil)
        .. " background=" .. tostring(GetCVar("Sound_EnableSoundWhenGameIsInBG")))
end

local function test(ids)
    -- Exercise production routing, including the established background-off
    -- Music path. The experimental one-shot Music path exposes zone music.
    if not queueReady() then return end
    if type(StopSound) ~= "function" or type(PlaySoundFile) ~= "function" then
        say("Для теста нужны PlaySoundFile и StopSound.")
        return
    end
    if not future(true) then return end
    baseline.testChannel = TalkingHeadRuDB.channel
    TalkingHeadRuDB.channel = "auto"
    traceOn()
    queue(ids)
end

SLASH_WOWVOICECATQUESTUPDATELAB1 = "/wvcqupdate"
SlashCmdList.WOWVOICECATQUESTUPDATELAB = function(command)
    command = (command or ""):match("^%s*(.-)%s*$"):lower()
    if command == "future" then future(false)
    elseif command == "changed" then future(true)
    elseif command == "invalid" then
        if future(true) then baseline.quests[179].d = -1; mode = "invalid"; WV:RefreshAudioSources() end
    elseif command == "missing" then
        if future(true) then routes[NEW_ID] = nil; mode = "missing"; WV:RefreshAudioSources() end
    elseif command == "audited" then audited()
    elseif command == "queue" then queue()
    elseif command == "solo" then queue({NEW_ID})
    elseif command == "oneshot" then oneShotOn(); return
    elseif command == "test" then test(); return
    elseif command == "test solo" then test({NEW_ID}); return
    elseif command == "trace" then traceOn(); return
    elseif command == "traceoff" then traceOff(); say("TRACE выключен."); return
    elseif command == "report" then
        say("REPORT build=" .. BUILD .. " mode=" .. mode .. " oneshot=" .. tostring(oneShot ~= nil)
            .. " trace=" .. tostring(trace ~= nil) .. " lines=" .. #traceLog)
        if #traceLog == 0 then
            say("Журнал пуст: тест ещё не записан в этой сессии. /reload очищает журнал. Запуск: /wvcqupdate test")
        end
        for _, line in ipairs(traceLog) do say(line) end
        return
    elseif command == "mark" then
        if trace then
            local current = trace.current
            trace.log(current and string.format("MARK %s elapsed=%.3f", tostring(current.id),
                GetTime() - current.started) or "MARK no active test track")
        end
        return
    elseif command == "reset" then restore(); baseline = nil; traceOff()
    elseif command ~= "status" then
        say("BUILD=" .. BUILD .. "; команды: test, test solo, future, changed, invalid, missing, audited, queue, solo, oneshot, status, reset, trace, traceoff, report, mark.")
        return
    end
    status()
end

local lifecycle = CreateFrame("Frame", "WowVoiceCatQuestUpdateLabLifecycle")
lifecycle:RegisterEvent("PLAYER_LOGOUT")
lifecycle:SetScript("OnEvent", function() restore(); baseline = nil; traceOff() end)

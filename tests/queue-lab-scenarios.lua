event('ADDON_LOADED')
WowVoice:GetHeadSettings()
local Lab, Q = WowVoiceQueueLab, WowVoice.questQueue
local pool, ids = Lab:Pool(), {}
for i = 1, 18 do ids[i] = pool[i].id end
local function step()
    local driver = frames.WowVoiceQuestQueueDriver
    if driver.visible then driver.scripts.OnUpdate() end
end
local function finish()
    local _, duration = WowVoice:SoundPath(Q.current.context.questId, Q.current.context.section)
    tick(now + duration + 1)
    step()
    if Q.gap then tick(Q.gap.deadline); step() end
end
local function fixture(id, npc, section, owner)
    local speaker = WowVoice:GetReplaySpeaker(id)
    return { questId = id, section = section or 'a', title = 'Quest ' .. id,
        text = WowVoiceAudioSources.Text(id, section or 'a') or '', queueOwner = owner or 'lab',
        speaker = { npcID = npc, name = 'NPC ' .. npc, displayID = 1234 } }
end
local function offer(id, npc, section)
    local context = fixture(id, npc, section)
    Q:Offer(context)
    return Q.offers['lab:' .. id .. ':' .. context.section]
end

-- Same gameplay queue receives production dialog and acceptance events.
assert(Q.enabled and SLASH_WOWVOICEQUEUELAB1 == '/tt')
-- Upstream WowVoice can leave its detached frame under this shared global.
-- The lab must call our live handler even if that global is stale or missing.
local liveFrame = WowVoiceFrame
WowVoiceFrame = CreateFrame('Frame')
assert(Lab:Accept(ids[1]))
assert(Q.current and Q.current.context.questId == ids[1], 'lab must use its own event frame, not the detached upstream global')
Lab:Reset()
WowVoiceFrame = nil
assert(Lab:Accept(ids[1]))
assert(Q.current and Q.current.context.questId == ids[1], 'lab must work without the shared frame global')
Lab:Reset()
WowVoiceFrame = liveFrame
local originalHandler = WowVoiceFrame:GetScript('OnEvent')
local emitted = {}
WowVoiceFrame:SetScript('OnEvent', function(frame, name, ...)
    emitted[#emitted + 1] = name
    return originalHandler(frame, name, ...)
end)
local api, capture, mark = GetQuestID, WowVoice.CaptureQuestSpeaker, WowVoice.MarkQuestListened
assert(Lab:Accept(ids[1]))
local current, count = Q.current, #plays
assert(current and Lab.state.current and current.context.queueOwner == 'lab')
assert(Lab:Accept(ids[2]))
assert(Q.current == current and #plays == count and Q:Count() == 2)
assert(emitted[1] == 'QUEST_DETAIL' and emitted[2] == 'QUEST_DETAIL')
assert(GetQuestID == api and WowVoice.CaptureQuestSpeaker == capture and WowVoice.MarkQuestListened == mark)
assert(not Lab:Accept(ids[1]))
assert(frames.WowVoiceQuestQueuePlayer.visible)
Lab:Abandon(ids[2])
assert(Q:Count() == 1 and Q.current == current)
Lab:Reset()
assert(not Q.current and Q:Count() == 0)

-- Next lives only in the queue toolbar; adding entries does not change head text space.
Lab:Accept(ids[1])
local head = TalkingHeadRu
local normalNameWidth = head.Name:GetWidth()
assert(not head.Next and not frames.WowVoiceQuestQueuePlayer:IsShown())
count = #plays
Lab:Accept(ids[2])
local nextButton = frames.WowVoiceQuestQueuePlayer.Next
assert(nextButton:IsEnabled() and #plays == count)
assert(head.Name:GetWidth() == normalNameWidth)
nextButton.scripts.OnClick(nextButton)
assert(Q.current.context.questId == ids[2] and #plays == count + 1)
assert(not nextButton:IsEnabled() and head.Name:GetWidth() == normalNameWidth)
Lab:Reset()

-- NPC 1/A, NPC 2/B, NPC 1/C: grouped playback A, C, B.
local a = offer(ids[1], 1001); Q:Accept(ids[1], 'lab')
local b = offer(ids[2], 2002)
assert(not b.group, 'viewing while busy does not enqueue')
Q:Accept(ids[2], 'lab')
local c = offer(ids[3], 1001); Q:Accept(ids[3], 'lab')
assert(#Q.groups == 2 and #Q.groups[1].records == 2 and Q.groups[1].records[2] == c)
assert(Q:Waiting() == c)
Q:Accept(ids[3], 'lab')
assert(Q:Count() == 3, 'acceptance cannot duplicate')
finish()
assert(Q.current == c and a.status == 'done')
finish()
assert(Q.current == b)
local d = offer(ids[4], 1001); Q:Accept(ids[4], 'lab')
assert(Q.current == b and Q.groups[2].records[1] == d, 'finished NPC gets a new block at the end')
Q:Abandon(ids[4], 'lab')
assert(Q.current == b and Q:Count() == 1)
Q:Clear()

-- A completed preview must not repeat on later acceptance; no invented text.
local text, replay = WowVoiceAudioSources.Text, WowVoice.GetReplaySpeaker
WowVoiceAudioSources.Text = function() return nil end
WowVoice.GetReplaySpeaker = function() return { speaker = {} } end
Lab:Accept(ids[1])
assert(TalkingHeadRu.Body.text == '')
WowVoiceAudioSources.Text, WowVoice.GetReplaySpeaker = text, replay
Lab:Reset()
a = offer(ids[1], 1001)
finish()
count = #plays
Q:Accept(ids[1], 'lab')
assert(not Q.current and Q:Count() == 0 and #plays == count)
Q:Clear()

-- Completion survives journal removal and isn't cut by the next offer.
a = offer(ids[1], 1001); Q:Accept(ids[1], 'lab')
local completion = offer(ids[1], 1001, 'c')
Q:Event('QUEST_TURNED_IN', ids[1], 'lab')
Q:Event('QUEST_REMOVED', ids[1], 'lab')
assert(completion.group and Q.current == a)
b = offer(ids[2], 1001); Q:Accept(ids[2], 'lab')
finish(); assert(Q.current == completion)
finish(); assert(Q.current == b)
Q:Clear()

-- All unread stages survive submission under the giver, with the real receiver speaking.
local progressID
for _, candidate in ipairs(pool) do
    if WowVoiceDur[candidate.id .. 'p'] and candidate.id ~= ids[1] and candidate.id ~= ids[4] then
        progressID = candidate.id; break
    end
end
assert(progressID, 'fixture requires a real quest with description, progress and completion audio')
-- Submitting a current or waiting quest keeps its whole conversation together.
-- Cover shared NPC blocks, different receivers, and reversed dialog delivery.
for _, waiting in ipairs({ false, true }) do
    for _, receiver in ipairs({ 1001, 3003 }) do
        for _, reversed in ipairs({ false, true }) do
            local blocker
            if waiting then blocker = offer(ids[1], 2002); Q:Accept(ids[1], 'lab') end
            local intro = offer(progressID, 1001); Q:Accept(progressID, 'lab')
            local other = offer(ids[4], 1001); Q:Accept(ids[4], 'lab')
            local before = #plays
            local middle, ending
            if reversed then
                ending = offer(progressID, receiver, 'c')
                middle = offer(progressID, receiver, 'p')
            else
                middle = offer(progressID, receiver, 'p')
                ending = offer(progressID, receiver, 'c')
            end
            assert(#plays == before and Q.current == (blocker or intro), 'submission must not interrupt')
            local actual = {}
            for _, group in ipairs(Q.groups) do
                for _, record in ipairs(group.records) do actual[#actual + 1] = record end
            end
            local expected = waiting and { blocker, intro, middle, ending, other }
                or { intro, middle, ending, other }
            for i, record in ipairs(expected) do
                assert(actual[i] == record, 'visible queue must keep quest stages adjacent')
                assert(Q.current == record, 'playback must follow the visible contiguous quest order')
                if record == intro or record == middle or record == ending then
                    assert(record.group.speaker.npcID == 1001, 'all stages stay under the quest giver')
                end
                if record == middle or record == ending then
                    assert(record.context.speaker.npcID == receiver, 'playback retains the real receiver')
                end
                finish()
            end
            assert(not Q.current and Q:Count() == 0)
            Q:Clear()
        end
    end
end

for _, reversed in ipairs({ false, true }) do
    a = offer(ids[1], 1001); Q:Accept(ids[1], 'lab')
    b = offer(progressID, 2002); Q:Accept(progressID, 'lab')
    local progress = offer(progressID, 1001, 'p')
    completion = offer(progressID, 1001, 'c')
    -- Turn-in lines belong to the giver's root, not the receiver's active block.
    assert(Q.groups[1].records[1] == a and Q.groups[2].records[1] == b)
    assert(#Q.groups == 2 and Q.groups[2].records[2] == progress and Q.groups[2].records[3] == completion)
    local total = Q:Count()
    offer(progressID, 1001, 'p'); offer(progressID, 1001, 'c')
    assert(Q:Count() == total, 'repeated turn-in dialogs do not duplicate queued lines')
    local first = reversed and 'QUEST_REMOVED' or 'QUEST_TURNED_IN'
    local second = reversed and 'QUEST_TURNED_IN' or 'QUEST_REMOVED'
    Q:Event(first, progressID, 'lab'); Q:Event(second, progressID, 'lab'); step()
    assert(b.group and progress.group and completion.group, 'successful turn-in must preserve all unheard stages')
    for _, record in ipairs({ progress, completion }) do
        local visual
        for _, frame in ipairs(allFrames) do if frame.record == record and frame.Icon then visual = frame end end
        assert(visual and visual.Icon.texture:find('ActiveQuestIcon', 1, true))
        assert(visual.Title.text == 'Сдача: ' .. record.context.title)
    end
    if reversed then
        -- Starting another line in the receiver block must not merge later turn-ins back into it.
        d = offer(ids[4], 1001); Q:Accept(ids[4], 'lab')
        finish(); assert(Q.current == d)
    end
    finish(); assert(Q.current == b, 'description must play before its turn-in')
    finish(); assert(Q.current == progress)
    finish(); assert(Q.current == completion)
    finish(); assert(not Q.current and Q:Count() == 0)
    Q:Clear()
end

-- Reverse delivery and explicit completion clicks cannot bypass waiting progress.
a = offer(ids[1], 1001); Q:Accept(ids[1], 'lab')
b = offer(progressID, 2002); Q:Accept(progressID, 'lab')
completion = offer(progressID, 1001, 'c')
local lateProgress = offer(progressID, 1001, 'p')
assert(#Q.groups == 2 and Q.groups[2].records[2] == lateProgress and Q.groups[2].records[3] == completion)
finish(); assert(Q.current == b)
finish(); assert(Q.current == lateProgress)
finish(); assert(Q.current == completion)
local countBeforeLate = Q:Count()
offer(progressID, 1001, 'p')
assert(Q:Count() == countBeforeLate, 'late progress is ignored once completion has started')
Q:Clear()
for _, action in ipairs({ 'Start', 'PlayNext' }) do
    a = offer(ids[1], 1001); Q:Accept(ids[1], 'lab')
    local progress = offer(progressID, 2002, 'p')
    completion = offer(progressID, 2002, 'c')
    Q[action](Q, completion)
    if action == 'PlayNext' then assert(Q:Waiting() == progress); finish() end
    assert(Q.current == progress, 'explicit completion selection must start its pending progress first')
    Q:Next(); assert(Q.current == completion)
    Q:Clear()
end

-- An unknown giver stays one root: a known receiver must not split off the turn-in.
local unknownContext = fixture(progressID, 1001)
unknownContext.speaker = {}
Q:Offer(unknownContext); Q:Accept(progressID, 'lab')
local unknownIntro = Q.current
local knownProgress = offer(progressID, 8200, 'p')
completion = offer(progressID, 8200, 'c')
assert(#Q.groups == 1 and knownProgress.group == unknownIntro.group and completion.group == unknownIntro.group)
assert(not Q.groups[1].speaker.npcID and knownProgress.context.speaker.npcID == 8200)
finish(); assert(Q.current == knownProgress and not Q.groups[1].speaker.npcID)
finish(); assert(Q.current == completion and not Q.groups[1].speaker.npcID)
Q:Clear()

-- Turn-in without an intro in this session uses the saved/indexed giver only for grouping.
local getReplay = WowVoice.GetReplaySpeaker
WowVoice.GetReplaySpeaker = function(_, id)
    return { questId = id, speaker = { npcID = 8100, name = 'Saved giver' } }
end
local standalone = offer(progressID, 8200, 'p')
assert(Q.current == standalone and standalone.group.speaker.npcID == 8100)
assert(standalone.context.speaker.npcID == 8200)
completion = offer(progressID, 8200, 'c')
assert(completion.group == standalone.group and #Q.groups == 1)
finish(); assert(Q.current == completion and completion.group.speaker.npcID == 8100)
Q:Clear()
WowVoice.GetReplaySpeaker = getReplay

-- Only the first waiting stage of each quest is actionable in the player.
a = offer(ids[1], 1001); Q:Accept(ids[1], 'lab')
d = offer(ids[4], 1001); Q:Accept(ids[4], 'lab')
b = offer(progressID, 2002); Q:Accept(progressID, 'lab')
local progress = offer(progressID, 2002, 'p')
completion = offer(progressID, 2002, 'c')
local function rowFor(record)
    for _, frame in ipairs(allFrames) do if frame.record == record and frame.Icon then return frame end end
end
assert(Q:ReadyRecord(progress) == b and Q:ReadyRecord(completion) == b)
assert(rowFor(b).Next.enabled and not rowFor(progress).Next.enabled and not rowFor(completion).Next.enabled)
assert(rowFor(b).Next:IsShown() and not rowFor(progress).Next:IsShown() and not rowFor(completion).Next:IsShown())
assert(not rowFor(a).Next:IsShown() and not rowFor(d).Next:IsShown(), 'current and already-next lines have no Next button')
assert(rowFor(b).Play:IsShown() and rowFor(d).Play:IsShown())
assert(not rowFor(a).Play:IsShown() and not rowFor(progress).Play:IsShown() and not rowFor(completion).Play:IsShown())
assert(rowFor(b).Play.Icon.texture == 'Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up')
local soundCount = #plays
rowFor(completion).scripts.OnClick(rowFor(completion))
rowFor(progress).Next.scripts.OnClick(rowFor(progress).Next)
assert(Q.current == a and #plays == soundCount, 'blocked row controls must not bypass the description')
rowFor(b).Next.scripts.OnClick(rowFor(b).Next)
finish(); assert(Q.current == b)
assert(Q:ReadyRecord(progress) == progress and Q:ReadyRecord(completion) == progress)
assert(not rowFor(progress).Play:IsShown() and not rowFor(progress).Next:IsShown())
soundCount = #plays
rowFor(progress).Play.scripts.OnClick(rowFor(progress).Play)
rowFor(progress).scripts.OnClick(rowFor(progress))
Q:PlayNext(progress)
assert(Q.current == b and #plays == soundCount, 'cannot manually jump to another stage of the playing quest')
Q:Start(completion) -- Defensive API check, even if a caller bypasses the disabled UI.
assert(Q.current == progress)
assert(Q:ReadyRecord(completion) == completion)
assert(not rowFor(completion).Play:IsShown() and not rowFor(completion).Next:IsShown())
soundCount = #plays
rowFor(completion).Play.scripts.OnClick(rowFor(completion).Play)
rowFor(completion).scripts.OnClick(rowFor(completion))
assert(Q.current == progress and #plays == soundCount)
finish(); assert(Q.current == completion, 'automatic progress-to-completion transition remains available')
Q:Clear()

-- A true abandonment removes waiting description/progress/completion together.
a = offer(ids[1], 1001); Q:Accept(ids[1], 'lab')
b = offer(progressID, 2002); Q:Accept(progressID, 'lab')
offer(progressID, 2002, 'p'); offer(progressID, 2002, 'c')
Q:Event('QUEST_REMOVED', progressID, 'lab'); step()
assert(Q:Count() == 1 and Q.current == a)
Q:Clear()

-- The lab's submit action drives the real intermediate and completion events.
Lab:Open()
Lab:Accept(progressID)
assert(Lab.state.quests[progressID].progress)
Lab:TurnIn(progressID)
assert(emitted[#emitted - 1] == 'QUEST_PROGRESS' and emitted[#emitted] == 'QUEST_COMPLETE')
assert(Q.current.context.section == 'a' and Q:Count() == 3)
finish(); assert(Q.current.context.section == 'p' and Lab.state.current.section == 'p')
finish(); assert(Q.current.context.section == 'c')
Lab:Reset()

-- Close preserves disabled autoplay; accepted additions do not resume it.
a = offer(ids[1], 1001); Q:Accept(ids[1], 'lab')
b = offer(ids[2], 2002); Q:Accept(ids[2], 'lab')
WowVoice:SetQueueAutoPlay(false)
TalkingHeadRu.Close.scripts.OnClick()
assert(Q.paused and not Q.current and Q:Count() == 1 and a.status == 'skipped')
c = offer(ids[3], 1001); Q:Accept(ids[3], 'lab')
count = #plays
step(); assert(#plays == count and not Q.current)
assert(frames.WowVoiceQuestQueuePlayer.visible, 'paused queue remains accessible after hiding head')
assert(rowFor(b).Play:IsShown())
rowFor(b).Play.scripts.OnClick(rowFor(b).Play)
assert(Q.current == b and a.status == 'skipped', 'Play starts the chosen record, not the discarded one')
assert(not rowFor(b).Play:IsShown())
Q:Clear()
WowVoice:SetQueueAutoPlay(true)

-- Cross/right-click skip only the current track, preserving both autoplay
-- preference and checkbox. Exercise Master and the background-off Music path.
local savedMusic, savedStopMusic = PlayMusic, StopMusic
local savedBackground = cvars.Sound_EnableSoundWhenGameIsInBG
local musicFiles, musicStops = {}, 0
PlayMusic = function(path) musicFiles[#musicFiles+1] = path; return true end
StopMusic = function() musicStops = musicStops + 1 end
for _, background in ipairs({'1','0'}) do
    cvars.Sound_EnableSoundWhenGameIsInBG = background
    for _, button in ipairs({'cross','right'}) do
        a = offer(ids[1], 1001); Q:Accept(ids[1], 'lab')
        b = offer(ids[2], 2002); Q:Accept(ids[2], 'lab')
        c = offer(ids[3], 3003); Q:Accept(ids[3], 'lab')
        local oldHandle, oldStops, oldMusicStops = plays[#plays].handle, #stops, musicStops
        local checkbox = frames.WowVoiceQuestQueuePlayer.Autoplay.Check
        if button == 'cross' then TalkingHeadRu.Close.scripts.OnClick()
        else TalkingHeadRu.scripts.OnClick(TalkingHeadRu, 'RightButton') end
        assert(not Q.current and not Q.paused and Q:Count() == 2 and a.status == 'skipped')
        assert(TalkingHeadRuDB.queueAutoPlay and checkbox:GetChecked(), 'dismissal must retain autoplay')
        if background == '1' then assert(#stops == oldStops + 1 and stops[#stops] == oldHandle)
        else assert(musicStops == oldMusicStops + 1) end
        step()
        assert(Q.current == b and TalkingHeadRu:IsShown(), 'next head must survive old playback cleanup')
        if background == '1' then assert(plays[#plays].file == WowVoice:SoundPath(ids[2], 'a'))
        else assert(musicFiles[#musicFiles] == WowVoice:SoundPath(ids[2], 'a')) end
        finish(); assert(Q.current == c, 'autoplay continues after the skipped track')
        TalkingHeadRu.Close.scripts.OnClick(); step()
        assert(not Q.current and Q:Count() == 0 and not TalkingHeadRu:IsShown())
        assert(TalkingHeadRuDB.queueAutoPlay, 'closing the last track preserves the saved choice')
        Q:Clear()
    end
end
PlayMusic, StopMusic = savedMusic, savedStopMusic
cvars.Sound_EnableSoundWhenGameIsInBG = savedBackground

-- Explicit next overrides NPC grouping, explicit now replaces only current.
a = offer(ids[1], 1001); Q:Accept(ids[1], 'lab')
b = offer(ids[2], 2002); Q:Accept(ids[2], 'lab')
c = offer(ids[3], 1001); Q:Accept(ids[3], 'lab')
Q:PlayNext(b)
assert(Q.current == a and Q:Waiting() == b and Q.groups[2].records[1] == b)
finish(); assert(Q.current == b)
Q:Start(c); assert(Q.current == c and Q:Count() == 1)
Q:Clear()

-- A newly accepted task cannot jump ahead of an explicit next choice.
a = offer(ids[1], 1001); Q:Accept(ids[1], 'lab')
d = offer(ids[4], 3003); Q:Accept(ids[4], 'lab')
b = offer(ids[2], 2002); Q:Accept(ids[2], 'lab')
Q:PlayNext(b)
c = offer(ids[3], 1001); Q:Accept(ids[3], 'lab')
assert(Q:Waiting() == b and Q.groups[2].records[1] == b)
finish(); assert(Q.current == b)
Q:Clear()

-- Next means next quest, after every remaining stage of the currently playing quest.
a = offer(progressID, 1001); Q:Accept(progressID, 'lab')
local currentProgress = offer(progressID, 1001, 'p')
local currentCompletion = offer(progressID, 1001, 'c')
b = offer(ids[1], 2002); Q:Accept(ids[1], 'lab')
local nextCompletion = offer(ids[1], 2002, 'c')
assert(Q:Waiting() == currentProgress and Q:NextQuest() == b)
assert(not rowFor(b).Next:IsShown() and not Q:CanPlayNext(b), 'already-next quest needs no priority link')
local unchangedCount = #plays
Q:PlayNext(b)
assert(Q:Waiting() == currentProgress and #plays == unchangedCount)
c = offer(ids[4], 3003); Q:Accept(ids[4], 'lab')
local chosenCompletion = offer(ids[4], 3003, 'c')
assert(rowFor(c).Next:IsShown())
rowFor(c).Next.scripts.OnClick(rowFor(c).Next)
assert(Q.current == a and Q:Waiting() == currentProgress and Q:NextQuest() == c)
assert(not rowFor(c).Next:IsShown() and rowFor(b).Next:IsShown())
local sequence = {}
for _, group in ipairs(Q.groups) do
    for _, record in ipairs(group.records) do sequence[#sequence + 1] = record end
end
local expectedSequence = { a, currentProgress, currentCompletion, c, chosenCompletion, b, nextCompletion }
for i, record in ipairs(expectedSequence) do
    assert(sequence[i] == record and Q.current == record, 'priority must preserve both quests as complete chains')
    finish()
end
assert(Q:Count() == 0 and not Q.current)
Q:Clear()

-- A dialog between natural completion and deferred advance cannot overtake.
a = offer(ids[1], 1001); Q:Accept(ids[1], 'lab')
b = offer(ids[2], 2002); Q:Accept(ids[2], 'lab')
local _, duration = WowVoice:SoundPath(ids[1], 'a')
tick(now + duration + 1)
assert(Q.current == a and Q.gap and a.status == 'done')
c = offer(ids[3], 3003)
assert(Q.current == a and not c.group)
Q:Accept(ids[3], 'lab')
assert(Q.current == a and Q:Waiting() == b, 'acceptance during the gap must not bypass it')
tick(Q.gap.deadline); step()
assert(Q.current == b)
Q:Clear()

-- Automatic transitions use one second across quests (0.7 fade + 0.3 hidden).
a = offer(ids[1], 1001); Q:Accept(ids[1], 'lab')
b = offer(ids[2], 2002); Q:Accept(ids[2], 'lab')
local gapPlayer, gapHead = frames.WowVoiceQuestQueuePlayer, TalkingHeadRu
local _, gapAudioDuration = WowVoice:SoundPath(ids[1], 'a')
tick(now + gapAudioDuration + 1)
local gapStarted, gapSounds = now, #plays
local waitingY = rowFor(b).viewY
assert(Q.gap and Q.current == a and a.status == 'done')
assert(Q.gap.deadline == gapStarted + 1 and gapPlayer.Next:IsEnabled())
assert(gapPlayer:IsShown() and not gapPlayer.fading and not rowFor(a).Bars[1].visible)
tick(gapStarted + 0.35); gapHead.scripts.OnUpdate(gapHead); step()
assert(math.abs(gapHead.visualAlpha - 0.5) < 0.001 and Q.current == a and #plays == gapSounds)
assert(rowFor(b).viewY == waitingY, 'do not advance the list before audio starts')
tick(gapStarted + 0.71); gapHead.scripts.OnUpdate(gapHead); step()
assert(not gapHead:IsShown() and gapPlayer:IsShown() and Q.current == a)
tick(gapStarted + 0.99); step(); assert(#plays == gapSounds)
tick(gapStarted + 1); step()
assert(Q.current == b and not Q.gap and gapHead:IsShown() and gapHead.visualAlpha == 1)
assert(#plays == gapSounds + 1 and rowFor(b).motion)
Q:Clear()

-- Stages of one quest pause briefly with an idle portrait, without fading it.
a = offer(progressID, 1001); Q:Accept(progressID, 'lab')
b = offer(progressID, 2002, 'p')
c = offer(progressID, 2002, 'c')
local _, stageDuration = WowVoice:SoundPath(progressID, 'a')
tick(now + stageDuration + 1)
gapStarted, gapSounds = now, #plays
assert(Q.gap.deadline == gapStarted + 0.4 and not Q.gap.fadeDuration)
tick(gapStarted + 0.39); gapHead.scripts.OnUpdate(gapHead); step()
assert(gapHead:IsShown() and gapHead.visualAlpha == 1 and #plays == gapSounds)
tick(gapStarted + 0.4); step()
assert(Q.current == b and #plays == gapSounds + 1)
Q:Clear()

-- Next and Play cancel the deadline; the stale gap cannot affect the new audio.
for _, useNext in ipairs({ false, true }) do
    a = offer(ids[1], 1001); Q:Accept(ids[1], 'lab')
    b = offer(ids[2], 2002); Q:Accept(ids[2], 'lab')
    c = offer(ids[3], 3003); Q:Accept(ids[3], 'lab')
    tick(now + gapAudioDuration + 1)
    local deadline = Q.gap.deadline
    tick(now + 0.3); gapHead.scripts.OnUpdate(gapHead)
    local before = #plays
    if useNext then gapPlayer.Next.scripts.OnClick(gapPlayer.Next)
    else rowFor(c).Play.scripts.OnClick(rowFor(c).Play) end
    local selected = useNext and b or c
    assert(Q.current == selected and not Q.gap and #plays == before + 1)
    assert(gapHead:IsShown() and gapHead.visualAlpha == 1)
    tick(deadline + 0.1); gapHead.scripts.OnUpdate(gapHead); step()
    assert(Q.current == selected and #plays == before + 1 and gapHead:IsShown())
    Q:Clear()
end

-- Removing all remaining stages releases a held portrait and stops the gap driver.
a = offer(progressID, 1001); Q:Accept(progressID, 'lab')
b = offer(progressID, 2002, 'p')
tick(now + stageDuration + 1)
assert(Q.gap and not Q.gap.fadeDuration)
Q:Abandon(progressID, 'lab')
assert(not Q.gap and not Q.current and Q:Count() == 0)
tick(now + 1.01); gapHead.scripts.OnUpdate(gapHead); step()
assert(not gapHead:IsShown() and not frames.WowVoiceQuestQueueDriver:IsShown())
Q:Clear()

-- Clearing the stand during the gap cannot start any of its pending recordings.
a = offer(ids[1], 1001); Q:Accept(ids[1], 'lab')
b = offer(ids[2], 2002); Q:Accept(ids[2], 'lab')
tick(now + gapAudioDuration + 1)
gapSounds = #plays
Q:Clear('lab')
tick(now + 2); step()
assert(not Q.gap and not Q.current and Q:Count() == 0 and #plays == gapSounds)

-- A source removed during the gap skips its line without stranding the queue.
a = offer(ids[1], 1001); Q:Accept(ids[1], 'lab')
b = offer(ids[2], 2002); Q:Accept(ids[2], 'lab')
c = offer(ids[3], 3003); Q:Accept(ids[3], 'lab')
tick(now + gapAudioDuration + 1)
local savedSoundPath = WowVoice.SoundPath
WowVoice.SoundPath = function(self, id, ...)
    if id == ids[2] then return nil end
    return savedSoundPath(self, id, ...)
end
tick(Q.gap.deadline); step()
step()
assert(b.status == 'failed' and a.status == 'done')
assert(Q.current == c, 'a missing recording must not strand the queue')
WowVoice.SoundPath = savedSoundPath
Q:Clear()

-- Close during the final visual fade advances once, without waiting for its gap.
a = offer(ids[1], 1001); Q:Accept(ids[1], 'lab')
b = offer(ids[2], 2002); Q:Accept(ids[2], 'lab')
local _, endingDuration = WowVoice:SoundPath(ids[1], 'a')
tick(now + endingDuration + 1)
TalkingHeadRu.Close.scripts.OnClick()
step()
assert(Q.current == b and not Q.paused and Q:Count() == 1 and a.status == 'done')
assert(TalkingHeadRuDB.queueAutoPlay and TalkingHeadRu:IsShown())
Q:Clear()
-- With no remaining queue, closing a standalone preview does not mute future dialogs.
a = offer(ids[1], 1001)
TalkingHeadRu.Close.scripts.OnClick()
b = offer(ids[2], 2002)
assert(Q.current == b)
Q:Clear()

-- Game event wiring uses the same queue with no test ownership tag.
questID = ids[1]
event('QUEST_DETAIL')
assert(Q.current and not Q.current.context.queueOwner)
frames.WowVoiceQuestQueueEvents.scripts.OnEvent(nil, 'QUEST_ACCEPTED', ids[1])
questID = ids[2]
event('QUEST_DETAIL')
assert(Q:Count() == 1)
frames.WowVoiceQuestQueueEvents.scripts.OnEvent(nil, 'QUEST_ACCEPTED', ids[2])
assert(Q:Count() == 2)
frames.WowVoiceQuestQueueEvents.scripts.OnEvent(nil, 'QUEST_REMOVED', ids[2])
step()
assert(Q:Count() == 1)
Q:Clear()
questID = 179

-- Real manual playback replaces test current and retains test waiting lines.
Lab:Accept(ids[1]); Lab:Accept(ids[2])
WowVoice:ReplayQuest(179)
assert(Q.current.context.questId == 179 and not Q.current.context.queueOwner)
local stopsBefore = #stops
Lab:Reset()
assert(#stops == stopsBefore and Q.current.context.questId == 179 and Q:Count() == 1)
Q:Clear()

-- Honor autoplay options; cleanup all substitutions on handler errors.
TalkingHeadRuDB.autoPlayAccept = false
count = #plays
Lab:Accept(ids[1]); assert(#plays == count and Q:Count() == 0)
TalkingHeadRuDB.autoPlayAccept = true
Lab:Reset()
local speak = WowVoice.Speak
WowVoice.Speak = function() error('fixture failure') end
Lab:Accept(ids[1])
assert(GetQuestID == api and WowVoice.CaptureQuestSpeaker == capture and WowVoice.MarkQuestListened == mark)
WowVoice.Speak = speak
Lab:Reset()
soundOK = false
Lab:Accept(ids[1])
assert(not Q.current and Q:Count() == 0)
soundOK = true
Lab:Reset()

-- Long grouped queue uses a bounded scrolling player; harness remains minimal.
SlashCmdList.WOWVOICEQUEUELAB('')
assert(Lab.window.visible)
for i = 1, 15 do Lab:Accept(ids[i]) end
assert(Q:Count() == 15 and #Lab.state:AcceptedQuests() == 15)
assert(frames.WowVoiceQuestQueuePlayer.width == 380 and frames.WowVoiceQuestQueuePlayer.height == 280)
assert(frames.WowVoiceQuestQueueScroll.visible)
local scroll = frames.WowVoiceQueueLabScroll
assert(scroll.maxValue == 10)
scroll:SetValue(10)
local submit, clear
for _, frame in ipairs(allFrames) do
    if frame.text == 'Сдать' and frame.enabled and frame:GetParent().record
        and frame:GetParent().record.id == ids[15] then submit = frame end
    if frame.text == 'Очистить' and frame:GetParent() == Lab.window then clear = frame end
end
assert(submit and clear)
submit.scripts.OnMouseDown(submit); submit.scripts.OnClick(submit)
assert(not Lab.state.quests[ids[15]].accepted)
Lab.window:Hide()
assert(Q:Count() == 0 and not Q.current and #Lab.state.accepted == 0)
assert(not frames.WowVoiceQuestQueuePlayer.visible)
Lab:Open(); Lab:Accept(ids[1]); Lab:Accept(ids[2])
clear.scripts.OnClick(clear)
assert(Lab.window.visible and Q:Count() == 0)

-- One cross per quest removes all stages; portraits never have delete controls.
a = offer(ids[1], 1001); Q:Accept(ids[1], 'lab')
b = offer(progressID, 2002); Q:Accept(progressID, 'lab')
local deletingProgress = offer(progressID, 3003, 'p')
completion = offer(progressID, 3003, 'c')
d = offer(ids[4], 2002); Q:Accept(ids[4], 'lab')
local beforeDelete = #plays
assert(rowFor(b).Remove:IsShown() and not rowFor(deletingProgress).Remove:IsShown() and not rowFor(completion).Remove:IsShown())
for _, frame in ipairs(allFrames) do
    if frame.groupKey and frame:IsShown() then assert(not frame.Remove) end
end
rowFor(b).Remove.scripts.OnClick(rowFor(b).Remove)
assert(not b.group and not deletingProgress.group and not completion.group)
assert(Q.current == a and Q:Count() == 2 and #plays == beforeDelete and d.group)
for _, frame in ipairs(allFrames) do
    if frame.groupKey == 'lab:npc:2002' and frame:IsShown() then assert(not frame.Remove) end
end
Q:Clear()

-- Current quest uses the Play slot for removal only while more stages remain.
a = offer(progressID, 1001); Q:Accept(progressID, 'lab')
b = offer(ids[1], 2002); Q:Accept(ids[1], 'lab')
assert(not rowFor(a).Remove:IsShown() and rowFor(b).Remove:IsShown())
local nextStage = offer(progressID, 3003, 'p')
completion = offer(progressID, 3003, 'c')
assert(rowFor(a).Remove:IsShown() and not rowFor(a).Play:IsShown())
local removePoint, removeAnchor = rowFor(a).Remove:GetPoint()
assert(removePoint == 'CENTER' and removeAnchor == rowFor(a).Play)
finish(); assert(Q.current == nextStage and rowFor(nextStage).Remove:IsShown())
finish(); assert(Q.current == completion and not rowFor(completion).Remove:IsShown())
assert(rowFor(b).Remove:IsShown() and rowFor(b).Remove:GetPoint() == 'LEFT')
Q:Clear()

-- Internal giver cleanup still preserves other givers and record ownership.
a = offer(progressID, 1001); Q:Accept(progressID, 'lab')
offer(progressID, 3003, 'p'); offer(progressID, 3003, 'c')
d = offer(ids[4], 1001); Q:Accept(ids[4], 'lab')
b = offer(ids[1], 2002); Q:Accept(ids[1], 'lab')
Q:Offer(fixture(ids[4], 1001, 'a', 'game')); Q:Accept(ids[4], 'game')
local realWaiting = Q.offers['game:' .. ids[4] .. ':a']
Q:PlayNext(b)
Q:DeleteNPC('lab:npc:1001')
assert(not Q.current and not a.group and not d.group and Q:Count() == 2)
assert(realWaiting.group and b.group, 'keep other NPCs and real/test ownership separate')
step(); assert(Q.current == b)
WowVoice:SetQueueAutoPlay(false)
TalkingHeadRu.Close.scripts.OnClick()
assert(Q.paused and realWaiting.group)
Q:DeleteQuest(realWaiting); step()
assert(not Q.current and Q:Count() == 0 and not Q.paused)
Q:Clear()
WowVoice:SetQueueAutoPlay(true)

-- Play-next immediately reflows at the final width, even while the pointer is on the list.
a = offer(ids[1], 1001); Q:Accept(ids[1], 'lab')
d = offer(ids[4], 2002); Q:Accept(ids[4], 'lab')
local promotedContext = fixture(progressID, 3003)
promotedContext.title = string.rep('Quest ', 8)
Q:Offer(promotedContext); Q:Accept(progressID, 'lab')
b = Q.offers['lab:' .. progressID .. ':a']
local promotedRow = rowFor(b)
assert(promotedRow.height > 26, 'fixture wraps while the link occupies space')
local viewport = promotedRow:GetParent():GetParent()
viewport.mouseOver = true
local beforePromotion = #plays
promotedRow.Next.scripts.OnClick(promotedRow.Next)
promotedRow = rowFor(b)
assert(Q:Waiting() == b and Q.current == a and #plays == beforePromotion)
assert(not promotedRow.Next:IsShown() and promotedRow.height == 26,
    'the first refresh after the click must already fit the title on one line')
assert(not promotedRow.motion, 'Play-next reordering does not animate')
local firstWidth = promotedRow.Title:GetWidth()
viewport.mouseOver = false
WowVoice:RefreshQuestQueuePlayer()
assert(rowFor(b).height == 26 and rowFor(b).Title:GetWidth() == firstWidth,
    'periodic refresh must not change the settled layout')
Q:Clear()

-- Audio switches immediately; natural and manual playback changes slide the remaining list.
for _, manual in ipairs({ false, true }) do
    a = offer(ids[1], 1001); Q:Accept(ids[1], 'lab')
    b = offer(ids[2], 1001); Q:Accept(ids[2], 'lab')
    c = offer(ids[3], 1001); Q:Accept(ids[3], 'lab')
    d = offer(ids[4], 1001); Q:Accept(ids[4], 'lab')
    local selected = manual and c or b
    local oldY = rowFor(selected).viewY
    local animationPlayer = frames.WowVoiceQuestQueuePlayer
    local oldPanelHeight = animationPlayer:GetHeight()
    assert(oldPanelHeight < 280 and oldPanelHeight == rowFor(selected):GetParent():GetHeight() + 28,
        'short queues fit their content instead of reserving the maximum height')
    local audioBefore = #plays
    if manual then rowFor(selected).Play.scripts.OnClick(rowFor(selected).Play) else finish() end
    assert(Q.current == selected and #plays == audioBefore + 1)
    local visual = rowFor(selected)
    assert(visual.motion and visual.viewY == oldY and visual.motion.target < oldY)
    local targetY = visual.motion.target
    assert(animationPlayer:GetHeight() == oldPanelHeight, 'panel shrinking starts with the row animation')
    animationPlayer.scripts.OnUpdate(animationPlayer, 0.1)
    assert(visual.viewY < oldY and visual.viewY > targetY)
    local intermediateHeight = animationPlayer:GetHeight()
    assert(intermediateHeight < oldPanelHeight)
    animationPlayer.scripts.OnUpdate(animationPlayer, 0.1)
    assert(visual.viewY == targetY and not visual.motion)
    assert(animationPlayer:GetHeight() < intermediateHeight
        and animationPlayer:GetHeight() == animationPlayer.contentHeight + 28,
        'the panel shrinks smoothly to fit all remaining entries, even before the last one')
    assert(#plays == audioBefore + 1, 'visual animation never restarts or delays audio')
    Q:Clear()
end

-- Manual browsing holds the visible entries steady across natural and toolbar-Next advances.
for _, manual in ipairs({ false, true }) do
    local records = {}
    for i = 1, 12 do
        records[i] = offer(ids[i], 1000 + i)
        Q:Accept(ids[i], 'lab')
    end
    local p = frames.WowVoiceQuestQueuePlayer
    local slider = frames.WowVoiceQuestQueueScroll
    local view = rowFor(records[6]):GetParent():GetParent()
    local function animate(dt) p.scripts.OnUpdate(p, dt) end
    -- Exercise both wheel and thumb input.
    if manual then slider:SetValue(rowFor(records[6]).viewY)
    else view.scripts.OnMouseWheel(view, -15) end
    local oldOffset = view:GetVerticalScroll()
    assert(oldOffset > 0)
    local screenY = rowFor(records[7]).viewY - oldOffset
    if manual then p.Next.scripts.OnClick(p.Next) else finish() end
    assert(Q.current == records[2])
    animate(0.1)
    assert(math.abs(rowFor(records[7]).viewY - view:GetVerticalScroll() - screenY) < 0.01)
    animate(0.1)
    assert(view:GetVerticalScroll() > 0 and view:GetVerticalScroll() < oldOffset)
    assert(math.abs(rowFor(records[7]).viewY - view:GetVerticalScroll() - screenY) < 0.01,
        'keep the content being read, not a stale numerical scroll offset')
    -- Returning to the top restores following, including smooth row motion.
    slider.scripts.OnMouseWheel(slider, 100)
    assert(view:GetVerticalScroll() == 0)
    finish()
    assert(Q.current == records[3] and rowFor(records[3]).motion)
    animate(0.1)
    assert(view:GetVerticalScroll() == 0 and rowFor(records[3]).motion)
    animate(0.1)
    assert(view:GetVerticalScroll() == 0 and not rowFor(records[3]).motion)
    -- Scrolling during an animation immediately takes control of the viewport.
    finish()
    slider:SetValue(250)
    local heldY = rowFor(records[9]).viewY - view:GetVerticalScroll()
    animate(0.1)
    assert(math.abs(rowFor(records[9]).viewY - view:GetVerticalScroll() - heldY) < 0.01)
    Q:Clear()
    offer(ids[1], 1001); Q:Accept(ids[1], 'lab')
    offer(ids[2], 1002); Q:Accept(ids[2], 'lab')
    assert(view:GetVerticalScroll() == 0, 'a new queue starts at the top')
    Q:Clear()
end

-- Final row slides up while the whole player fades; new work cancels the exit.
for _, revive in ipairs({ false, true }) do
    a = offer(ids[1], 1001); Q:Accept(ids[1], 'lab')
    b = offer(ids[2], 2002); Q:Accept(ids[2], 'lab')
    local finalPlayer = frames.WowVoiceQuestQueuePlayer
    local oldHeight, oldY = finalPlayer:GetHeight(), rowFor(b).viewY
    finish()
    assert(Q.current == b and finalPlayer:IsShown() and finalPlayer.fading)
    assert(finalPlayer:GetHeight() == oldHeight and rowFor(b).viewY == oldY)
    local fadeSounds = #plays
    finalPlayer.scripts.OnUpdate(finalPlayer, 0.1)
    assert(finalPlayer.alpha > 0 and finalPlayer.alpha < 1 and rowFor(b).viewY < oldY)
    assert(finalPlayer:GetHeight() < oldHeight and finalPlayer:GetHeight() > finalPlayer.fading.targetHeight,
        'the panel must shrink during the slide, not keep the empty second slot')
    if revive then
        c = offer(ids[3], 3003); Q:Accept(ids[3], 'lab')
        assert(not finalPlayer.fading and finalPlayer.alpha == 1 and finalPlayer:IsShown())
        finalPlayer.scripts.OnUpdate(finalPlayer, 0.3)
        assert(finalPlayer:IsShown() and Q.current == b)
    else
        finalPlayer.scripts.OnUpdate(finalPlayer, 0.1)
        assert(not rowFor(b).motion and finalPlayer:IsShown())
        assert(finalPlayer:GetHeight() == finalPlayer.fading.targetHeight)
        finalPlayer.scripts.OnUpdate(finalPlayer, 0.05)
        assert(not finalPlayer:IsShown() and Q.current == b)
        WowVoice:RefreshQuestQueuePlayer()
        assert(not finalPlayer:IsShown(), 'periodic refresh must not revive the sole playing row')
    end
    assert(#plays == fadeSounds, 'panel fade must not affect sound')
    Q:Clear()
end

-- Long NPC names and quest titles wrap fully even at the smallest player width.
local previousWrap = nativeWordWrap
nativeWordWrap = true
local longQuest = fixture(ids[1], 8101)
longQuest.title = string.rep('Длинное название задания ', 20)
longQuest.speaker.name = string.rep('Длинное имя квестгивера ', 12)
Q:Offer(longQuest); Q:Accept(ids[1], 'lab')
offer(ids[2], 8102); Q:Accept(ids[2], 'lab')
local previousWidth = TalkingHeadRu:GetWidth()
TalkingHeadRu:SetWidth(350)
WowVoice:RefreshQuestQueuePlayer()
local longRow = rowFor(Q.current)
local _, queueTextSize = longRow.Title:GetFont()
assert(queueTextSize == 11)
assert(longRow.Title.text == longQuest.title and longRow.Title:CanWordWrap() and longRow.Title:CanNonSpaceWrap())
assert(longRow.height >= longRow.Title:GetStringHeight() + 8 and longRow.height > 26)
local longHeader
for _, frame in ipairs(allFrames) do
    if frame.Name and frame.Name.text == longQuest.speaker.name then longHeader = frame end
end
assert(longHeader and longHeader.height >= longHeader.Name:GetStringHeight() + 10 and longHeader.height > 40)
assert(frames.WowVoiceQuestQueueScroll.visible and frames.WowVoiceQuestQueuePlayer.height == 280)
Q:Clear()
TalkingHeadRu:SetWidth(previousWidth)
nativeWordWrap = previousWrap

-- Giver tiles have transparent gaps, contain all their stages, and follow row motion.
a = offer(ids[1], 1001); Q:Accept(ids[1], 'lab')
b = offer(ids[2], 1001); Q:Accept(ids[2], 'lab')
c = offer(ids[3], 2002); Q:Accept(ids[3], 'lab')
local firstTile, secondTile
for _, frame in ipairs(allFrames) do
    if frame.giverKey == 'lab:npc:1001' and frame:IsShown() then firstTile = frame end
    if frame.giverKey == 'lab:npc:2002' and frame:IsShown() then secondTile = frame end
end
assert(firstTile and secondTile and firstTile.last == rowFor(b) and #firstTile.BackgroundParts == 9)
local function tileTop(frame) local _, _, _, _, y = frame:GetPoint(); return -y end
local _, _, _, _, viewportTop = firstTile:GetParent():GetParent():GetPoint()
assert(viewportTop == -28 and tileTop(firstTile) == 0,
    'the first tile starts below the fixed queue toolbar, without an extra inset inside the viewport')
local toolbar = frames.WowVoiceQuestQueuePlayer.Next:GetParent()
assert(-viewportTop + tileTop(firstTile) - toolbar:GetHeight() == 4,
    'alignment keeps the original four-unit gap between the toolbar and first tile')
local function checkGap()
    assert(math.abs(tileTop(secondTile) - tileTop(firstTile) - firstTile:GetHeight() - 8) < 0.001)
    assert(math.abs(tileTop(firstTile) + firstTile:GetHeight()
        - firstTile.last.viewY - firstTile.last:GetHeight() - 6) < 0.001)
end
checkGap()
local tilePlayer = frames.WowVoiceQuestQueuePlayer
for _, part in ipairs(tilePlayer.BackgroundParts) do
    assert(not part.texture.visible, 'a shared background must not fill the gaps between tiles')
end
local clearQueue
for _, frame in ipairs(allFrames) do
    if frame.Label and frame.Label.text == 'Очистить всё' then clearQueue = frame end
end
assert(clearQueue and clearQueue:GetParent():GetParent() == tilePlayer,
    'Clear all belongs to the fixed toolbar outside the scrolling tiles')
finish()
tilePlayer.scripts.OnUpdate(tilePlayer, 0.1); checkGap()
tilePlayer.scripts.OnUpdate(tilePlayer, 0.1); checkGap()
Q:Clear()

-- A narrow fragment of the next tile is trimmed without exceeding the user's height.
WowVoice:SetQuestQueueHeight(382)
local trimRecords = {}
for i = 1, 5 do trimRecords[i] = offer(ids[i], 9100 + i); Q:Accept(ids[i], 'lab') end
local trimPlayer = frames.WowVoiceQuestQueuePlayer
local trimView = rowFor(trimRecords[1]):GetParent():GetParent()
local fourthBottom = rowFor(trimRecords[4]).viewY + rowFor(trimRecords[4]):GetHeight() + 6
assert(trimView:GetHeight() == fourthBottom and 382 - 28 - trimView:GetHeight() <= 24)
assert(trimView:GetHeight() < 382 - 28 and trimPlayer:GetHeight() == trimView:GetHeight() + 28 and WowVoice:GetQuestQueueHeight() == 382,
    'fit the visible area without overwriting the selected maximum')
local settledHeight = trimView:GetHeight()
local _, footerY = clearQueue:GetParent():GetCenter()
for i = 1, 3 do WowVoice:RefreshQuestQueuePlayer() end
assert(trimView:GetHeight() == settledHeight, 'periodic refresh must not oscillate between heights')
trimView.mouseOver = true
trimView.scripts.OnMouseWheel(trimView, -1)
assert(trimView:GetVerticalScroll() > 0 and trimPlayer:GetHeight() <= 382)
assert(trimView:GetHeight() > settledHeight and select(2, clearQueue:GetParent():GetCenter()) == footerY,
    'expanding the viewport after scrolling must not move the Clear all link')
trimView.scripts.OnMouseWheel(trimView, 1)
assert(trimView:GetVerticalScroll() == 0 and trimView:GetHeight() == settledHeight,
    'wheel scrolling updates the fitted edge even while the pointer is over the list')
assert(select(2, clearQueue:GetParent():GetCenter()) == footerY,
    'trimming the next tile fragment must not move the Clear all link')
trimView.scripts.OnMouseWheel(trimView, -100)
assert(math.abs(trimView:GetVerticalScroll() + trimView:GetHeight() - trimPlayer.contentHeight) < 0.001,
    'the last tile remains reachable after shrinking the viewport')
trimView.mouseOver = false
Q:Clear()
for i = 1, 3 do offer(ids[i], 9200 + i); Q:Accept(ids[i], 'lab') end
local beforeRemovalHeight = trimPlayer:GetHeight()
local _, beforeRemovalFooterY = clearQueue:GetParent():GetCenter()
Q:DeleteNPC('lab:npc:9203')
assert(Q:Count() == 2 and trimPlayer:GetHeight() < beforeRemovalHeight)
assert(select(2, clearQueue:GetParent():GetCenter()) == beforeRemovalFooterY,
    'removing a giver tile must not move the fixed queue toolbar')
Q:Clear()
WowVoice:SetQuestQueueHeight(280)

-- Portraits must also resolve NPCs absent from the real journal and local display tables.
local logCount, logInfo = C_QuestLog.GetNumQuestLogEntries, C_QuestLog.GetInfo
C_QuestLog.GetNumQuestLogEntries = function() return 0 end
C_QuestLog.GetInfo = function() return nil end
local first, second = fixture(ids[1], 8101), fixture(ids[2], 8102)
first.speaker.displayID, second.speaker.displayID = nil, nil
Q:Offer(first); Q:Accept(ids[1], 'lab')
Q:Offer(second); Q:Accept(ids[2], 'lab')
assert(WowVoice:GetQuestQueuePortraitDisplay(first.speaker) == 18101,
    'current NPC should reuse the already loaded talking head model')
assert(not WowVoice:GetQuestQueuePortraitDisplay(second.speaker))
local sounds = #plays
for i = 1, 360 do
    now = now + 1/60
    local work = frames.WowVoiceWorkFrame.scripts.OnUpdate
    if work then work() end
end
assert(WowVoice:GetQuestQueuePortraitDisplay(second.speaker) == 18102,
    'waiting NPC outside the journal must be requested by the bounded warmup worker')
WowVoice:RefreshQuestQueuePlayer()
local portrait
for _, frame in ipairs(allFrames) do
    if frame.Name and frame.Portrait and frame.Name.text == 'NPC 8102' then portrait = frame.Portrait end
end
assert(portrait and portrait.displayID == 18102, 'replace the question mark with the resolved 2D portrait')
assert(#plays == sounds, 'portrait loading must not restart or advance audio')
Q:Clear()
C_QuestLog.GetNumQuestLogEntries, C_QuestLog.GetInfo = logCount, logInfo
WowVoiceFrame:SetScript('OnEvent', originalHandler)
print('PASS: shared grouped queue, accept-only waiting, NPC order, abandonment, completion, close/resume, manual priority, portraits/player, bounded scroll and isolated lab cleanup')

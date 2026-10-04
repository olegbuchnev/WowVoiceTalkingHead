-- Runs against the public TOC before the development harness is loaded.
local WV, Q = WowVoice, WowVoice.questQueue
assert(Q.enabled and not WowVoiceQueueLab and not SLASH_WOWVOICEQUEUELAB1)
WowVoiceDB = { autoPlay = false, autoPlayAccept = false, autoPlayTurnIn = false,
    autoPlayAcceptDefaultOnApplied = true, volume = 0.6 }
event('ADDON_LOADED')
assert(WowVoiceDB.autoPlay and WowVoiceDB.autoPlayAccept and WowVoiceDB.autoPlayTurnIn
    and WowVoiceDB.playlistAutoPlayApplied == 2 and WowVoiceDB.volume == 0.6)
assert(WowVoiceDB.queueAutoPlay == true, 'continuous playback defaults on once')
WowVoiceDB.queueAutoPlay = false
event('ADDON_LOADED')
assert(WowVoiceDB.queueAutoPlay == false, 'a later autoplay choice survives default initialization')
WowVoiceDB.queueAutoPlay = true
-- The previously shipped test archive already set the boolean migration flag.
WowVoiceDB.playlistAutoPlayApplied = true
WowVoiceDB.autoPlay, WowVoiceDB.autoPlayAccept, WowVoiceDB.autoPlayTurnIn = false, false, false
WowVoiceDB.trackerButtons, WowVoiceDB.queueDescriptionsOnly = false, true
event('ADDON_LOADED')
assert(WowVoiceDB.autoPlay and WowVoiceDB.autoPlayAccept and WowVoiceDB.autoPlayTurnIn
    and WowVoiceDB.playlistAutoPlayApplied == 2)
assert(WowVoiceDB.trackerButtons == nil and WowVoiceDB.queueDescriptionsOnly and WowVoiceDB.volume == 0.6,
    'playback migration preserves active preferences and removes the obsolete tracker setting')
WowVoiceDB.queueDescriptionsOnly = false
WV:SetAutoPlayEnabled(false)
WV:SetAutoPlayAcceptEnabled(false)
WV:SetAutoPlayTurnInEnabled(false)
event('ADDON_LOADED')
assert(not WowVoiceDB.autoPlay and not WowVoiceDB.autoPlayAccept and not WowVoiceDB.autoPlayTurnIn,
    'migration must not override a later opt-out')
WV:SetAutoPlayEnabled(true)
WV:SetAutoPlayAcceptEnabled(true)
WV:SetAutoPlayTurnInEnabled(true)

local ids = {}
for name in pairs(WowVoiceDur) do
    local id = tonumber(name:match('^(%d+)a$'))
    if id and WowVoiceDur[id .. 'p'] and WowVoiceDur[id .. 'c'] then ids[#ids + 1] = id end
end
table.sort(ids)
assert(#ids >= 4)
local function offer(index, section, npc, owner)
    local id = ids[index]
    Q:Offer({ questId = id, section = section or 'a', title = 'Quest ' .. id,
        text = 'Actual captured dialog', queueOwner = owner,
        speaker = { npcID = npc or index, name = 'NPC ' .. (npc or index), displayID = 1234 } })
    if not section or section == 'a' then Q:Accept(id, owner) end
    return Q.offers[(owner or 'game') .. ':' .. id .. ':' .. (section or 'a')]
end
local function step()
    local frame = frames.WowVoiceQuestQueueDriver
    if frame.visible then frame.scripts.OnUpdate() end
end
local function resetRuntime(keepPreferences)
    if not keepPreferences then WowVoiceDB.queueAutoPlay = true end
    Q:Clear()
    Q.groups, Q.offers, Q.completed, Q.removals = {}, {}, {}, {}
    Q.current, Q.nextRecord, Q.gap, Q.loggingOut = nil, nil, nil, nil
    Q.paused = false
    frames.WowVoiceQuestQueueDriver:Hide()
end
local function restore(saved, elapsed)
    resetRuntime(true)
    WowVoiceQueueDB = saved
    serverNow = saved.savedAt + (elapsed or 0)
    Q:RestoreSession()
end

-- Real event routing works without /tt: viewing, accepting and turn-in do not interrupt.
assert(not WowVoiceTalkingHead, 'exercise paused restore before any head has been created')
WowVoiceQueueDB = { version = 1, savedAt = serverNow, paused = true, records = {
    { context = { questId = ids[1], section = 'a', title = 'Saved quest' }, giver = { npcID = 100 } }
} }
local silent = #plays
Q:RestoreSession()
assert(frames.WowVoiceQuestQueuePlayer:IsShown() and not WowVoiceTalkingHead:IsShown()
    and #plays == silent and Q.paused, 'paused queue is accessible immediately after a fresh login')
resetRuntime()
questID = ids[1]
event('QUEST_DETAIL')
local first = Q.current
frames.WowVoiceQuestQueueEvents.scripts.OnEvent(nil, 'QUEST_ACCEPTED', 1, ids[1])
questID = ids[2]
event('QUEST_DETAIL')
frames.WowVoiceQuestQueueEvents.scripts.OnEvent(nil, 'QUEST_ACCEPTED', 2, ids[2])
assert(Q.current == first and Q:Count() == 2)
event('QUEST_COMPLETE')
assert(Q.current == first and Q:Count() == 3)
resetRuntime()

-- Accepting an offer opened during a manual replay starts a lone line without
-- briefly exposing an idle playlist during the transport's old-sound cleanup.
local originalMusic = PlayMusic
function PlayMusic(path)
    if soundOK then plays[#plays + 1] = {file = path, channel = 'Music'} end
    return soundOK
end
for _, background in ipairs({'0', '1'}) do
    cvars.Sound_EnableSoundWhenGameIsInBG = background
    for _, afterFade in ipairs({false, true}) do
        for _, fail in ipairs({false, true}) do
            resetRuntime()
            assert(WV:ReplayQuest(ids[1]))
            questID = ids[2]
            event('QUEST_DETAIL')
            assert(Q:Count() == 1 and Q.current.context.questId == ids[1])
            local opened = Q.offers['game:' .. ids[2] .. ':a']
            assert(opened and not opened.group and not opened.started)
            local duration = select(2, WV:SoundPath(ids[1], 'a'))
            tick(now + duration + 0.1)
            assert(Q:Count() == 0 and not Q.current)
            if afterFade then
                tick(now + 2)
                WowVoiceTalkingHead.scripts.OnUpdate()
            end
            local player = frames.WowVoiceQuestQueuePlayer
            assert(not player:IsShown())
            local show, flashes = player.Show, 0
            function player:Show()
                if not self:IsShown() then flashes = flashes + 1 end
                return show(self)
            end
            soundOK = not fail
            frames.WowVoiceQuestQueueEvents.scripts.OnEvent(nil, 'QUEST_ACCEPTED', 2, ids[2])
            soundOK, player.Show = true, show
            assert(flashes == 0 and not player:IsShown(),
                'accepting the sole pending description must never flash the playlist')
            if fail then assert(Q:Count() == 0 and not Q.current and opened.status == 'failed')
            else assert(Q:Count() == 1 and Q.current == opened and opened.status == 'playing') end
        end
    end
end
PlayMusic = originalMusic
cvars.Sound_EnableSoundWhenGameIsInBG = '1'
resetRuntime()
print('PASS: acceptance after manual replay never flashes a single-line playlist, both transports, head fade and failed playback')

-- Persist the current line before Core stops it, exact quest order, real receiver,
-- giver grouping, pending completion and the explicit "next" priority.
local a = offer(1, 'a', 100)
offer(2, 'a', 200)
local c = offer(3, 'a', 300)
offer(1, 'p', 999); offer(1, 'c', 999)
Q:Event('QUEST_TURNED_IN', ids[1])
Q:PlayNext(c)
offer(4, 'a', 444, 'lab')
local _, interruptedDuration = WV:SoundPath(ids[1], 'a')
tick(now + interruptedDuration * 0.6)
event('PLAYER_LOGOUT')
local saved = WowVoiceQueueDB
assert(saved and #saved.records == 5 and saved.records[1].context.questId == ids[1])
assert(saved.records[1].context ~= a.context and saved.records[1].context.speaker ~= a.context.speaker)
assert(saved.records[2].context.section == 'p' and saved.records[2].context.speaker.npcID == 999)
assert(saved.records[2].giver.npcID == 100 and saved.completed[ids[1]])
event('PLAYER_LOGOUT')
assert(WowVoiceQueueDB == saved, 'a repeated logout event cannot replace the pre-stop snapshot')
resetRuntime()
WowVoiceQueueDB = saved
serverNow = saved.savedAt + 299
local sounds = #plays
frames.WowVoiceQuestQueueEvents.scripts.OnEvent(nil, 'PLAYER_ENTERING_WORLD')
assert(Q:Count() == 5 and not Q.current and #plays == sounds and not WowVoiceQueueDB)
assert(Q.groups[1].speaker.npcID == 100 and Q.nextRecord.context.questId == ids[3])
assert(Q.completed['game:' .. ids[1]])
-- Entering the world is not yet permission to start audio. Loading time and
-- time played before logout must not consume the restarted line's duration.
step()
assert(not Q.current and #plays == sounds, 'restored playback waits for the loading screen')
tick(now + 40)
step()
assert(not Q.current and #plays == sounds, 'loading cannot start or expire a restored line')
frames.WowVoiceQuestQueueEvents.scripts.OnEvent(nil, 'LOADING_SCREEN_DISABLED')
assert(not Q.current and #plays == sounds, 'audio starts on the frame after loading completes')
local restoredModel = frames.WowVoiceTalkingHead.Model
local completeLoad = restoredModel.CompleteLoad
function restoredModel:CompleteLoad(display)
    completeLoad(self, display)
    self.animation, self.paused = 0, true -- Native load finalization after its callback.
end
step()
local restartedAt = now
assert(Q.current.context.questId == ids[1] and #plays == sounds + 1, 'interrupted line restarts once in-world')
assert(Q.current.context.text == 'Actual captured dialog')
frames.WowVoiceTalkingHead.scripts.OnUpdate()
assert(restoredModel.animation == 60 and not restoredModel.paused,
    'playlist restored after reload must restart its model animation after native loading')
restoredModel.CompleteLoad = completeLoad
frames.WowVoiceQuestQueueEvents.scripts.OnEvent(nil, 'PLAYER_ENTERING_WORLD')
frames.WowVoiceQuestQueueEvents.scripts.OnEvent(nil, 'LOADING_SCREEN_DISABLED')
step()
assert(#plays == sounds + 1, 'zoning cannot restart a restored playlist')
tick(restartedAt + interruptedDuration - 0.01)
frames.WowVoiceTalkingHead.scripts.OnUpdate()
assert(Q.current and Q.current.status == 'playing' and not Q.gap
    and WowVoiceTalkingHead.Progress.value < 1,
    'the restarted line and head retain the full duration regardless of prior playback and loading')
tick(restartedAt + interruptedDuration + WowVoiceDB.tail + 0.01)
assert(Q.gap and Q.current.status == 'done' and #plays == sounds + 1,
    'only a complete new duration finishes restored audio')

-- Exactly five minutes expires; normal play has no age limit.
restore(saved, 300)
step(); assert(Q:Count() == 0 and not Q.current and not WowVoiceQueueDB)
restore(saved, -1)
assert(Q:Count() == 0)
restore(saved, 0)
step(); serverNow = serverNow + 3600
assert(Q:Count() == 5 and Q.current)
event('PLAYER_LOGOUT')
assert(WowVoiceQueueDB.savedAt == serverNow)

-- Closing the head with autoplay disabled drops the line and preserves the pause.
resetRuntime()
offer(1); offer(2)
WV:SetQueueAutoPlay(false)
WowVoiceTalkingHead.Close.scripts.OnClick()
event('PLAYER_LOGOUT')
local paused = WowVoiceQueueDB
assert(paused.paused and #paused.records == 1 and paused.records[1].context.questId == ids[2])
restore(paused, 10)
sounds = #plays
step(); assert(Q.paused and not Q.current and #plays == sounds and Q:Count() == 1)
assert(Q:Start(Q:Waiting()) and Q.current.context.questId == ids[2])

-- Reload immediately after a skip resumes the successor and retains autoplay.
resetRuntime()
local skipped = offer(1)
offer(2)
WowVoiceTalkingHead.Close.scripts.OnClick()
assert(skipped.status == 'skipped' and not Q.current and not Q.paused and WowVoiceDB.queueAutoPlay)
event('PLAYER_LOGOUT')
local afterSkip = WowVoiceQueueDB
assert(not afterSkip.paused and #afterSkip.records == 1 and afterSkip.records[1].context.questId == ids[2])
restore(afterSkip, 1); step()
assert(Q.current.context.questId == ids[2] and WowVoiceDB.queueAutoPlay)

-- Completed audio in the automatic gap must not be replayed.
resetRuntime()
offer(1); offer(2)
local _, duration = WV:SoundPath(ids[1], 'a')
tick(now + duration + 1)
assert(Q.gap and Q.current.status == 'done')
event('PLAYER_LOGOUT')
local gap = WowVoiceQueueDB
assert(#gap.records == 1 and gap.records[1].context.questId == ids[2] and not gap.paused)
restore(gap, 1); step()
assert(Q.current.context.questId == ids[2])

-- Autoplay can be disabled after the current line, with no audio restart or cut.
resetRuntime()
local running = offer(1)
local waiting = offer(2)
local autoplayButton = frames.WowVoiceQuestQueuePlayer.Autoplay
assert(autoplayButton and autoplayButton.Label.text == 'Автовоспроизведение'
    and autoplayButton.Check:GetChecked())
local played, stopped = #plays, #stops
GameTooltip:SetOwner(UIParent, 'ANCHOR_RIGHT')
GameTooltip:AddLine('Native tooltip')
GameTooltip:Show()
autoplayButton.scripts.OnEnter(autoplayButton)
autoplayButton.Check.scripts.OnEnter(autoplayButton.Check)
assert(GameTooltip.visible and GameTooltip:IsOwned(UIParent) and GameTooltip.lines[1] == 'Native tooltip',
    'new queue controls have no tooltip and leave native tooltips untouched')
autoplayButton.Check.scripts.OnLeave(autoplayButton.Check)
autoplayButton.Check.scripts.OnClick(autoplayButton.Check)
assert(Q.paused and Q.current == running and running.status == 'playing'
    and #plays == played and #stops == stopped, 'pause only blocks automatic advancement')
assert(autoplayButton.Label.text == 'Автовоспроизведение' and not autoplayButton.Check:GetChecked(),
    'pending pause keeps the label and unchecks autoplay')
autoplayButton.scripts.OnLeave(autoplayButton)
assert(GameTooltip.visible and GameTooltip:IsOwned(UIParent))
GameTooltip:Hide()
autoplayButton.scripts.OnClick(autoplayButton)
assert(not Q.paused and autoplayButton.Check:GetChecked() and Q.current == running
    and #plays == played and #stops == stopped, 'toggling off does not restart current audio')
autoplayButton.scripts.OnClick(autoplayButton)
offer(3, 'c')
assert(Q.paused and Q.current == running and Q:Count() == 3,
    'new quest events preserve the requested pause')
local _, pauseDuration = WV:SoundPath(ids[1], 'a')
tick(now + pauseDuration + 1); step()
assert(Q.paused and not Q.current and not Q.gap and running.status == 'done'
    and Q:Waiting() == waiting and #plays == played, 'finished line is removed without starting its successor')
assert(autoplayButton.Label.text == 'Автовоспроизведение' and not autoplayButton.Check:GetChecked())
assert(frames.WowVoiceQuestQueuePlayer:IsShown(), 'paused playlist remains visible')
Q:SaveSession()
local autoplayPaused = WowVoiceQueueDB
assert(autoplayPaused.paused and #autoplayPaused.records == 2)
restore(autoplayPaused, 1); step()
assert(Q.paused and not Q.current and #plays == played
    and not autoplayButton.Check:GetChecked(), 'disabled autoplay survives reload')
autoplayButton.scripts.OnClick(autoplayButton)
assert(not Q.paused and Q.current.context.questId == ids[2] and #plays == played + 1
    and autoplayButton.Check:GetChecked(), 'enabling autoplay starts the next waiting line once')

-- A pause clicked in the automatic gap cannot strand/replay the finished line.
resetRuntime(); running = offer(1); waiting = offer(2)
local _, gapDuration = WV:SoundPath(ids[1], 'a')
tick(now + gapDuration + 1)
assert(Q.gap and Q.current == running and running.status == 'done')
played, stopped = #plays, #stops
autoplayButton.scripts.OnClick(autoplayButton)
assert(Q.paused and not Q.current and not Q.gap and Q:Count() == 1
    and not autoplayButton.Check:GetChecked() and #stops == stopped)
tick(now + 2); step()
WowVoiceTalkingHead.scripts.OnUpdate(WowVoiceTalkingHead, 2)
assert(not WowVoiceTalkingHead:IsShown() and #plays == played,
    'head fades normally while the paused queue waits')
Q:Event('QUEST_REMOVED', ids[2]); step()
assert(Q:Count() == 0 and not Q.paused, 'abandonment still clears waiting quests while paused')
offer(3)
assert(Q.current.context.questId == ids[3], 'an empty queue cannot leave a stale pause behind')

-- Removing a requested pause before completion retains normal automatic playback.
resetRuntime(); offer(1); waiting = offer(2)
Q:SetPaused(true); Q:SetPaused(false)
tick(now + pauseDuration + 1)
assert(Q.gap and not Q.paused)
tick(Q.gap.deadline); step()
assert(Q.current == waiting)
Q:SetPaused(true); Q:Clear()
assert(Q:Count() == 0 and not Q.paused and not frames.WowVoiceQuestQueuePlayer:IsShown())
print('PASS: autoplay preserves current audio, toggles before completion, resumes once, persists and handles gaps/quest events')

-- The fixed Next control plays one line at a time when autoplay is disabled.
resetRuntime(); running = offer(1); waiting = offer(2)
local lastWaiting = offer(3)
local nextControl = frames.WowVoiceQuestQueuePlayer.Next
local toolbar = autoplayButton:GetParent()
local toolbarY = select(2, toolbar:GetCenter())
assert(nextControl:IsEnabled() and autoplayButton:GetWidth() + nextControl:GetWidth()
    + toolbar.Clear:GetWidth() + 24 <= toolbar:GetWidth(), 'toolbar controls fit at the existing player width')
GameTooltip:SetOwner(UIParent, 'ANCHOR_RIGHT'); GameTooltip:Show()
nextControl.scripts.OnEnter(nextControl); nextControl.scripts.OnLeave(nextControl)
assert(GameTooltip.visible and GameTooltip:IsOwned(UIParent), 'Next never creates or hides a tooltip')
GameTooltip:Hide()
Q:SetPaused(true)
played = #plays
nextControl.scripts.OnClick(nextControl)
assert(Q.current == waiting and Q.paused and #plays == played + 1 and running.status == 'skipped',
    'Next skips the current line without enabling autoplay')
assert(select(2, toolbar:GetCenter()) == toolbarY, 'the toolbar stays fixed when the list gets shorter')
local _, nextDuration = WV:SoundPath(ids[2], 'a')
tick(now + nextDuration + 1); step()
assert(Q.paused and not Q.current and Q:Waiting() == lastWaiting and nextControl:IsEnabled())
assert(frames.WowVoiceQuestQueuePlayer:IsShown(), 'the sole waiting line remains accessible')
nextControl.scripts.OnClick(nextControl)
assert(Q.current == lastWaiting and Q.paused and #plays == played + 2 and not nextControl:IsEnabled(),
    'Next from the paused queue starts only the last waiting line and then disables itself')
local lastPlayer = frames.WowVoiceQuestQueuePlayer
assert(lastPlayer.fading, 'the sole playing line fades even with autoplay disabled')
lastPlayer.scripts.OnUpdate(lastPlayer, 0.25)
assert(not lastPlayer:IsShown() and Q.current == lastWaiting and WowVoiceTalkingHead:IsShown())
WV:RefreshQuestQueuePlayer()
assert(not lastPlayer:IsShown(), 'refresh does not reveal the last playing line')
local _, lastDuration = WV:SoundPath(ids[3], 'a')
tick(now + lastDuration + 1); step()
assert(Q:Count() == 0 and #plays == played + 2)

resetRuntime(); running = offer(1); waiting = offer(2)
nextControl.scripts.OnClick(nextControl)
assert(Q.current == waiting and not Q.paused, 'Next preserves enabled autoplay too')
tick(now + nextDuration + 1); step()
assert(Q:Count() == 0 and not nextControl:IsEnabled())
resetRuntime()
print('PASS: fixed Next skips or starts one line, preserves autoplay mode and disables without a successor')

-- Playlist buttons and whole-row clicks play one line without lifting pause.
local function playlistRow(record)
    for _, frame in ipairs(allFrames) do
        if frame.record == record and frame.Play then return frame end
    end
    error('Missing playlist row')
end
resetRuntime(); offer(1)
local single = offer(2)
local singleProgress = offer(2, 'p')
local singleCompletion = offer(2, 'c')
local later = offer(3)
Q:SetPaused(true)
tick(now + pauseDuration + 1); step()
played = #plays
local singleRow = playlistRow(single)
singleRow.Play.scripts.OnClick(singleRow.Play)
assert(Q.current == single and Q.paused and #plays == played + 1,
    'Play in a paused playlist starts one line and preserves pause')
local _, singleDuration = WV:SoundPath(ids[2], 'a')
tick(now + singleDuration + 1); step()
assert(not Q.current and not Q.gap and Q.paused and #plays == played + 1
    and singleProgress.group and singleCompletion.group and later.group,
    'single playback does not advance to the next stage of the same quest')
local progressRow = playlistRow(singleProgress)
progressRow.scripts.OnClick(progressRow)
assert(Q.current == singleProgress and Q.paused and #plays == played + 2,
    'clicking the quest title also preserves pause')
local laterRow = playlistRow(later)
laterRow.Play.scripts.OnClick(laterRow.Play)
assert(Q.current == later and Q.paused and #plays == played + 3
    and singleCompletion.group, 'replacing a playing line in the paused playlist keeps pause')
local _, laterDuration = WV:SoundPath(ids[3], 'a')
tick(now + laterDuration + 1); step()
assert(Q.paused and not Q.current and Q:Waiting() == singleCompletion)
autoplayButton.scripts.OnClick(autoplayButton)
assert(not Q.paused and Q.current == singleCompletion and #plays == played + 4,
    'enabling autoplay resumes continuous playback')

-- Playing from an active playlist retains its existing continuous behavior.
resetRuntime(); offer(1); single = offer(2); later = offer(3)
singleRow = playlistRow(single)
singleRow.scripts.OnClick(singleRow)
assert(not Q.paused and Q.current == single)
tick(now + singleDuration + 1)
assert(Q.gap)
tick(Q.gap.deadline); step()
assert(Q.current == later and not Q.paused)

-- Missing audio during single playback must leave the remaining queue paused.
resetRuntime(); offer(1); single = offer(2); later = offer(3)
Q:SetPaused(true); tick(now + pauseDuration + 1); step()
singleRow = playlistRow(single)
soundOK = false
singleRow.Play.scripts.OnClick(singleRow.Play)
soundOK = true
step()
assert(Q.paused and not Q.current and Q:Waiting() == later,
    'a failed manual line cannot resume the rest of a paused queue')
resetRuntime()
print('PASS: paused playlist supports one-click single-line playback, same-quest stages, replacement, failure and continuous resume')

-- Per-type switches only stop new entries; pending lines still play and restore.
for _, section in ipairs({'a', 'p', 'c'}) do
    resetRuntime()
    WV:SetAutoPlayAcceptEnabled(true); WV:SetAutoPlayTurnInEnabled(true)
    offer(1)
    local pending = offer(2, section)
    Q:Offer({questId=ids[4], section='a', title='Opened, not accepted'})
    if section == 'a' then WV:SetAutoPlayAcceptEnabled(false)
    else WV:SetAutoPlayTurnInEnabled(false) end
    local count = Q:Count()
    offer(3, section)
    assert(Q:Count() == count and pending.group, 'turning off a type blocks new entries, preserves old ones')
    if section == 'a' then
        Q:Accept(ids[4])
        assert(Q:Count() == count, 'an unaccepted offer must not become a new queued description after disabling')
    end
    Q:SaveSession()
    local retained = WowVoiceQueueDB
    local played = #plays
    assert(Q:Start(pending) and Q.current == pending and #plays == played+1,
        'manual Play of an already queued line must still work')
    restore(retained, 1)
    assert(Q:Count() == count, 'reload preserves lines of a now-disabled type')
    step()
    assert(Q.current.context.questId == ids[1])
    local _, firstDuration = WV:SoundPath(ids[1], 'a')
    tick(now + firstDuration + 1)
    assert(Q.gap)
    tick(now + 1.1); step()
    assert(Q.current and Q.current.context.questId == ids[2] and Q.current.context.section == section,
        'automatic playback of an already queued line must still work')
    WV:SetAutoPlayEnabled(false)
    assert(Q:Count() == 1 and Q.current.context.questId == ids[2],
        'the master switch also preserves already queued playback')
    WV:SetAutoPlayEnabled(true)
end
WV:SetAutoPlayAcceptEnabled(true); WV:SetAutoPlayTurnInEnabled(true)
print('PASS: per-type switches block only new entries; queued a/p/c play manually, advance automatically and survive reload')

-- Clear, missing audio and harness records cannot revive stale work.
resetRuntime(); offer(1, 'a', 1, 'lab')
event('PLAYER_LOGOUT'); assert(not WowVoiceQueueDB)
resetRuntime(); offer(1); offer(2); Q:Clear()
event('PLAYER_LOGOUT'); assert(not WowVoiceQueueDB)
restore(saved, 1)
soundOK = false
for _ = 1, 8 do step() end
assert(Q:Count() == 0 and not Q.current)
soundOK = true
resetRuntime()
WV:SetAutoPlayEnabled(false)
WV:SetAutoPlayAcceptEnabled(false); WV:SetAutoPlayTurnInEnabled(false)
WV:SetQueueDescriptionsOnly(true)
WowVoiceQueueDB = saved; Q:RestoreSession()
assert(Q:Count() == 5 and not WowVoiceQueueDB, 'all existing stages restore regardless of admission settings')
step()
assert(Q.current.context.questId == ids[1] and Q.current.context.section == 'a')
offer(4); offer(4, 'p'); offer(4, 'c')
assert(Q:Count() == 5, 'master-off blocks all new quest entries')
Q:SaveSession()
assert(WowVoiceQueueDB and #WowVoiceQueueDB.records == 5, 'master-off does not disable saving')
assert(Q:Next() and Q.current.context.section == 'p', 'manual Next works with all admission switches off')
local _, progressDuration = WV:SoundPath(ids[1], 'p')
tick(now + progressDuration + 1)
assert(Q.gap)
tick(now + 1.1); step()
assert(Q.current and Q.current.context.section == 'c', 'automatic advance works with all admission switches off')
WV:SetAutoPlayEnabled(true)
WV:SetAutoPlayAcceptEnabled(true); WV:SetAutoPlayTurnInEnabled(true)
WV:SetQueueDescriptionsOnly(false)
print('PASS: master-off and descriptions-only preserve pending audio, manual/automatic advancement and session persistence')

-- The toolbar choice survives empty queues and reload; manual launches keep it.
resetRuntime(); running = offer(1); waiting = offer(2)
played, stopped = #plays, #stops
autoplayButton.Check.scripts.OnClick(autoplayButton.Check)
assert(WowVoiceDB.queueAutoPlay == false and Q.paused and Q.current == running
    and #plays == played and #stops == stopped)
Q:Clear()
assert(Q:Count() == 0 and not Q.paused and WowVoiceDB.queueAutoPlay == false,
    'clearing the queue does not erase the remembered mode')
played = #plays
running = offer(1); waiting = offer(2)
assert(Q.current == running and Q.paused and #plays == played + 1
    and not autoplayButton.Check:GetChecked(), 'a new queue starts its first line in the remembered mode')
tick(now + pauseDuration + 1); step()
assert(not Q.current and Q.paused and Q:Waiting() == waiting and #plays == played + 1)
Q:SaveSession()
local rememberedSession = WowVoiceQueueDB
event('ADDON_LOADED')
assert(WowVoiceDB.queueAutoPlay == false)
restore(rememberedSession, 1); step()
assert(WowVoiceDB.queueAutoPlay == false and Q.paused and not Q.current and #plays == played + 1)
nextControl.scripts.OnClick(nextControl)
assert(Q.current.context.questId == ids[2] and Q.paused and #plays == played + 2)
tick(now + nextDuration + 1); step()
assert(Q:Count() == 0 and WowVoiceDB.queueAutoPlay == false)
running = offer(3); waiting = offer(4)
assert(Q.current == running and Q.paused)
assert(WV:PlayQueuedQuest({ context = { questId = ids[1], section = 'a', title = 'Manual journal replay',
    speaker = { npcID = 100, name = 'NPC', displayID = 1234 } } }))
assert(Q.current.context.questId == ids[1] and Q.paused and WowVoiceDB.queueAutoPlay == false,
    'manual playback outside the playlist respects the remembered advancement mode')
tick(now + pauseDuration + 1); step()
assert(not Q.current and Q.paused and Q:Waiting() == waiting)
played = #plays
autoplayButton.scripts.OnClick(autoplayButton)
assert(WowVoiceDB.queueAutoPlay == true and not Q.paused and Q.current == waiting and #plays == played + 1)
Q:Clear()
running = offer(1); waiting = offer(2)
assert(not Q.paused and autoplayButton.Check:GetChecked())
tick(now + pauseDuration + 1); step()
assert(Q.gap)
tick(Q.gap.deadline); step()
assert(Q.current == waiting and not Q.paused)
resetRuntime()
print('PASS: toolbar autoplay choice persists across empty queues and reload, preserves first-line launch, single playback and continuous resume')
resetRuntime()
WowVoiceQueueDB = { version = 1, savedAt = serverNow, records = { false, { context = {} } } }
Q:RestoreSession(); assert(Q:Count() == 0)
print('PASS: public playlist, one-time autoplay migration, per-character logout snapshot, 5-minute expiry, paused/gap restore, ordering and stand exclusion')

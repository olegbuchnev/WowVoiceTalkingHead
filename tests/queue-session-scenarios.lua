-- Runs against the public TOC before the development harness is loaded.
local WV, Q = WowVoice, WowVoice.questQueue
assert(Q.enabled and not WowVoiceQueueLab and not SLASH_WOWVOICEQUEUELAB1)
WowVoiceDB = { autoPlay = false, autoPlayAccept = false, autoPlayTurnIn = false,
    autoPlayAcceptDefaultOnApplied = true, volume = 0.6 }
event('ADDON_LOADED')
assert(WowVoiceDB.autoPlay and WowVoiceDB.autoPlayAccept and WowVoiceDB.autoPlayTurnIn
    and WowVoiceDB.playlistAutoPlayApplied == 2 and WowVoiceDB.volume == 0.6)
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
local function resetRuntime()
    Q:Clear()
    Q.groups, Q.offers, Q.completed, Q.removals = {}, {}, {}, {}
    Q.current, Q.nextRecord, Q.gap, Q.loggingOut = nil, nil, nil, nil
    Q.paused = false
    frames.WowVoiceQuestQueueDriver:Hide()
end
local function restore(saved, elapsed)
    resetRuntime()
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

-- Persist the current line before Core stops it, exact quest order, real receiver,
-- giver grouping, pending completion and the explicit "next" priority.
local a = offer(1, 'a', 100)
offer(2, 'a', 200)
local c = offer(3, 'a', 300)
offer(1, 'p', 999); offer(1, 'c', 999)
Q:Event('QUEST_TURNED_IN', ids[1])
Q:PlayNext(c)
offer(4, 'a', 444, 'lab')
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
step()
assert(Q.current.context.questId == ids[1] and #plays == sounds + 1, 'interrupted line restarts once in-world')
assert(Q.current.context.text == 'Actual captured dialog')
frames.WowVoiceQuestQueueEvents.scripts.OnEvent(nil, 'PLAYER_ENTERING_WORLD')
step()
assert(#plays == sounds + 1, 'zoning cannot restart a restored playlist')

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

-- Closing the head before exit drops that line and preserves a paused queue.
resetRuntime()
offer(1); offer(2)
WV:Silence('head close')
event('PLAYER_LOGOUT')
local paused = WowVoiceQueueDB
assert(paused.paused and #paused.records == 1 and paused.records[1].context.questId == ids[2])
restore(paused, 10)
sounds = #plays
step(); assert(Q.paused and not Q.current and #plays == sounds and Q:Count() == 1)
assert(Q:Start(Q:Waiting()) and Q.current.context.questId == ids[2])

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
resetRuntime()
WowVoiceQueueDB = { version = 1, savedAt = serverNow, records = { false, { context = {} } } }
Q:RestoreSession(); assert(Q:Count() == 0)
print('PASS: public playlist, one-time autoplay migration, per-character logout snapshot, 5-minute expiry, paused/gap restore, ordering and stand exclusion')

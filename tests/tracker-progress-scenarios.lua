event('ADDON_LOADED')
local WV = WowVoice
local events = frames.WowVoiceTrackerEvents
local function send(name, ...)
    events.scripts.OnEvent(events, name, ...)
    -- Simulate the deferred, coalesced scan before asserting rendered state.
    now = now + 0.051
    for i = 1, 100 do
        if not WV.Work.jobs['tracker-progress'] then break end
        local update = frames.WowVoiceWorkFrame.scripts.OnUpdate
        if update then update() end
    end
    assert(not WV.Work.jobs['tracker-progress'], 'progress scan did not finish')
end
local quests = {179, 192, 90902, 999999}
local objectives = {}
for _, id in ipairs(quests) do
    objectives[id] = {{text='Targets: 0/10', type='monster', numFulfilled=0, numRequired=10, finished=false}}
end
C_QuestLog.GetNumQuestLogEntries = function() return #quests end
C_QuestLog.GetInfo = function(i) return {questID=quests[i]} end
C_QuestLog.GetQuestObjectives = function(id) return objectives[id] end
QuestObjectiveTracker = CreateFrame('Frame', nil, UIParent)
local tracker = QuestObjectiveTracker
tracker.usedBlocks = {QuestTemplate={}}
function tracker:Update() end
function tracker:FreeBlock(row) self.usedBlocks.QuestTemplate[row.id]=nil; row:Hide() end
local function row(id)
    local r = CreateFrame('Frame', nil, tracker)
    r.id = id
    r.HeaderText = r:CreateFontString(nil, 'ARTWORK', 'QuestTitleFont')
    tracker.usedBlocks.QuestTemplate[id] = r
    return r
end
local first, second, extra, missing = row(179), row(192), row(90902), row(999999)
send('ADDON_LOADED')
local function playFor(r)
    for _, f in ipairs(allFrames) do if f.parent==r and f.Icon then return f end end
end
local play, other, supplemental = playFor(first), playFor(second), playFor(extra)
assert(play and other and supplemental and not playFor(missing))
local function advance(seconds)
    now = now + seconds
    for _, f in ipairs(allFrames) do
        if f.ProgressGlow and f:IsVisible() and f.scripts.OnUpdate then f.scripts.OnUpdate(f) end
    end
end
local function change(id, value)
    objectives[id][1].numFulfilled = value
    objectives[id][1].text = 'Targets: '..value..'/10'
    send('QUEST_LOG_UPDATE')
end
local function finish(id)
    local _, duration = WV:SoundPath(id, 'a')
    tick(now + duration + 0.1)
end
command('options')
local panel = frames.WowVoiceOptionsPanel
assert(WowVoiceDB.trackerProgressPulse and panel.TrackerProgressPulse:GetChecked())
WowVoiceDB.trackerProgressPulse=nil
event('ADDON_LOADED')
assert(WowVoiceDB.trackerProgressPulse, 'existing installations default on')
send('PLAYER_LOGIN')
send('QUEST_LOG_UPDATE')
assert(not play.ProgressGlow.visible, 'initial snapshot is silent')
change(179, 1)
local reminderStart=now
advance(0.6)
assert(play.ProgressGlow.visible and play.ProgressGlow.alpha>0.5)
assert(play.ProgressAnts.visible and play.ProgressAnts.texture:find('IconAlertAnts',1,true))
local initialCoords=table.concat(play.ProgressAnts.texCoord, ',')
advance(0.03)
assert(table.concat(play.ProgressAnts.texCoord, ',')~=initialCoords,
    'stock action-button edge advances through its animation frames')
assert(not other.ProgressGlow.visible and #plays==0 and #stops==0)
restored('1','0.37')
send('QUEST_LOG_UPDATE'); tracker:Update()
advance(1.9)
assert(play.ProgressGlow.visible and play.ProgressGlow.alpha==1 and play.alpha==1,
    'normal reminder stays fully bright without pauses or pulsing')
assert(play.Icon.alpha==0.7, 'glow does not change the triangle opacity')
play.scripts.OnEnter(play)
assert(play.Icon.alpha==1, 'hover still highlights the triangle')
play.scripts.OnLeave(play)
assert(play.alpha==1 and play.Icon.alpha==0.7, 'leaving dims only the triangle, not the glow')
advance(2.5)
assert(play.ProgressGlow.visible and play.ProgressGlow.alpha==1, 'glow remains steady')
now=reminderStart+9.9
send('QUEST_LOG_UPDATE'); tracker:Update()
assert(play.ProgressGlow.visible and play.scripts.OnUpdate, 'reminder is still visible just before 10 seconds')
now=reminderStart+10
advance(0)
assert(not play.ProgressGlow.visible and not play.scripts.OnUpdate and play.Icon.alpha==0.7,
    '10-second limit restores normal appearance; unchanged updates do not extend it')
assert(not play.ProgressAnts.visible, 'timeout hides animated edge too')
change(179, 2)
advance(9)
change(179, 3)
advance(0.6)
assert(play.ProgressGlow.visible, 'every real change restarts pulse')
advance(4.4)
assert(play.ProgressGlow.visible and play.scripts.OnUpdate, 'new progress gives a fresh 10-second window')
objectives[179][1].finished=true
send('QUEST_LOG_UPDATE')
assert(play.ProgressGlow.visible, 'non-counter completion changes trigger pulse')
advance(10)
local saved = objectives[179]
objectives[179]=nil; send('QUEST_LOG_UPDATE')
objectives[179]={{text=''}}; send('QUEST_LOG_UPDATE')
objectives[179]=saved; send('QUEST_LOG_UPDATE')
assert(not play.ProgressGlow.visible, 'cache misses retain last valid snapshot')
panel.TrackerProgressPulse:SetChecked(false)
panel.TrackerProgressPulse.scripts.OnClick(panel.TrackerProgressPulse)
change(179, 4)
event('ADDON_LOADED')
assert(not WowVoiceDB.trackerProgressPulse and not play.ProgressGlow.visible)
panel.TrackerProgressPulse:SetChecked(true)
panel.TrackerProgressPulse.scripts.OnClick(panel.TrackerProgressPulse)
send('QUEST_LOG_UPDATE')
assert(not play.ProgressGlow.visible, 'enabling does not replay old changes')
change(179, 5)
WV:SetTrackerProgressPulseEnabled(false)
assert(not play.ProgressGlow.visible and not play.scripts.OnUpdate, 'disable stops current pulse immediately')
WV:SetTrackerProgressPulseEnabled(true)
change(179, 6)
WV:SetTrackerButtonsEnabled(false)
assert(not play.visible and not play.ProgressGlow.visible)
assert(not panel.TrackerProgressPulse:IsEnabled() and panel.TrackerProgressPulse.Label.alpha<1,
    'parent option disables and dims the reminder sub-option')
assert(panel.TrackerProgressPulse:GetChecked() and WowVoiceDB.trackerProgressPulse,
    'disabling the parent preserves the saved reminder choice')
WV:SetTrackerButtonsEnabled(true)
assert(not play.ProgressGlow.visible)
assert(panel.TrackerProgressPulse:IsEnabled() and panel.TrackerProgressPulse.Label.alpha==1,
    'enabling the parent restores the reminder control')
change(90902, 1)
assert(supplemental.ProgressGlow.visible, 'supplemental quests work too')
tracker:FreeBlock(extra)
assert(not supplemental.ProgressGlow.visible and not supplemental.scripts.OnUpdate)
extra.id=192; extra:Show(); tracker.usedBlocks.QuestTemplate[192]=extra
tracker:Update()
assert(not supplemental.ProgressGlow.visible, 'pooled rows cannot carry another quest glow')
tracker.usedBlocks.QuestTemplate[192]=second
tracker:Update()
print('PASS: steady 10-second glow, repeated progress, unchanged events, cache misses, options and pooled rows')

-- Starting a description counts immediately, independent of autoplay settings.
WV:SetAutoPlayAcceptEnabled(false)
WV:SetAutoPlayTurnInEnabled(false)
questID=192
local playCount=#plays
event('QUEST_DETAIL')
change(192, 1)
assert(#plays==playCount and other.ProgressGlow.visible, 'autoplay opt-out leaves quest eligible')
send('PLAYER_ENTERING_WORLD')
assert(not other.ProgressGlow.visible, 'entering world establishes silent baseline')
change(192, 2)
assert(other.ProgressGlow.visible, 'quest carried from an earlier session remains eligible if never started')
assert(WV:ReplayQuest(179))
assert(WowVoiceDB.listenedQuests[playerGUID][179], 'successful start immediately marks description heard')
frames.WowVoiceTalkingHead.Close.scripts.OnClick()
assert(WowVoiceDB.listenedQuests[playerGUID][179], 'closing early retains heard state')
change(179, 7)
assert(not play.ProgressGlow.visible, 'closing early suppresses future reminders')
assert(WV:ReplayQuest(179))
finish(179)
assert(WowVoiceDB.listenedQuests[playerGUID][179] and not play.ProgressGlow.visible)
change(179, 8)
assert(not play.ProgressGlow.visible, 'finished manual replay suppresses further reminders')
event('ADDON_LOADED'); send('PLAYER_LOGIN'); send('PLAYER_ENTERING_WORLD', false, true)
change(179, 9)
assert(not play.ProgressGlow.visible, 'saved heard state survives reload')
local originalGUID=playerGUID
playerGUID='Player-2-OTHER'
send('PLAYER_ENTERING_WORLD')
change(179, 10)
assert(play.ProgressGlow.visible, 'heard state is per character')
playerGUID=originalGUID
send('PLAYER_ENTERING_WORLD')
WV:SetAutoPlayAcceptEnabled(true)
questID=192
event('QUEST_DETAIL')
assert(not WowVoiceDB.listenedQuests[playerGUID][192], 'automatic descriptions do not start a manual-play cooldown')
change(192, 3)
assert(other.ProgressGlow.visible, 'automatic playback does not suppress progress reminders for another quest')
finish(192)
WV:SetAutoPlayTurnInEnabled(true)
questID=861
event('QUEST_COMPLETE')
local _, completionDuration=WV:SoundPath(861,'c')
tick(now+completionDuration+0.1)
assert(not WowVoiceDB.listenedQuests[playerGUID][861], 'turn-in completion does not mark description')
soundOK=false
assert(not WV:ReplayQuest(90902))
tick(now+100)
assert(not WowVoiceDB.listenedQuests[playerGUID][90902], 'failed sound never counts')
soundOK=true
questID=90902
event('QUEST_DETAIL') -- A successful automatic retry restores availability.
assert(WV:ReplayQuest(90902))
assert(WV:ReplayQuest(861))
finish(861)
assert(WowVoiceDB.listenedQuests[playerGUID][90902], 'replaced playback still counts')
print('PASS: manual description starts persist even when closed/replaced; autoplay, failures and turn-in lines do not start a cooldown')

-- Actual options Test button previews every visible arrow, even heard quests
-- and when the preference is disabled, without changing either saved state.
WV:SetTrackerProgressPulseEnabled(false)
local played, stopped=#plays, #stops
panel.Buttons.test.scripts.OnClick()
advance(0.6)
assert(play.ProgressGlow.visible and other.ProgressGlow.visible)
assert(not WowVoiceDB.trackerProgressPulse and WowVoiceDB.listenedQuests[playerGUID][179])
advance(2)
assert(play.ProgressGlow.visible and play.ProgressGlow.alpha==1, 'preview has no pauses')
advance(2.4)
assert(play.ProgressGlow.visible and other.ProgressGlow.visible, 'preview stays steady on every button')
advance(30.8)
assert(play.ProgressGlow.visible and play.scripts.OnUpdate, 'preview continues beyond the normal 10-second limit')
assert(#plays==played and #stops==stopped, 'preview is silent')
panel.Buttons.test.scripts.OnClick()
assert(not play.ProgressGlow.visible and not play.scripts.OnUpdate)
panel.Buttons.test.scripts.OnClick()
panel:Hide()
assert(not play.ProgressGlow.visible and not other.scripts.OnUpdate, 'closing options stops preview')
panel:Show()
panel.Buttons.test.scripts.OnClick()
assert(WV:ReplayQuest(179))
assert(not play.ProgressGlow.visible and not other.scripts.OnUpdate, 'real audio exits preview')
WV:Silence()
panel.Buttons.test.scripts.OnClick()
frames.WowVoiceTalkingHead.Close.scripts.OnClick()
assert(not play.ProgressGlow.visible and not other.scripts.OnUpdate, 'portrait close exits preview')
assert(not WowVoiceDB.trackerProgressPulse, 'test never changes saved preference')
print('PASS: options test keeps all active arrows glowing; close, toggle and real playback clean up')

-- A one-hour wall-clock cooldown survives logout, reload and zoning.
WV:SetTrackerProgressPulseEnabled(true)
local heardUntil=WowVoiceDB.listenedQuests[playerGUID][179]
assert(heardUntil==serverNow+3600, 'successful playback stores an absolute one-hour deadline')
WowVoiceDB.listenedQuests['Player-2-OTHER']={[192]=heardUntil}
serverNow=heardUntil-3590
now=0 -- A new client process has a different uptime.
event('PLAYER_LOGOUT')
send('PLAYER_LOGIN')
send('PLAYER_ENTERING_WORLD', true, false)
assert(WowVoiceDB.listenedQuests[playerGUID][179]==heardUntil)
assert(WowVoiceDB.listenedQuests['Player-2-OTHER'][192]==heardUntil)
assert(not play.ProgressGlow.visible, 'login itself does not start a reminder')
change(179, 9)
assert(not play.ProgressGlow.visible, 'a full restart does not reset the cooldown')
serverNow=heardUntil-1
send('PLAYER_ENTERING_WORLD', false, true)
change(179, 8)
assert(not play.ProgressGlow.visible, 'reload preserves the remaining second')
send('PLAYER_ENTERING_WORLD', false, false)
change(179, 7)
assert(not play.ProgressGlow.visible, 'zone transitions preserve the cooldown')
serverNow=heardUntil
send('QUEST_LOG_UPDATE')
assert(not play.ProgressGlow.visible, 'expiry alone never lights the button')
change(179, 6)
assert(play.ProgressGlow.visible and play.ProgressAnts.visible, 'progress at exactly one hour reminds again')
assert(not WowVoiceDB.listenedQuests[playerGUID][179], 'expired records are pruned')
assert(WV:ReplayQuest(179))
frames.WowVoiceTalkingHead.Close.scripts.OnClick()
assert(not play.ProgressGlow.visible and not play.ProgressAnts.visible)
local firstDeadline=WowVoiceDB.listenedQuests[playerGUID][179]
serverNow=serverNow+1800
assert(WV:ReplayQuest(179))
WV:Silence()
local extended=WowVoiceDB.listenedQuests[playerGUID][179]
assert(extended==serverNow+3600 and extended==firstDeadline+1800, 'replay starts a fresh hour')
serverNow=firstDeadline
change(179, 5)
assert(not play.ProgressGlow.visible, 'the older deadline cannot end a renewed cooldown')
-- Failed starts neither create nor extend a cooldown.
soundOK=false
assert(not WV:ReplayQuest(179))
assert(WowVoiceDB.listenedQuests[playerGUID][179]==extended)
soundOK=true
WV:SetQuestAudioAvailable(179,true)
-- Offline time counts; login still establishes a silent baseline.
event('PLAYER_LOGOUT')
serverNow=extended+600
now=0
send('PLAYER_LOGIN')
send('PLAYER_ENTERING_WORLD', true, false)
assert(not play.ProgressGlow.visible and not WowVoiceDB.listenedQuests[playerGUID][179])
change(179, 4)
assert(play.ProgressGlow.visible, 'offline expiry allows the next objective change')
-- Legacy booleans carry no date: do not suppress reminders forever or invent a deadline.
WowVoiceDB.listenedQuests[playerGUID][179]=true
send('PLAYER_LOGIN')
assert(not WowVoiceDB.listenedQuests[playerGUID][179])
change(179, 3)
assert(play.ProgressGlow.visible, 'legacy session marks do not prevent future reminders')
print('PASS: absolute one-hour cooldown, exact expiry, replay renewal, failed starts, restart/reload/zoning, offline time and legacy migration')

-- Last acceptance delays only that quest, and only until another quest changes.
extra = row(90902)
tracker:Update()
supplemental = playFor(extra)
local function accept(id)
    assert(events.events.QUEST_ACCEPTED)
    send('QUEST_ACCEPTED', id)
    local recent = WowVoiceDB.lastAcceptedQuest[playerGUID]
    assert(recent.questID == id and recent.acceptedAt == serverNow and not recent.otherProgress)
    return recent
end
local function wallAdvance(seconds)
    serverNow = serverNow + seconds
    advance(seconds)
end
local function increment(id)
    change(id, objectives[id][1].numFulfilled + 1)
end
accept(179)
increment(179)
assert(not play.ProgressGlow.visible, 'the last accepted quest waits five minutes')
wallAdvance(299); increment(179)
assert(not play.ProgressGlow.visible, 'the acceptance delay is still active at 4:59')
wallAdvance(1); send('QUEST_LOG_UPDATE')
assert(not play.ProgressGlow.visible, 'five-minute expiry alone must not create a reminder')
increment(179)
assert(play.ProgressGlow.visible, 'the next progress at five minutes can remind')
wallAdvance(11)
local recent = accept(192)
increment(192)
assert(not other.ProgressGlow.visible)
increment(179)
assert(play.ProgressGlow.visible and recent.otherProgress, 'another quest reminds immediately and removes the delay')
increment(192)
assert(other.ProgressGlow.visible and serverNow == recent.acceptedAt,
    'returning to the latest quest reminds without waiting five minutes')
wallAdvance(11)
recent = accept(192)
assert(not other.ProgressGlow.visible, 'reaccepting resets any old glow and the delay')
increment(192); assert(not other.ProgressGlow.visible)
send('QUEST_LOG_UPDATE')
local cachedObjectives = objectives[179]
objectives[179] = nil; send('QUEST_LOG_UPDATE')
objectives[179] = cachedObjectives; send('QUEST_LOG_UPDATE')
assert(not recent.otherProgress, 'unchanged events and objective cache misses do not remove the delay')
-- Both quests can change in one coalesced event. Process the latest first to
-- ensure journal order cannot suppress its reminder after another quest changes.
quests = {192, 179, 90902, 999999}
objectives[192][1].numFulfilled = objectives[192][1].numFulfilled + 1
objectives[179][1].numFulfilled = objectives[179][1].numFulfilled + 1
send('QUEST_LOG_UPDATE')
assert(other.ProgressGlow.visible and play.ProgressGlow.visible and recent.otherProgress)
wallAdvance(11)
recent = accept(179)
increment(999999)
assert(recent.otherProgress, 'another quest without an audio recording also removes the delay')
increment(179); assert(play.ProgressGlow.visible)
-- Starting a newer quest replaces, rather than extends, the previous delay.
wallAdvance(11)
recent = accept(90902)
increment(90902); assert(not supplemental.ProgressGlow.visible)
increment(179); assert(play.ProgressGlow.visible)
increment(90902); assert(supplemental.ProgressGlow.visible)
-- Acceptance time and the other-quest flag survive loading screens/reloads,
-- while objective baselines remain silent. Offline time counts toward five minutes.
wallAdvance(11)
recent = accept(179)
wallAdvance(200)
event('ADDON_LOADED'); send('PLAYER_LOGIN'); send('PLAYER_ENTERING_WORLD')
assert(WowVoiceDB.lastAcceptedQuest[playerGUID] == recent and not recent.otherProgress)
increment(179); assert(not play.ProgressGlow.visible)
wallAdvance(100)
send('PLAYER_ENTERING_WORLD')
assert(not play.ProgressGlow.visible)
increment(179); assert(play.ProgressGlow.visible)
wallAdvance(11)
recent = accept(179)
increment(192); assert(recent.otherProgress)
send('PLAYER_ENTERING_WORLD'); increment(179)
assert(play.ProgressGlow.visible, 'the removed delay stays removed after reload')
wallAdvance(11)
recent = accept(179)
local owner = playerGUID
playerGUID = 'Player-3-NEW'
send('PLAYER_ENTERING_WORLD'); increment(179)
assert(play.ProgressGlow.visible and not WowVoiceDB.lastAcceptedQuest[playerGUID], 'last acceptance is per character')
playerGUID = owner
send('PLAYER_ENTERING_WORLD'); increment(179)
assert(not play.ProgressGlow.visible and WowVoiceDB.lastAcceptedQuest[playerGUID] == recent)
-- Disabled reminders keep observing progress but do not replay it on enable.
WV:SetTrackerProgressPulseEnabled(false)
increment(192); assert(recent.otherProgress and not other.ProgressGlow.visible)
WV:SetTrackerProgressPulseEnabled(true)
assert(not play.ProgressGlow.visible and not other.ProgressGlow.visible)
increment(179); assert(play.ProgressGlow.visible)
-- A manual Play has priority over both acceptance rules, even if closed early.
play.scripts.OnClick()
local deadline = WowVoiceDB.listenedQuests[playerGUID][179]
assert(deadline == serverNow + 3600 and not play.ProgressGlow.visible)
frames.WowVoiceTalkingHead.Close.scripts.OnClick()
accept(179)
increment(192); increment(179)
assert(not play.ProgressGlow.visible, 'other-quest progress cannot bypass the manual-play hour')
wallAdvance(301); increment(179)
assert(not play.ProgressGlow.visible, 'the five-minute delay cannot bypass the manual-play hour')
serverNow = deadline - 1
increment(179); assert(not play.ProgressGlow.visible)
serverNow = deadline
send('QUEST_LOG_UPDATE'); assert(not play.ProgressGlow.visible)
increment(179); assert(play.ProgressGlow.visible)
-- Progress on a manually suppressed quest still removes another quest's delay.
assert(WV:ReplayQuest(179)); WV:Silence()
recent = accept(192)
increment(179); assert(not play.ProgressGlow.visible and recent.otherProgress)
increment(192); assert(other.ProgressGlow.visible)
print('PASS: last acceptance waits five real minutes, other-quest progress removes the delay, coalesced order, silent baselines, no-audio quests, restart/offline persistence, character isolation and manual-hour priority')

-- The production notification shares the glow's eligibility and preference.
-- Never duplicate Blizzard's yellow message when real progress is observed.
UIErrorsFrame = CreateFrame('MessageFrame', 'UIErrorsFrame', UIParent)
function UIErrorsFrame:GetFont() return 'system-font', 18, '' end
function UIErrorsFrame:AddMessage() error('real progress must not emit a synthetic status message') end
WowVoiceDB.lastAcceptedQuest[playerGUID] = nil
WowVoiceDB.listenedQuests[playerGUID] = {}
send('PLAYER_ENTERING_WORLD')
local notice = frames.WowVoiceQuestReminderPreview
assert(not notice:IsShown())
local beforePlays, beforeErrors = #plays, WV.Work.errors
increment(179)
assert(notice:IsShown() and not notice.isTest and notice.questID == 179 and play.ProgressGlow.visible)
assert(#plays == beforePlays, 'notification never autoplays')
local function advanceNotice(seconds)
    advance(seconds)
    if notice:IsShown() and notice.scripts.OnUpdate then notice.scripts.OnUpdate(notice) end
end
advanceNotice(4)
local oldDeadline = notice.expiresAt
send('QUEST_LOG_UPDATE')
assert(notice.expiresAt == oldDeadline, 'unchanged snapshots do not extend the notification')
increment(179)
assert(notice.expiresAt > oldDeadline and notice.questID == 179)
advanceNotice(5)
assert(not notice:IsShown() and play.ProgressGlow.visible, 'text lasts five seconds, glow ten')
increment(179)
notice.scripts.OnEnter(notice)
increment(192)
assert(notice.questID == 179 and other.ProgressGlow.visible, 'hovered click target cannot switch quests')
advanceNotice(20)
assert(notice:IsShown(), 'hover holds a production notification too')
notice.scripts.OnLeave(notice)
assert(notice.expiresAt == now + 5, 'leaving restarts the full notification lifetime')
advanceNotice(4)
notice.scripts.OnEnter(notice)
advanceNotice(10)
notice.scripts.OnLeave(notice)
assert(notice.expiresAt == now + 5, 'each hover grants a fresh five seconds after leaving')
advanceNotice(4.9)
assert(notice:IsShown())
advanceNotice(0.11)
assert(not notice:IsShown())
increment(192)
assert(notice.questID == 192, 'new progress replaces a non-hovered notification')
objectives[179][1].numFulfilled = objectives[179][1].numFulfilled + 1
objectives[192][1].numFulfilled = objectives[192][1].numFulfilled + 1
send('QUEST_WATCH_UPDATE', 192)
assert(notice.questID == 192 and play.ProgressGlow.visible and other.ProgressGlow.visible,
    'coalesced progress prefers the latest native event and glows both quests')
panel.TrackerProgressPulse:SetChecked(false)
panel.TrackerProgressPulse.scripts.OnClick(panel.TrackerProgressPulse)
assert(not notice:IsShown() and not play.ProgressGlow.visible and not other.ProgressGlow.visible)
increment(179)
assert(not notice:IsShown())
WV:SetTrackerProgressPulseEnabled(true)
assert(not notice:IsShown(), 'enabling does not replay suppressed progress')
increment(179)
assert(notice:IsShown())
WV:SetTrackerButtonsEnabled(false)
assert(not notice:IsShown() and not panel.TrackerProgressPulse:IsEnabled())
assert(panel.TrackerProgressPulse.Description.alpha < 1)
WV:SetTrackerButtonsEnabled(true)
increment(179)
WowVoiceDB.enabled = false
WV:RefreshTrackerButtons()
assert(not notice:IsShown())
WowVoiceDB.enabled = true
increment(179)
WV:SetQuestAudioAvailable(179, false)
assert(not notice:IsShown(), 'audio failure removes the notification immediately')
WV:SetQuestAudioAvailable(179, true)
increment(179)
accept(179)
assert(not notice:IsShown(), 'reacceptance removes the old notification')
wallAdvance(270); increment(179)
assert(not notice:IsShown(), 'first progress at 4:30 remains silent')
wallAdvance(60); increment(179)
assert(notice:IsShown(), 'next progress at 5:30 shows the message')
notice.scripts.OnClick(notice)
assert(not notice:IsShown() and not play.ProgressGlow.visible)
assert(WowVoiceDB.listenedQuests[playerGUID][179] == serverNow + 3600)
WV:Silence()
wallAdvance(3599); increment(179)
assert(not notice:IsShown(), 'manual play suppresses the notification for the whole hour')
wallAdvance(1); increment(179)
assert(notice:IsShown(), 'next progress at expiry can notify again')
send('PLAYER_ENTERING_WORLD')
assert(not notice:IsShown(), 'zone changes clear notification and establish a silent baseline')
accept(179)
increment(192)
increment(179)
assert(notice:IsShown() and notice.questID == 179, 'other-quest progress removes the message acceptance delay')
for index, id in ipairs(quests) do
    if id == 179 then table.remove(quests, index); break end
end
send('QUEST_LOG_UPDATE')
assert(not notice:IsShown(), 'removing the quest also removes its clickable notification')
increment(999999)
assert(not notice:IsShown(), 'quests without audio remain silent')
assert(WV.Work.errors == beforeErrors, 'production notifications must not fail inside the deferred scan')
print('PASS: real reminder and glow share one option, no duplicate status/autoplay, renewal, hover target safety, native-event priority, lifecycle cleanup and five-minute/one-hour rules')

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
local objectives, completed = {}, {}
C_QuestLog.IsComplete = function(id) return completed[id] == true end
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
assert(WowVoiceDB.listenedQuests[playerGUID][192] == serverNow + 1800, 'automatic descriptions start the same 30-minute cooldown')
change(192, 3)
assert(not other.ProgressGlow.visible, 'the first kill after automatic playback must not remind')
local autoDeadline = WowVoiceDB.listenedQuests[playerGUID][192]
serverNow = serverNow + 1
event('QUEST_DETAIL')
assert(WowVoiceDB.listenedQuests[playerGUID][192] == autoDeadline, 'duplicate dialogue events do not renew the cooldown')
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
print('PASS: manual and automatic descriptions share cooldown; duplicate events, failures and turn-in lines do not renew it')

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

-- A listening pause slides only while active and only for that quest's progress.
WV:SetTrackerProgressPulseEnabled(true)
assert(WV:ReplayQuest(179)); WV:Silence()
local heardUntil = WowVoiceDB.listenedQuests[playerGUID][179]
assert(heardUntil == serverNow + 1800)
serverNow = serverNow + 60
change(179, 9)
local extended = WowVoiceDB.listenedQuests[playerGUID][179]
assert(extended == serverNow + 1800 and extended == heardUntil + 60)
assert(not play.ProgressGlow.visible, 'first item renews the active pause')
serverNow = serverNow + 60
send('QUEST_LOG_UPDATE'); tracker:Update()
assert(WowVoiceDB.listenedQuests[playerGUID][179] == extended, 'unchanged events do not renew')
change(192, 4)
assert(WowVoiceDB.listenedQuests[playerGUID][179] == extended, 'other quests do not renew')
change(179, 8)
extended = WowVoiceDB.listenedQuests[playerGUID][179]
assert(extended == serverNow + 1800, 'second item renews the pause again')
-- Reloads, zoning and other characters preserve rather than extend the deadline.
local originalGUID = playerGUID
WowVoiceDB.listenedQuests['Player-2-OTHER'] = {[179]=extended-10}
serverNow = serverNow + 10
now = 0
send('PLAYER_LOGIN'); send('PLAYER_ENTERING_WORLD')
assert(WowVoiceDB.listenedQuests[playerGUID][179] == extended)
assert(WowVoiceDB.listenedQuests['Player-2-OTHER'][179] == extended-10)
playerGUID = 'Player-2-OTHER'
send('PLAYER_ENTERING_WORLD'); change(179, 7)
assert(WowVoiceDB.listenedQuests[originalGUID][179] == extended, 'activity is per character')
playerGUID = originalGUID
send('PLAYER_ENTERING_WORLD')
serverNow = extended-1
send('QUEST_LOG_UPDATE')
assert(not play.ProgressGlow.visible and WowVoiceDB.listenedQuests[playerGUID][179] == extended)
serverNow = extended
send('QUEST_LOG_UPDATE')
assert(not play.ProgressGlow.visible, 'expiry alone is silent')
change(179, 6)
assert(play.ProgressGlow.visible and not WowVoiceDB.listenedQuests[playerGUID][179],
    'progress after 30 quiet minutes reminds instead of renewing an expired pause')
-- A real replay renews; failed playback does not.
assert(WV:ReplayQuest(179)); WV:Silence()
local firstDeadline = WowVoiceDB.listenedQuests[playerGUID][179]
serverNow = serverNow + 900
assert(WV:ReplayQuest(179)); WV:Silence()
extended = WowVoiceDB.listenedQuests[playerGUID][179]
assert(extended == firstDeadline+900)
soundOK = false
assert(not WV:ReplayQuest(179))
assert(WowVoiceDB.listenedQuests[playerGUID][179] == extended)
soundOK = true
WV:SetQuestAudioAvailable(179, true)
-- Offline time counts and does not replay old progress at login.
event('PLAYER_LOGOUT')
serverNow = extended+600
now = 0
send('PLAYER_LOGIN'); send('PLAYER_ENTERING_WORLD')
assert(not play.ProgressGlow.visible and not WowVoiceDB.listenedQuests[playerGUID][179])
change(179, 5); assert(play.ProgressGlow.visible)
-- Upgrade old one-hour deadlines once, retaining the original listening time.
WowVoiceDB.reminderCooldown30Minutes = nil
WowVoiceDB.listenedQuests[playerGUID] = {[179]=serverNow+3500, [192]=serverNow+1700, [90902]=true}
WowVoiceDB.listenedQuests['Player-2-OTHER'] = {[179]=serverNow+3400}
send('PLAYER_LOGIN')
assert(WowVoiceDB.listenedQuests[playerGUID][179] == serverNow+1700)
assert(not WowVoiceDB.listenedQuests[playerGUID][192] and not WowVoiceDB.listenedQuests[playerGUID][90902])
assert(WowVoiceDB.listenedQuests['Player-2-OTHER'][179] == serverNow+1600)
send('PLAYER_LOGIN')
assert(WowVoiceDB.listenedQuests[playerGUID][179] == serverNow+1700, 'migration is not repeated')
serverNow = serverNow+1800
send('PLAYER_ENTERING_WORLD')
print('PASS: sliding 30-minute pause, unchanged and other-quest events, character isolation, reload/offline expiry, replay/failure and migration')

-- Acceptance only resets the baseline, without hidden timers or cross-quest rules.
local function accept(id)
    assert(events.events.QUEST_ACCEPTED)
    send('QUEST_ACCEPTED', id)
end
local function wallAdvance(seconds)
    serverNow = serverNow + seconds
    advance(seconds)
end
local function increment(id)
    change(id, objectives[id][1].numFulfilled + 1)
end
WowVoiceDB.lastAcceptedQuest = {[playerGUID]={questID=179, acceptedAt=serverNow, otherProgress=false}}
accept(179)
assert(not play.ProgressGlow.visible, 'acceptance itself is silent')
increment(179)
assert(play.ProgressGlow.visible, 'first progress immediately after acceptance can remind')
accept(192)
increment(192)
assert(other.ProgressGlow.visible, 'newer acceptance adds no delay')
accept(179)
assert(not play.ProgressGlow.visible, 'reacceptance clears an old reminder')
increment(179)
assert(play.ProgressGlow.visible, 'reacceptance does not restart a hidden timer')
send('PLAYER_ENTERING_WORLD')
assert(not play.ProgressGlow.visible and not other.ProgressGlow.visible)
increment(179)
assert(play.ProgressGlow.visible, 'progress after reload ignores old acceptance history')
play.scripts.OnClick()
local deadline = WowVoiceDB.listenedQuests[playerGUID][179]
assert(deadline == serverNow + 1800 and not play.ProgressGlow.visible)
frames.WowVoiceTalkingHead.Close.scripts.OnClick()
accept(179)
increment(192); increment(179)
assert(other.ProgressGlow.visible and not play.ProgressGlow.visible, 'other quests do not override a listening cooldown')
serverNow = deadline - 1
increment(179); assert(not play.ProgressGlow.visible)
serverNow = WowVoiceDB.listenedQuests[playerGUID][179]
send('QUEST_LOG_UPDATE'); assert(not play.ProgressGlow.visible)
increment(179); assert(play.ProgressGlow.visible)
print('PASS: immediate progress after acceptance, legacy acceptance history ignored, silent reload and preserved listening cooldown')

-- Abandonment clears only this quest's old pause, before any new offer playback.
local function removeQuest(id)
    for index, value in ipairs(quests) do
        if value == id then table.remove(quests, index); break end
    end
    assert(events.events.QUEST_REMOVED)
    send('QUEST_REMOVED', id)
end
assert(WV:ReplayQuest(192)); WV:Silence()
local otherDeadline = WowVoiceDB.listenedQuests[playerGUID][192]
assert(WV:ReplayQuest(179)); WV:Silence()
WowVoiceDB.listenedQuests['Player-2-OTHER'][179] = serverNow+1800
local otherCharacterDeadline = WowVoiceDB.listenedQuests['Player-2-OTHER'][179]
-- A queued scan of the old quest must not resume after removal.
events.scripts.OnEvent(events, 'QUEST_LOG_UPDATE')
removeQuest(179)
assert(not WowVoiceDB.listenedQuests[playerGUID][179] and not play.ProgressGlow.visible)
assert(WowVoiceDB.listenedQuests[playerGUID][192] == otherDeadline)
assert(WowVoiceDB.listenedQuests['Player-2-OTHER'][179] == otherCharacterDeadline)
send('PLAYER_ENTERING_WORLD')
assert(not WowVoiceDB.listenedQuests[playerGUID][179], 'reload cannot resurrect an abandoned quest pause')
quests[#quests+1] = 179
objectives[179][1].numFulfilled = 0
accept(179)
assert(not play.ProgressGlow.visible, 'silent reacceptance only establishes a baseline')
increment(179)
assert(play.ProgressGlow.visible, 'new progress after abandonment is eligible without another listen')
removeQuest(179)
assert(not play.ProgressGlow.visible, 'abandoning also clears an active reminder')
-- Automatic offer playback occurs before acceptance, and creates a NEW pause.
WV:SetAutoPlayAcceptEnabled(true)
questID = 179
event('QUEST_DETAIL')
local newDeadline = WowVoiceDB.listenedQuests[playerGUID][179]
assert(newDeadline == serverNow+1800)
quests[#quests+1] = 179
objectives[179][1].numFulfilled = 0
accept(179)
assert(WowVoiceDB.listenedQuests[playerGUID][179] == newDeadline,
    'acceptance preserves the new automatic description pause')
increment(179)
assert(not play.ProgressGlow.visible, 'new listening still suppresses first progress')
WV:Silence()
print('PASS: abandonment clears old cooldown and queued scan, preserves other quests/characters, silent reacceptance and fresh autoplay pause')

-- The production notification shares the glow's eligibility and preference.
-- Never duplicate Blizzard's yellow message when real progress is observed.
UIErrorsFrame = CreateFrame('MessageFrame', 'UIErrorsFrame', UIParent)
function UIErrorsFrame:GetFont() return 'system-font', 18, '' end
function UIErrorsFrame:AddMessage() error('real progress must not emit a synthetic status message') end
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
assert(notice:IsShown(), 'first progress at 4:30 has no acceptance delay')
wallAdvance(60); increment(179)
assert(notice:IsShown(), 'next progress at 5:30 shows the message')
notice.scripts.OnClick(notice)
assert(not notice:IsShown() and not play.ProgressGlow.visible)
assert(WowVoiceDB.listenedQuests[playerGUID][179] == serverNow + 1800)
WV:Silence()
wallAdvance(1799); increment(179)
assert(not notice:IsShown(), 'manual play suppresses the notification for the whole 30 minutes')
wallAdvance(1800); increment(179)
assert(notice:IsShown(), 'next progress after 30 quiet minutes can notify again')
send('PLAYER_ENTERING_WORLD')
assert(not notice:IsShown(), 'zone changes clear notification and establish a silent baseline')
accept(179)
increment(192)
increment(179)
assert(notice:IsShown() and notice.questID == 179, 'quest switching has no effect on eligibility')
-- Final progress follows the same rules, including a return after two days.
objectives[179] = {{text='Targets: 8/9', type='monster', numFulfilled=8, numRequired=9, finished=false}}
completed[179] = false
send('PLAYER_ENTERING_WORLD')
assert(WV:ReplayQuest(179)); WV:Silence()
event('PLAYER_LOGOUT')
serverNow = serverNow + 2*24*60*60
now = 0
send('PLAYER_LOGIN'); send('PLAYER_ENTERING_WORLD')
assert(not notice:IsShown() and not play.ProgressGlow.visible, 'returning at 8/9 establishes a silent baseline')
objectives[179][1].text = 'Targets: 9/9'
objectives[179][1].numFulfilled = 9
objectives[179][1].finished = true
completed[179] = true
send('QUEST_WATCH_UPDATE', 179)
assert(notice:IsShown() and play.ProgressGlow.visible, '9/9 after two days reminds after the listening pause has expired')
local finalDeadline = notice.expiresAt
notice.scripts.OnEnter(notice)
send('QUEST_LOG_UPDATE')
assert(notice:IsShown() and notice.expiresAt == finalDeadline, 'unchanged completion neither hides nor renews the reminder')
notice.scripts.OnLeave(notice)
advanceNotice(5)
assert(not notice:IsShown())
send('QUEST_LOG_UPDATE')
assert(not notice:IsShown(), 'unchanged completed quests do not repeatedly remind')
send('PLAYER_ENTERING_WORLD')
assert(not notice:IsShown() and not play.ProgressGlow.visible, 'login at 9/9 is silent')
-- Completing a quest during an active listening pause still suppresses both effects.
completed[179] = false
objectives[179][1].numFulfilled = 8
objectives[179][1].finished = false
send('PLAYER_ENTERING_WORLD')
assert(WV:ReplayQuest(179)); WV:Silence()
serverNow = serverNow + 60
objectives[179][1].numFulfilled = 9
objectives[179][1].finished = true
completed[179] = true
send('QUEST_WATCH_UPDATE', 179)
assert(not notice:IsShown() and not play.ProgressGlow.visible, '9/9 respects the active pause')
assert(WowVoiceDB.listenedQuests[playerGUID][179] == serverNow+1800, 'final progress renews an active pause like intermediate progress')
-- A single non-counter escort objective can also remind after the pause expires.
serverNow = serverNow + 1800
objectives[179] = {{text='Escort in progress', type='event', finished=false}}
completed[179] = false
send('PLAYER_ENTERING_WORLD')
objectives[179][1].text = 'Escort complete'
objectives[179][1].finished = true
completed[179] = true
send('QUEST_LOG_UPDATE')
assert(notice:IsShown() and play.ProgressGlow.visible, 'escort completion uses the same reminder rules')
print('PASS: 8/9 to 9/9 after two days, completed baselines, unchanged events, active pause renewal and escort completion')
for index, id in ipairs(quests) do
    if id == 179 then table.remove(quests, index); break end
end
send('QUEST_LOG_UPDATE')
assert(not notice:IsShown(), 'removing the quest also removes its clickable notification')
increment(999999)
assert(not notice:IsShown(), 'quests without audio remain silent')
assert(WV.Work.errors == beforeErrors, 'production notifications must not fail inside the deferred scan')
print('PASS: real reminder and glow share one option, no duplicate status/autoplay, renewal, hover target safety, native-event priority, lifecycle cleanup and listening cooldown')

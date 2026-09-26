event('ADDON_LOADED')
local WV = WowVoice
local events = frames.WowVoiceTrackerEvents
local function send(name, ...) events.scripts.OnEvent(events, name, ...) end
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
assert(WowVoiceDB.listenedQuests[playerGUID][192], 'automatic descriptions count immediately too')
change(192, 3)
assert(not other.ProgressGlow.visible, 'automatic playback suppresses progress reminders too')
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
print('PASS: started descriptions persist per character even when closed/replaced; failures and turn-in lines do not count')

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

-- A real logout/login is a new listening session; reload and zoning are not.
WV:SetTrackerProgressPulseEnabled(true)
WowVoiceDB.listenedQuests['Player-2-OTHER']={[192]=true}
event('PLAYER_LOGOUT')
send('PLAYER_LOGIN')
send('PLAYER_ENTERING_WORLD', true, false)
assert(not WowVoiceDB.listenedQuests[playerGUID][179], 'real login clears last-session playback marks')
assert(WowVoiceDB.listenedQuests['Player-2-OTHER'][192], 'login only resets the current character')
assert(not play.ProgressGlow.visible, 'login itself does not start a reminder')
change(179, 9)
assert(play.ProgressGlow.visible and play.ProgressAnts.visible,
    'progress after a new login reminds about a quest played in the previous session')
assert(WV:ReplayQuest(179))
frames.WowVoiceTalkingHead.Close.scripts.OnClick()
assert(not play.ProgressGlow.visible and not play.ProgressAnts.visible, 'playing then closing stops both glow layers')
send('PLAYER_ENTERING_WORLD', false, true)
change(179, 8)
assert(not play.ProgressGlow.visible, 'reload preserves new-session playback marks')
send('PLAYER_ENTERING_WORLD', false, false)
change(179, 7)
assert(not play.ProgressGlow.visible, 'zone transition also preserves playback marks')
print('PASS: real login resets listening session; reload/zoning preserve marks and other characters remain isolated')

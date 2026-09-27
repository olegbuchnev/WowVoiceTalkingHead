event('ADDON_LOADED')
local WV = WowVoice
local quests = {179, 192, 90902, 999999}
C_QuestLog.GetNumQuestLogEntries = function() return #quests end
C_QuestLog.GetInfo = function(index) return {questID=quests[index]} end
C_QuestLog.GetQuestObjectives = function(id) return {{text='Objective for '..id..': 1/5'}} end
QuestObjectiveTracker = CreateFrame('Frame', nil, UIParent)
local tracker = QuestObjectiveTracker
tracker.usedBlocks = {QuestTemplate={}}
local rows, replay = {}, {}
for _, id in ipairs({179, 192, 90902, 999999, 861}) do
    local row = CreateFrame('Frame', nil, tracker)
    row.id = id
    row.HeaderText = row:CreateFontString(nil, 'ARTWORK', 'QuestTitleFont')
    tracker.usedBlocks.QuestTemplate[id] = row
    rows[id] = row
end
WV:RefreshTrackerButtons()
for _, f in ipairs(allFrames) do
    if f.Icon and f.parent and f.parent.id then
        replay[f.parent.id] = f
        function f:GetCenter() return 1500, 800 end
    end
end
rows[90902]:Hide()
UIErrorsFrame = CreateFrame('MessageFrame', 'UIErrorsFrame', UIParent)
function UIErrorsFrame:GetFont() return 'font', 18, '' end
local messages = {}
function UIErrorsFrame:AddMessage(text, r, g, b) messages[#messages + 1] = {text, r, g, b} end
local function updateAt(value)
    now = value
    local frame = frames.WowVoiceQuestReminderPreview
    if frame.visible and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame) end
    for _, play in pairs(replay) do
        if play:IsVisible() and play.scripts.OnUpdate then play.scripts.OnUpdate(play) end
    end
end
assert(not frames.WowVoiceQuestReminderPreview, 'preview must be lazy and never appear at login')
command('remindertest 179')
local frame = assert(frames.WowVoiceQuestReminderPreview)
local start = now
assert(frame.visible and frame.questID == 179 and frame.Label.text == 'Вспомнить задание')
assert(frame.points[1][2] == UIErrorsFrame and frame.points[1][3] == 'TOP' and frame.points[1][5] == -24)
assert(frame.Label.fontSize == 18 and frame.Icon.width > 18 and frame.height > frame.Icon.width)
assert(frame.Icon.point[2] == frame.Label and frame.Icon.point[3] == 'RIGHT')
assert(messages[1][2] == 1 and messages[1][3] == 1 and messages[1][4] == 0)
assert(messages[1][1] == 'Objective for 179: 1/5')
assert(replay[179].ProgressGlow.visible and not replay[192].ProgressGlow.visible,
    'only the selected quest glows')
assert(#plays == 0 and not WowVoiceDB.listenedQuests and not WowVoiceDB.lastAcceptedQuest,
    'showing mock must not start audio, a cooldown or an acceptance record')
updateAt(start + 4.9)
assert(frame.visible and frame.alpha < 1, 'fade fits within five seconds')
updateAt(start + 5)
assert(not frame.visible and not frame.scripts.OnUpdate)
assert(replay[179].ProgressGlow.visible, 'tracker glow outlives the five-second text')
updateAt(start + 10)
assert(not replay[179].ProgressGlow.visible, 'test glow stops after ten seconds')
command('remindertest 179')
start = now
updateAt(start + 4)
frame.scripts.OnEnter(frame)
updateAt(start + 24)
assert(frame.visible and frame.alpha == 1, 'hover pauses expiration')
frame.scripts.OnLeave(frame)
updateAt(start + 28.9)
assert(frame.visible)
updateAt(start + 29)
assert(not frame.visible, 'leaving starts a fresh five seconds instead of the remaining second')
local originalRandom = math.random
local randomCalls = 0
math.random = function(count)
    assert(count == 2, 'random pool excludes hidden, unvoiced and non-journal quests')
    randomCalls = randomCalls + 1
    return randomCalls == 1 and 1 or 2
end
command('remindertest')
assert(frame.questID == 179 and frame.visible)
command('remindertest')
assert(frame.questID == 192 and frame.visible and randomCalls == 2)
assert(not replay[179].ProgressGlow.visible and replay[192].ProgressGlow.visible,
    'a new test clears the previous test glow')
math.random = originalRandom
updateAt(now + 4)
command('remindertest 192')
assert(frames.WowVoiceQuestReminderPreview == frame and frame.questID == 192)
updateAt(now + 3)
assert(frame.visible, 'repeated command resets the five-second lifetime')
command('remindertest off')
assert(not frame.visible and not frame.scripts.OnUpdate)
assert(not replay[192].ProgressGlow.visible, 'off clears both parts of the preview')
local function noCandidate(commandText)
    local before = #messages
    command(commandText or 'remindertest')
    assert(not frame.visible and #messages == before, 'no eligible visible row: no synthetic progress or card')
end
noCandidate('remindertest 90902')
noCandidate('remindertest 861')
tracker:Hide()
noCandidate()
tracker:Show()
tracker:SetAlpha(0)
noCandidate()
tracker:SetAlpha(1)
rows[192]:Hide()
local getCenter = replay[179].GetCenter
replay[179].GetCenter = function() return -50, 800 end
noCandidate()
replay[179].GetCenter = function() return nil, nil end
noCandidate()
replay[179].GetCenter = getCenter
rows[192]:Show()
local count = #messages
command('remindertest invalid')
command('remindertest -1')
assert(#messages == count and not frame.visible)
command('remindertest 179')
frame.scripts.OnClick(frame)
assert(not frame.visible and plays[#plays].file:find('179a.ogg', 1, true))
assert(WowVoiceDB.listenedQuests[playerGUID][179], 'actual click retains normal manual-play cooldown')
assert(not replay[179].ProgressGlow.visible, 'click also clears test glow')
local deadline = WowVoiceDB.listenedQuests[playerGUID][179]
command('remindertest 179')
assert(replay[179].ProgressGlow.visible and WowVoiceDB.listenedQuests[playerGUID][179] == deadline,
    'mock can preview an existing cooldown without changing it')
command('remindertest off')
WV:Silence()
UIErrorsFrame = nil
command('remindertest 179')
assert(frame.points[1][2] == UIParent, 'fallback placement when no standard message frame exists')
command('remindertest off')
print('PASS: reminder mock, random visible voiced journal quests, hidden/transparent/offscreen exclusion, matching ten-second glow, five-second text, hover pause, replacement, cancellation and real click playback')

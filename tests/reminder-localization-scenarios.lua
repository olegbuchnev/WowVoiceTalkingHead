local WV, L = WowVoice, WowVoiceLocale
WV.questQueue:Clear()
C_QuestLog.GetNumQuestLogEntries = function() return 1 end
C_QuestLog.GetInfo = function() return {questID=179} end
C_QuestLog.GetQuestObjectives = function() return {{text='Objective: 1/5'}} end
QuestObjectiveTracker = CreateFrame('Frame', nil, UIParent)
local row = CreateFrame('Frame', nil, QuestObjectiveTracker)
row.id = 179
row.HeaderText = row:CreateFontString(nil, 'ARTWORK', 'QuestTitleFont')
QuestObjectiveTracker.usedBlocks = {QuestTemplate={row}}
WV:RefreshTrackerButtons()
for _, frame in ipairs(allFrames) do
    if frame.parent == row and frame.Icon then
        function frame:GetCenter() return 1500, 800 end
    end
end
-- The fallback without a native status frame must also support Cyrillic.
UIErrorsFrame = nil
WV:TestQuestReminder(179)
local reminder = assert(frames.WowVoiceQuestReminderPreview)
assert(reminder:IsShown() and reminder.Label:GetText() == 'Вспомнить задание')
assert(reminder.Label:GetFont() == L.cyrillicFont)
assert(reminder:GetWidth() == reminder.Label:GetStringWidth() + 24)
WV:TestQuestReminder(false)

UIErrorsFrame = CreateFrame('MessageFrame', 'UIErrorsFrame', UIParent)
local nativeFont
local size = 18
function UIErrorsFrame:GetFont() return nativeFont, size, 'OUTLINE' end
function UIErrorsFrame:AddMessage() end
-- Every show reassigns the native status font; preserve its size and outline
-- while selecting a Cyrillic face, without altering UIErrorsFrame itself.
for _, value in ipairs({
    {'Fonts\\FRIZQT__.TTF', L.cyrillicFont, 18},
    {'Fonts\\SKURRI.TTF', 'Fonts\\SKURRI_CYR.TTF', 22},
    {'Fonts\\MORPHEUS.TTF', 'Fonts\\MORPHEUS_CYR.TTF', 20},
    {'Fonts\\FRIZQT__.TTF', L.cyrillicFont, 18},
}) do
    nativeFont, size = L.isEnglish and value[1] or value[2], value[3]
    WV:TestQuestReminder(179)
    local face, height, flags = reminder.Label:GetFont()
    assert(reminder:IsShown() and reminder.Label:GetText() == 'Вспомнить задание')
    assert(face == value[2] and height == size and flags == 'OUTLINE')
    assert(UIErrorsFrame:GetFont() == nativeFont)
    assert(reminder:GetWidth() > reminder.Label:GetStringWidth() + reminder.Icon:GetWidth())
    WV:TestQuestReminder(false)
end
print('PASS: ' .. GetLocale() .. ' Russian reminder, Cyrillic status font, repeat appearances, size/outline and fallback layout')

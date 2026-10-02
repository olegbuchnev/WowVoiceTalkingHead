local WV, Q, S = WowVoice, WowVoice.questQueue, WowVoiceAudioSources
local english = WowVoiceLocale.isEnglish
assert(WowVoiceLocale.isRussian == (GetLocale() == 'ruRU'))
local texts = WowVoiceQuestTexts.entries
local description, completion = texts['179a'], texts['179c']
local unitSex = UnitSex
local playerSex = 2
function UnitSex() return playerSex end
texts['179a'] = { male = 'Русское описание для героя.', female = 'Русское описание для героини.' }
texts['179c'] = { common = 'Русское завершение.' }
local head = frames.WowVoiceTalkingHead
local gameText = english and 'Current game dialogue.' or 'Настоящий текст задания из игры.'
local function start(section)
    Q:Clear()
    local item = { context = { questId = 179, section = section, title = 'Quest',
        text = gameText, speaker = { npcID = 658, name = 'NPC' } } }
    Q:Add(item)
    assert(Q:Start(item))
    assert(item.context.text == gameText, 'display choice must never overwrite captured game text')
    return item
end
for _, source in ipairs({'wowvoice', 'catquest'}) do
    assert(WV:SetSharedQuestVoice(source))
    for _, sex in ipairs({2, 3}) do
        playerSex = sex
        for _, section in ipairs({'a', 'c', 'p'}) do
            start(section)
            local expected = english and S.Text(179, section) or gameText
            assert(head.Body:GetText() == (expected or gameText), 'locale priority must apply to either audio source and each stage')
        end
    end
end

-- Save the original English/Russian game capture, not substituted subtitles.
start('a')
Q:SaveSession()
local saved = WowVoiceQueueDB
assert(saved.records[1].context.text == gameText)
Q:Clear()
Q.loggingOut = nil
WowVoiceQueueDB = saved
Q:RestoreSession()
frames.WowVoiceQuestQueueDriver.scripts.OnUpdate()
assert(head.Body:GetText() == (english and texts['179a'].female or gameText))
assert(Q.current.context.text == gameText)
Q:Clear()

-- No Russian entry (or only whitespace/non-Russian text) retains game text.
for _, entry in ipairs({{}, {common = '   '}, {common = 'English database text'}}) do
    texts['179a'] = entry
    start('a')
    assert(head.Body:GetText() == gameText)
end
texts['179a'] = {common = 'Русское описание.'}

-- Bundled text works without either voice pack; reading time uses displayed
-- text as well when no measured recording duration exists.
Q:Clear()
local isLoaded = C_AddOns.IsAddOnLoaded
C_AddOns.IsAddOnLoaded = function() return false end
start('a')
assert(head.Body:GetText() == (english and texts['179a'].common or gameText))
local missingID = 999997
assert(not texts[missingID .. 'a'] and not WowVoiceDur[missingID .. 'a'])
texts[missingID .. 'a'] = {common = 'Короткое русское описание.'}
local context = {questId = missingID, section = 'a', text = string.rep('word ', 30)}
assert(WV:SilentDuration(context) == (english and 4 or 12))
texts[missingID .. 'a'] = nil
C_AddOns.IsAddOnLoaded = isLoaded
Q:Clear()

-- Replaying a captured quest gets current journal data, including after a
-- client-language change; the saved capture remains untouched.
questCache()[179] = {description = 'Old capture', npcID = 658}
C_QuestLog.GetLogIndexForQuestID = function(id) assert(id == 179); return 7 end
GetQuestLogQuestText = function(index) assert(index == 7); return gameText end
assert(WV:ReplayQuest(179))
assert(head.Body:GetText() == (english and texts['179a'].common or gameText))
assert(questCache()[179].description == 'Old capture')
Q:Clear()
texts['179a'], texts['179c'], UnitSex = description, completion, unitSex
print('PASS: ' .. GetLocale() .. ' quest text priority, both audio sources, stages/sex variants, reload, missing translations, silent duration and current journal text')

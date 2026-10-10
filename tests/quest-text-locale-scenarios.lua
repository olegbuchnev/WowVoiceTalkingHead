local WV, Q, S = WowVoice, WowVoice.questQueue, WowVoiceAudioSources
local english = WowVoiceLocale.isEnglish
assert(WowVoiceLocale.isRussian == (GetLocale() == 'ruRU'))
local texts = WowVoiceQuestTexts.entries
local description, completion, progress = texts['179a'], texts['179c'], texts['179p']
local unitSex = UnitSex
local playerSex = 2
function UnitSex() return playerSex end
texts['179a'] = { male = 'Русское описание для героя.', female = 'Русское описание для героини.' }
texts['179c'] = { common = 'Русское завершение.' }
texts['179p'] = { common = 'Русский текст выполнения.' }
local head = frames.TalkingHeadRu
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
for _, order in ipairs({{'wowvoice','catquest','wayfarer'}, {'wowvoice','wayfarer','catquest'},
    {'catquest','wowvoice','wayfarer'}, {'catquest','wayfarer','wowvoice'},
    {'wayfarer','wowvoice','catquest'}, {'wayfarer','catquest','wowvoice'}}) do
    assert(WV:SetVoicePriority(order))
    for _, sex in ipairs({2, 3}) do
        playerSex = sex
        for _, section in ipairs({'a', 'c', 'p'}) do
            start(section)
            local expected = english and S.Text(179, section) or gameText
            assert(head.Body:GetText() == (expected or gameText), 'locale priority must apply to either audio source and each stage')
        end
    end
end
for _, source in ipairs({'wowvoice','catquest','wayfarer'}) do
    assert(S.DisplayText({questId=179,section='a',audioSourceID=source,text=gameText})
        == (english and texts['179a'].female or gameText))
    assert(S.DisplayText({questId=179,section='a',audioSourceID=source,text=''}) == texts['179a'].female)
end

-- Save the original English/Russian game capture, not substituted subtitles.
start('a')
Q:SaveSession()
local saved = TalkingHeadRuQueueDB
assert(saved.records[1].context.text == gameText)
Q:Clear()
Q.loggingOut = nil
TalkingHeadRuQueueDB = saved
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

-- Bundled text remains available as metadata, but cannot start an unvoiced head.
Q:Clear()
local isLoaded = C_AddOns.IsAddOnLoaded
C_AddOns.IsAddOnLoaded = function() return false end
assert(S.DisplayText({questId = 179, section = 'a', text = gameText})
    == (english and texts['179a'].common or gameText))
assert(not WV:ReplayQuest(179) and not head:IsShown())
local missingID = 999997
assert(not texts[missingID .. 'a'] and not WowVoiceDur[missingID .. 'a'])
texts[missingID .. 'a'] = {common = 'Короткое русское описание.'}
local context = {questId = missingID, section = 'a', text = string.rep('word ', 30)}
assert(S.DisplayText(context) == (english and texts[missingID .. 'a'].common or context.text))
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
texts['179a'], texts['179c'], texts['179p'], UnitSex = description, completion, progress, unitSex
print('PASS: ' .. GetLocale() .. ' independent quest texts, six audio orders, all preview sources, stages/sex variants, reload, missing translations, unavailable audio and current journal text')

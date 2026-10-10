event('ADDON_LOADED')
local WV, L, Q = WowVoice, WowVoiceLocale, WowVoice.questQueue
local english = GetLocale() ~= 'ruRU'
assert(L.isEnglish == english)
assert(L['Автовоспроизведение'] == (english and 'Autoplay' or 'Автовоспроизведение'))
command('options')
local options = frames.WowVoiceOptionsPanel
assert(options.LockFrames.Label:GetText() == 'Заблокировать фреймы')
assert(options.Buttons.compareVoices:GetText() == 'Послушать озвучку')
assert(options.LockFrames.Label:GetFont() == L.cyrillicFont)
local ok, reason = WV:SetHeadScale(0)
assert(not ok and reason == 'Введите масштаб от 50 до 150%.')
ok, reason = WV:SetQuestQueuePosition('invalid', 0)
assert(not ok and reason == 'Введите числа в поля X и Y. Допускаются минус и дробная часть.')
options.QueueHeightInput:SetText('0')
options.QueueHeightInput.scripts.OnEnterPressed(options.QueueHeightInput)
assert(options.Status:GetText() == 'Введите высоту от 280 до 600.')
assert(options.Status:GetFont() == L.cyrillicFont)
local schema = CatQuestVoicePack.schemaVersion
CatQuestVoicePack.schemaVersion = 999
WV:RefreshAudioSourceOptions()
assert(options.AudioSourceWarning.message == 'формат индекса CatQuest_Voices не поддерживается')
CatQuestVoicePack.schemaVersion = schema
WV:RefreshAudioSourceOptions()

local function record(id, name, title, body)
    return { context = { questId = id, section = 'a', title = title, text = body,
        speaker = { npcID = id, name = name } } }
end
local ru = record(179, 'Русское имя', 'Русское задание', 'Русская речь. Ёж идёт к маяку.')
local en = record(999997, 'English NPC', 'English quest', 'English dialogue.')
-- A voiced fixture without Russian metadata exercises native English fonts.
WowVoiceDur['999997a'] = 10
Q:Add(ru); Q:Add(en); assert(Q:Start(ru))
local head, player = frames.TalkingHeadRu, frames.WowVoiceQuestQueuePlayer
assert(head.Name:GetText() == ru.context.speaker.name)
assert(head.Body:GetText() == (english and WowVoiceAudioSources.Text(179, 'a') or ru.context.text))
assert(head.Name:GetFont() == 'Fonts\\MORPHEUS_CYR.TTF')
assert(head.Body:GetFont() == L.cyrillicFont)
assert(head.TextMeasure:GetFont() == head.Body:GetFont())
assert(player.Autoplay.Label:GetText() == (english and 'Autoplay' or 'Автовоспроизведение'))
assert(player.Next.Label:GetText() == (english and 'Next' or 'Далее'))
local toolbar = player.Next:GetParent()
local function bounds(button)
    local center = button:GetCenter()
    return center - button:GetWidth() / 2, center + button:GetWidth() / 2
end
local _, clearRight = bounds(toolbar.Clear)
local autoLeft, autoRight = bounds(player.Autoplay)
local nextLeft = bounds(player.Next)
assert(autoLeft >= clearRight and nextLeft >= autoRight, 'toolbar buttons must not overlap in either locale')
assert(math.abs((autoLeft - clearRight) - (nextLeft - autoRight)) < 0.001,
    'toolbar must distribute both gaps evenly with translated labels')
local sawName, sawTitle, sawNext, sawClear = false, false, false, false
for _, frame in ipairs(allFrames) do
    if frame.Name and frame.Name:GetText() == ru.context.speaker.name then
        sawName = true
        assert(frame.Name:GetFont() == L.cyrillicFont or frame.Name:GetFont() == 'Fonts\\MORPHEUS_CYR.TTF')
    end
    if frame.Title and frame.Title:GetText() == ru.context.title then
        sawTitle = true
        assert(frame.Title:GetFont() == L.cyrillicFont)
    end
    if frame.Label and frame.Label.GetText then
        local label = frame.Label:GetText()
        if label == (english and 'Play next' or 'Следующим') then sawNext = true end
        if label == (english and 'Clear all' or 'Очистить всё') then sawClear = true end
    end
end
assert(sawName and sawTitle and sawNext and sawClear)
-- Reused regions must recover their native font for English content.
assert(Q:Start(en))
assert(head.Name:GetText() == 'English NPC')
assert(head.Name:GetFont() == (english and 'Fonts\\MORPHEUS.ttf' or 'Fonts\\MORPHEUS_CYR.TTF'))
assert(head.Body:GetText() == 'English dialogue.')
assert(head.Body:GetFont() == (english and 'Fonts\\FRIZQT__.TTF' or L.cyrillicFont))
local size = select(2, head.Body:GetFont())
L.SetContentText(head.Body, 'English + русский')
assert(head.Body:GetFont() == L.cyrillicFont and select(2, head.Body:GetFont()) == size)
L.SetContentText(head.Body, 'English again')
assert((head.Body:GetFont() ~= L.cyrillicFont) == english)
Q:Clear()

-- The source still supplies Russian text and the same sound file on an English client.
assert(WV:SetSharedQuestVoice('catquest'))
assert(WV:ReplayQuest(179))
assert(plays[#plays].file:find('CatQuest_Voices', 1, true))
assert(head.Body:GetText():find('[\208-\211][\128-\191]'))
assert(head.Body:GetFont() == L.cyrillicFont)
Q:Clear()

-- Unlock instructions follow the Russian settings UI on every client.
local previewPlays = #plays
WV:SetWindowsUnlocked(true)
assert(WV:IsWindowsUnlocked() and head:IsShown())
assert(head.Body:GetText():find('Это тест говорящей головы.', 1, true) == 1,
    'unlock instructions must stay Russian on English clients')
assert(head.Body:GetText():find('Кнопка центрирования', 1, true))
assert(head.Body:GetFont() == L.cyrillicFont and head.TextMeasure:GetFont() == L.cyrillicFont)
assert(#plays == previewPlays, 'unlock preview must remain silent')
WV:SetWindowsUnlocked(false)
-- Font changes preserve layout settings, tolerate missing client faces and do
-- not change shared font objects. A recycled region recovers its Latin face.
local region = head:CreateFontString(nil, 'ARTWORK', 'QuestTitleFont')
region:SetFont('Fonts/MORPHEUS.ttf', 19, 'OUTLINE')
L.SetContentText(region, 'Имя Ёж')
assert(region:GetFont() == (english and 'Fonts\\MORPHEUS_CYR.TTF' or 'Fonts/MORPHEUS.ttf'))
local _, height, flags = region:GetFont()
assert(height == 19 and flags == 'OUTLINE')
L.SetContentText(region, 'English')
assert(region:GetFont() == 'Fonts/MORPHEUS.ttf')
local setFont = region.SetFont
function region:SetFont(file, height, flags)
    if file == 'Fonts\\MORPHEUS_CYR.TTF' then return false end
    setFont(self, file, height, flags)
    return true
end
L.SetContentText(region, 'Русское имя')
assert(region:GetFont() == (english and L.cyrillicFont or 'Fonts/MORPHEUS.ttf'))
L.SetContentText(region, 'English')
assert(region:GetFont() == 'Fonts/MORPHEUS.ttf')
function region:SetFont(file, height, flags)
    if file:find('_CYR', 1, true) then return false end
    setFont(self, file, height, flags)
    return true
end
L.SetContentText(region, 'Русское имя')
assert(region:GetFont() == 'Fonts/MORPHEUS.ttf')
WowVoiceDur['999997a'] = nil
print('PASS: ' .. GetLocale() .. ' English player/Russian settings, Blizzard quest fonts, Cyrillic fallback, reused regions and original voice source')

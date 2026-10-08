-- Player/head labels follow the client language; settings stay Russian.
-- Voice-pack content retains its language.
local locale = type(GetLocale) == "function" and GetLocale() or "ruRU"
local english = locale == "enUS" or locale == "enGB"
local translations = {
    ["Автовоспроизведение"] = "Autoplay",
    ["Далее"] = "Next",
    ["Очистить всё"] = "Clear all",
    ["Следующим"] = "Play next",
    ["Неизвестный NPC"] = "Unknown NPC",
    ["Задание "] = "Quest ",
    ["Квест "] = "Quest ",
    ["Сдача: "] = "Turn-in: ",
    ["Описание задания"] = "Quest description",
    ["Выполнение задания"] = "Quest progress",
    ["Завершение задания"] = "Quest completion",
    ["Текст задания недоступен."] = "Quest text is unavailable.",
    ["Слушать"] = "Listen",
    ["Читать"] = "Read",
    ["Тест говорящей головы"] = "Talking head preview",
    ["Ваш персонаж"] = "Your character",
    ["Это тест говорящей головы. Слева показана модель вашего персонажа. Звук в этом режиме не запускается.\n\n"] = "This is a talking head preview. Your character appears on the left. No audio plays in this mode.\n\n",
    ["Здесь будет текст задания. Каждый блок остаётся неподвижным, пока идёт его чтение. "] = "Quest text appears here. Each block stays still while it is being read. ",
    ["Затем короткий плавный сдвиг открывает продолжение, сохраняя две строки предыдущего блока. "] = "A short, smooth scroll then reveals the next block, keeping two lines of the previous block visible. ",
    ["Последний блок раскрывается заранее и стоит на месте до конца реплики.\n\n"] = "The last block appears early and stays in place until the dialogue ends.\n\n",
    ["Кнопка центрирования выравнивает окно по горизонтали, сохраняя высоту.\n\n"] = "The center button aligns the panel horizontally while keeping its height.\n\n",
    ["Только во время теста панель можно перемещать мышью. В обычном режиме её положение закреплено. "] = "You can drag the panel during the preview. Its position is locked during normal playback. ",
    ["Тест повторяется каждые 30 секунд и прекращается при закрытии настроек."] = "The preview repeats every 30 seconds and stops when you close settings.",
    ["положение говорящей головы сброшено"] = "talking head position reset",
    ["TalkingHead Ru: озвучка выключена. Включить: /thead on"] = "TalkingHead Ru: Playback is disabled. Enable it with /thead on.",
    ["А"] = "A",
    ["А\nА"] = "A\nA",
    ["озвучка выключена. Включить: /thead on"] = "Playback is disabled. Enable it with /thead on.",
    ["для описания этого квеста нет записи в установленном аудиопаке"] = "No description recording for this quest in the installed voice packs.",
    ["не удалось воспроизвести описание квеста %d"] = "Could not play the description of quest %d.",
    ["Озвучка: WowVoice — https://boosty.to/wowvoice; Cathey — https://boosty.to/cathey"] = "Voices: WowVoice — https://boosty.to/wowvoice; Cathey — https://boosty.to/cathey",
    ["Спасибо, что поддерживаешь WowVoice! |cffffd100Ctrl+C|r скопирует ссылку — вставь её в браузер:"] = "Thank you for supporting WowVoice! Press |cffffd100Ctrl+C|r to copy the link, then paste it into your browser:",
    ["Закрыть"] = "Close",
}
local L = setmetatable({ isEnglish = english, isRussian = locale == "ruRU" }, {
    __index = function(_, key) return english and translations[key] or key end,
})
WowVoiceLocale = L

-- Keep the quest/UI font family chosen by Blizzard. The English faces lack
-- Cyrillic glyphs; use their built-in Russian counterparts for imported text.
L.cyrillicFont = "Fonts\\FRIZQT___CYR.TTF"
local cyrillicFaces = {
    ["fonts\\frizqt__.ttf"] = L.cyrillicFont,
    ["fonts\\morpheus.ttf"] = "Fonts\\MORPHEUS_CYR.TTF",
    ["fonts\\skurri.ttf"] = "Fonts\\SKURRI_CYR.TTF",
}
local originals = setmetatable({}, { __mode = "k" })
function L.ApplyContentFont(region, text, sourceFace)
    if not english then return end
    local face, size, flags = region:GetFont()
    if not face then return end
    -- A native message region can change its font between appearances.
    if sourceFace then originals[region] = sourceFace
    elseif not originals[region] then originals[region] = face end
    local cyrillic = type(text) == "string" and text:find("[\208-\211][\128-\191]")
    local original = originals[region]
    local wanted = original
    if cyrillic then
        local key = original:lower():gsub("/", "\\")
        wanted = cyrillicFaces[key] or (key:find("_cyr", 1, true) and original) or L.cyrillicFont
    end
    if face ~= wanted then
        local ok = region:SetFont(wanted, size, flags)
        -- A client missing a localized title face can still use the quest body
        -- face. Never leave a region without a font if both loads fail.
        if ok == false then
            if not cyrillic or wanted == L.cyrillicFont
                or region:SetFont(L.cyrillicFont, size, flags) == false then
                region:SetFont(face, size, flags)
            end
        end
    end
end
function L.SetContentText(region, text)
    L.ApplyContentFont(region, text)
    region:SetText(text)
end

-- Settings supply Russian text directly; only adapt the font here.
function L.SetOptionsText(widget, text)
    local region = widget.GetFontString and widget:GetFontString() or widget
    if region and region.GetFont then L.ApplyContentFont(region, text) end
    widget:SetText(text)
end

-- Apply the font only to the tooltip's current lines, restoring it on hide.
local tooltips = setmetatable({}, { __mode = "k" })
function L.OptionsTooltip(tooltip)
    if not english or not tooltip.NumLines or not tooltip.GetName or not tooltip.HookScript then return end
    local regions = tooltips[tooltip]
    if not regions then
        regions = {}
        tooltips[tooltip] = regions
        tooltip:HookScript("OnHide", function()
            for region in pairs(regions) do L.ApplyContentFont(region, ""); regions[region] = nil end
        end)
    end
    for i = 1, tooltip:NumLines() do
        for _, side in ipairs({ "Left", "Right" }) do
            local region = _G[tooltip:GetName() .. "Text" .. side .. i]
            if region then
                L.ApplyContentFont(region, region:GetText())
                regions[region] = true
            end
        end
    end
end

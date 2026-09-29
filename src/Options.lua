-- Built-in options page: Settings -> AddOns -> WowVoice.
local WV = _G.WowVoice
local panel, category

-- Previously published packs predate explicit upstream version metadata.
local legacySourceVersions = {
    WowVoiceSounds = { ["1.0.3-forever.1"] = "1.0.1" },
}

local function refreshVoicePreference()
    if not panel.SharedVoiceButtons then return end
    local source, reason = WowVoiceAudioSources.Status()
    panel.SharedVoiceCaption:SetAlpha(source and 1 or 0.45)
    for id, button in pairs(panel.SharedVoiceButtons) do
        button:SetChecked(WV:GetSharedQuestVoice() == id)
        button:SetEnabled(source ~= nil)
        button:SetAlpha(source and 1 or 0.45)
        local selected = WV:GetSharedQuestVoice() == id
        button.Border:SetVertexColor(selected and 1 or 0.6, selected and 0.82 or 0.6, selected and 0.25 or 0.6)
    end
    panel.SharedVoiceTooltip.message = source
        and "Выбранная озвучка используется при получении и сдаче заданий, а также в журнале и списке заданий. Если запись есть только у одного источника, используется она."
        or ("Для выбора установите и включите CatQuest Voices "
            .. tostring(WowVoiceCatQuestAudio and WowVoiceCatQuestAudio.sourceVersion or "")
            .. ". Сейчас используется WowVoice.\n" .. tostring(reason or ""))
end

local function refreshVersions()
    refreshVoicePreference()
    local source = WowVoiceAudioSources.Status()
    panel.AudioSourceCaption:SetText("Озвучка CatQuest:")
    panel.AudioSourceCaption:SetWidth(math.ceil(panel.AudioSourceCaption:GetStringWidth()) + 2)
    local metadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local function field(addon, key)
        local value = metadata and metadata(addon, key)
        return type(value) == "string" and value ~= "" and value or nil
    end
    local installed = field("CatQuest_Voices", "Version")
    local supported = WowVoiceCatQuestAudio and WowVoiceCatQuestAudio.sourceVersion
    local incompatible = not source and WowVoiceAudioSources.Loaded("CatQuest_Voices")
        and installed and supported and installed ~= supported
    local warning = panel.AudioSourceWarning
    if GameTooltip and GameTooltip:IsOwned(warning) then GameTooltip:Hide() end
    warning.message = incompatible and ("Установлена: " .. installed .. ". Поддерживается: " .. supported
        .. ".\nДополнительная озвучка недоступна.\nУстановите совместимую версию CatQuest Voices"
        .. " или обновите WowVoice Talking Head до версии с её поддержкой.") or nil
    if incompatible then warning:Show() else warning:Hide() end
    local width = 0
    for addon, text in pairs(panel.VersionLabels) do
        local version
        if addon == "AudioSource" then
            version = source and source.version or (incompatible and installed) or "недоступна"
            if incompatible then text:SetTextColor(1, 0.25, 0.25)
            else text:SetTextColor(0.7, 0.7, 0.7) end
        else
            local installed = field(addon, "Version")
            version = installed
            if legacySourceVersions[addon] then
                version = field(addon, "X-Source-Version") or legacySourceVersions[addon][installed]
            end
            if not version then
                version = metadata and not installed and not field(addon, "Title")
                    and "не установлен" or "версия не указана"
            end
        end
        text:SetWidth(124)
        text:SetText(version)
        width = math.max(width, math.ceil(text:GetStringWidth()) + 2)
    end
    for _, text in pairs(panel.VersionLabels) do text:SetWidth(math.min(124, width)) end
end

local function status(text)
    panel.Status:SetText(text or "")
end

function WV:RefreshAudioSourceOptions()
    if panel and panel:IsShown() then refreshVersions() end
end

local function refreshScale()
    if panel.draggingScale then return end
    local percent = math.floor(WV:GetHeadScale() * 100 + 0.5)
    panel.refreshingScale = true
    panel.ScaleSlider:SetValue(percent)
    panel.ScaleInput:SetText(tostring(percent))
    panel.refreshingScale = false
end

local function coordinate(value)
    if math.abs(value) < 0.005 then value = 0 end
    return string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", "")
end

local function refreshPosition(force)
    if panel.editingPosition and not force then return end
    local x, y = WV:GetHeadAnchorPosition()
    x, y = coordinate(x), coordinate(y)
    if panel.PositionX:GetText() ~= x then panel.PositionX:SetText(x) end
    if panel.PositionY:GetText() ~= y then panel.PositionY:SetText(y) end
end

function WV:RefreshQuestQueuePositionOptions(force)
    if not panel or not panel:IsShown() or not panel.QueuePositionX then return end
    if panel.editingQueuePosition and not force then return end
    if force then
        panel.editingQueuePosition = nil
        panel.QueuePositionX:ClearFocus()
        panel.QueuePositionY:ClearFocus()
    end
    local x, y = self:GetQuestQueuePosition()
    x, y = coordinate(x), coordinate(y)
    if panel.QueuePositionX:GetText() ~= x then panel.QueuePositionX:SetText(x) end
    if panel.QueuePositionY:GetText() ~= y then panel.QueuePositionY:SetText(y) end
end

function WV:RefreshHeadPositionOptions()
    if not panel or not panel:IsShown() then return end
    -- Mouse positioning replaces any uncommitted numeric draft. Refresh only
    -- these fields while moving; the other controls do not need per-frame work.
    if panel.editingPosition then
        panel.editingPosition = nil
        panel.PositionX:ClearFocus()
        panel.PositionY:ClearFocus()
    end
    refreshPosition(true)
end

function WV:RefreshHeadOptions()
    if not panel or not panel:IsShown() then return end
    refreshScale()
    local selected = WV:GetHeadAnchor()
    for point, dot in pairs(panel.AnchorPoints) do
        dot:SetChecked(point == selected)
        if point == selected then dot.Border:SetVertexColor(1, 0.82, 0.25)
        else dot.Border:SetVertexColor(0.6, 0.6, 0.6) end
    end
    refreshPosition()
    panel.AutoPlayAccept:SetChecked(WowVoiceDB.autoPlayAccept == true)
    panel.AutoPlayTurnIn:SetChecked(WowVoiceDB.autoPlayTurnIn ~= false)
    local autoPlay = WowVoiceDB.autoPlay ~= false
    panel.AutoPlay:SetChecked(autoPlay)
    for _, control in ipairs({ panel.AutoPlayAccept, panel.AutoPlayTurnIn }) do
        control:SetEnabled(autoPlay)
        control:SetAlpha(autoPlay and 1 or 0.45)
        control.Label:SetAlpha(autoPlay and 1 or 0.45)
        control.Description:SetAlpha(autoPlay and 1 or 0.45)
    end
    if panel.QueueHeight then
        panel.QueueDescriptionsOnly:SetChecked(WowVoiceDB.queueDescriptionsOnly == true)
        for _, control in ipairs({ panel.QueueDescriptionsOnly, panel.QueueHeight, panel.QueueScale,
            panel.Buttons.queueMove, panel.Buttons.queueReset, panel.Buttons.applyQueuePosition }) do
            control:SetEnabled(autoPlay)
            control:SetAlpha(autoPlay and 1 or 0.45)
        end
        for _, label in ipairs(panel.QueueLabels) do label:SetAlpha(autoPlay and 1 or 0.45) end
        for _, field in ipairs({ panel.QueueHeightInput, panel.QueueScaleInput, panel.QueuePositionX, panel.QueuePositionY }) do
            field:EnableMouse(autoPlay)
            field:SetAlpha(autoPlay and 1 or 0.45)
            if not autoPlay then field:ClearFocus() end
        end
        panel.refreshingQueue = true
        panel.QueueHeight:SetValue(WV:GetQuestQueueHeight())
        panel.QueueHeightInput:SetText(tostring(WV:GetQuestQueueHeight()))
        local percent = math.floor(WV:GetQuestQueueScale() * 100 + 0.5)
        panel.QueueScale:SetValue(percent)
        panel.QueueScaleInput:SetText(tostring(percent))
        panel.refreshingQueue = nil
        panel.Buttons.queueMove:SetText(WV:IsQuestQueuePreview() and "Готово" or "Переместить")
        self:RefreshQuestQueuePositionOptions(not autoPlay)
    end
end

local function createPanel()
    panel = CreateFrame("Frame", "WowVoiceOptionsPanel")
    panel:Hide()
    panel.Buttons = {}
    local scroll = CreateFrame("ScrollFrame", "WowVoiceOptionsScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 0)
    local content = CreateFrame("Frame", nil, scroll)
    local queueOptions = WV.questQueue and WV.questQueue.enabled
    local lowerOffset = 40 + (queueOptions and 424 or 0)
    content:SetSize(584, 818 + lowerOffset)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(self, width)
        content:SetWidth(math.max(584, width))
        self:UpdateScrollChildRect()
    end)
    panel.Scroll, panel.Content = scroll, content
    local function label(text, font, x, y, width, height)
        local fs = content:CreateFontString(nil, "ARTWORK", font)
        fs:SetPoint("TOPLEFT", content, "TOPLEFT", x, y)
        fs:SetSize(width, height)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetText(text)
        return fs
    end
    label(WV.displayName, "GameFontNormalLarge", 16, -16, 280, 28)
    panel.VersionLabels = {}
    for index, item in ipairs({
        { "WowVoiceTalkingHead", "Аддон" },
        { "WowVoiceSounds", "Озвучка WowVoice" },
        { "AudioSource", "Доп. озвучка" },
    }) do
        local text = label("", "GameFontHighlightSmall", 0, 0, 124, 12)
        text:ClearAllPoints()
        text:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -16 - (index - 1) * 13)
        text:SetJustifyH("LEFT")
        text:SetTextColor(0.7, 0.7, 0.7)
        local caption = label(item[2] .. ":", "GameFontHighlightSmall", 0, 0, 112, 12)
        caption:ClearAllPoints()
        caption:SetPoint("TOPRIGHT", text, "TOPLEFT", -8, 0)
        caption:SetJustifyH("RIGHT")
        caption:SetTextColor(0.7, 0.7, 0.7)
        panel.VersionLabels[item[1]] = text
        if item[1] == "AudioSource" then
            caption:SetWordWrap(false)
            panel.AudioSourceCaption = caption
            local warning = CreateFrame("Frame", nil, content)
            warning:SetPoint("TOPLEFT", caption, "TOPLEFT", -2, 2)
            warning:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", 2, -2)
            warning:EnableMouse(true)
            warning:SetScript("OnEnter", function(self)
                if not self.message then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("Несовместимая версия CatQuest Voices", 1, 0.25, 0.25)
                GameTooltip:AddLine(self.message, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            local function hideTooltip(self)
                if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
            end
            warning:SetScript("OnLeave", hideTooltip)
            warning:SetScript("OnHide", hideTooltip)
            panel.AudioSourceWarning = warning
        end
    end
    refreshVersions()
    label("При перетаскивании масштаба предпросмотр появится автоматически.\n"
        .. "«Тест / переместить» позволяет перетащить окно. Положение сохраняется.",
        "GameFontHighlightSmall", 20, -58, 540, 28)
    local function section(text, y)
        local heading = label(text, "GameFontNormalLarge", 20, y, 540, 22)
        local line = content:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(0.6, 0.52, 0.32, 0.45)
        line:SetSize(544, 1)
        line:SetPoint("TOPLEFT", content, "TOPLEFT", 20, y - 24)
        return heading, line
    end
    section("Говорящая голова", -94)
    section("Воспроизведение", -460)

    local function discardPosition()
        panel.editingPosition = nil
        if panel.PositionX then
            panel.PositionX:ClearFocus()
            panel.PositionY:ClearFocus()
            refreshPosition(true)
        end
    end

    local function button(key, text, x, width, callback, y)
        local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        b:SetSize(width, 26)
        b:SetPoint("TOPLEFT", content, "TOPLEFT", x, y or -128)
        b:SetText(text)
        b:SetScript("OnClick", callback)
        panel.Buttons[key] = b
    end
    -- Match the compact numeric fields used by Questie's AceGUI slider widget.
    local function numericField(width, x, y)
        local field = CreateFrame("EditBox", nil, content, "BackdropTemplate")
        field:SetSize(width, 20)
        field:SetPoint("TOPLEFT", content, "TOPLEFT", x, y)
        field:SetAutoFocus(false)
        field:SetFontObject("GameFontHighlightSmall")
        field:SetJustifyH("CENTER")
        field:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\ChatFrame\\ChatFrameBackground", tile = true, edgeSize = 1, tileSize = 5 })
        field:SetBackdropColor(0, 0, 0, 0.5)
        field:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
        field:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(0.5, 0.5, 0.5, 1) end)
        field:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8) end)
        return field
    end
    button("test", "Тест / переместить", 20, 170, function()
        local ok, reason = WV:ToggleHeadPreview()
        status(ok and "Тест без звука: перетащите окно и оцените подсветку кнопок озвучки. Повторное нажатие остановит тест." or reason)
    end)
    button("center", "Центр по горизонтали", 202, 170, function()
        discardPosition()
        WV:CenterTalkingHead()
        status("Окно выровнено по центру по горизонтали.")
    end)
    button("reset", "Сбросить положение", 384, 180, function()
        discardPosition()
        WV:ResetHeadPosition()
        status("Положение сброшено: автоматическая привязка снизу над панелью действий.")
    end)
    label("Масштаб панели", "GameFontNormal", 20, -327, 280, 20)
    local slider = CreateFrame("Slider", "WowVoiceHeadScaleSlider", content, "OptionsSliderTemplate")
    panel.ScaleSlider = slider
    slider:SetPoint("TOPLEFT", content, "TOPLEFT", 24, -356)
    slider:SetSize(260, 17)
    slider:SetMinMaxValues(50, 150)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(false)
    for _, suffix in ipairs({ "Low", "High", "Text" }) do
        local text = slider[suffix] or _G["WowVoiceHeadScaleSlider" .. suffix]
        if text then text:Hide() end
    end
    label("50%", "GameFontHighlightSmall", 20, -379, 60, 16)
    local high = label("150%", "GameFontHighlightSmall", 228, -379, 60, 16)
    high:SetJustifyH("RIGHT")
    local input = numericField(48, 308, -354)
    panel.ScaleInput = input
    input:SetNumeric(true)
    input:SetMaxLetters(3)
    label("%", "GameFontHighlight", 362, -357, 18, 20)
    local function applyScale(percent)
        discardPosition()
        if percent ~= math.floor(WV:GetHeadScale() * 100 + 0.5) then
            local ok, reason = WV:SetHeadScale(percent / 100)
            if ok then WV:EnsureHeadPreview(true); WV:FinishAutoHeadPreview(2) end
            status(ok and "" or reason)
        else
            status()
        end
        refreshScale()
    end
    local function finishScaleDrag()
        if not panel.draggingScale then return end
        panel.draggingScale = nil
        local ok, reason = WV:EndHeadScalePreview()
        WV:FinishAutoHeadPreview(0)
        status(ok and "" or reason)
        refreshScale()
    end
    local function beginScaleDrag()
        if panel.draggingScale then return end
        discardPosition()
        WV:EnsureHeadPreview(true)
        panel.draggingScale = true
        WV:BeginHeadScalePreview()
        input:ClearFocus()
    end
    slider:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        beginScaleDrag()
    end)
    slider:SetScript("OnValueChanged", function(_, value)
        if panel.refreshingScale then return end
        local percent = math.floor(value + 0.5)
        -- Native sliders can change value before delivering OnMouseDown.
        if panel.draggingScale or (IsMouseButtonDown and IsMouseButtonDown("LeftButton")) then
            beginScaleDrag()
            input:SetText(tostring(percent))
            local _, reason = WV:SetHeadScale(value / 100, true)
            status(reason)
            return
        end
        applyScale(percent)
    end)
    slider:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then finishScaleDrag() end
    end)
    slider:SetScript("OnUpdate", function()
        -- Also finish if the mouse was released outside the slider.
        if panel.draggingScale and IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            finishScaleDrag()
        end
    end)
    input:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        local percent = text:match("^%d+$") and tonumber(text)
        if not percent or percent < 50 or percent > 150 then
            status("Введите целое число от 50 до 150.")
            self:SetFocus()
            return
        end
        discardPosition()
        local ok, reason = WV:SetHeadScale(percent / 100)
        if ok then WV:EnsureHeadPreview(true); WV:FinishAutoHeadPreview(2) end
        status(ok and "" or reason)
        self:ClearFocus()
    end)
    input:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        refreshScale()
        status()
    end)
    input:SetScript("OnEditFocusLost", refreshScale)
    button("resetScale", "Сбросить масштаб", 384, 180, function()
        discardPosition()
        local ok, reason = WV:SetHeadScale(1)
        status(ok and "Масштаб панели сброшен: 100%." or reason)
    end, -351)
    label("Точка привязки и масштабирования", "GameFontNormal", 20, -169, 540, 20)
    local diagram = CreateFrame("Frame", nil, content, "BackdropTemplate")
    diagram:SetPoint("TOPLEFT", content, "TOPLEFT", 36, -211)
    diagram:SetSize(180, 72)
    diagram:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    diagram:SetBackdropColor(0.08, 0.08, 0.08, 0.8)
    diagram:SetBackdropBorderColor(0.55, 0.49, 0.32, 1)
    panel.AnchorPoints, panel.AnchorDiagram = {}, diagram
    label("Координаты точки привязки", "GameFontNormal", 254, -218, 310, 20)
    for _, point in ipairs({ "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }) do
        local dot = CreateFrame("CheckButton", nil, diagram)
        dot:SetSize(32, 32)
        dot:SetPoint("CENTER", diagram, point, 0, 0)
        -- The old radio sheet contains tiny 16px states. Layer the client's
        -- antialiased 128px circle instead, retaining a generous click target.
        local function circle(size, layer, r, g, b, alpha)
            local t = dot:CreateTexture(nil, layer)
            t:SetPoint("CENTER", dot, "CENTER", 0, 0)
            t:SetSize(size, size)
            t:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
            t:SetVertexColor(r, g, b, alpha or 1)
            return t
        end
        dot.Border = circle(28, "BACKGROUND", 0.6, 0.6, 0.6)
        circle(24, "BORDER", 0.06, 0.06, 0.06)
        dot:SetCheckedTexture(circle(12, "ARTWORK", 1, 0.82, 0.25))
        dot:SetHighlightTexture(circle(28, "HIGHLIGHT", 1, 0.82, 0.25, 0.18), "ADD")
        dot:SetScript("OnClick", function()
            finishScaleDrag()
            input:ClearFocus()
            discardPosition()
            WV:EnsureHeadPreview()
            local ok, reason = WV:SetHeadAnchor(point)
            if ok then WV:FinishAutoHeadPreview(2) end
            status(ok and "" or reason)
        end)
        panel.AnchorPoints[point] = dot
    end
    local function applyPosition()
        local function number(text)
            text = text:match("^%s*(.-)%s*$"):gsub(",", ".")
            return text:match("^[+-]?%d*%.?%d+$") and tonumber(text)
        end
        local x, y = number(panel.PositionX:GetText()), number(panel.PositionY:GetText())
        if not x or not y then
            status("Введите числа в поля X и Y. Например: -120 или 35,5.")
            return
        end
        finishScaleDrag()
        WV:EnsureHeadPreview()
        local ok, reason = WV:SetHeadAnchorPosition(x, y)
        if ok then discardPosition(); WV:FinishAutoHeadPreview(2) end
        status(ok and "" or reason)
    end
    local function positionInput(key, caption, x)
        label(caption, "GameFontHighlightSmall", x, -252, 20, 20)
        local field = numericField(78, x + 24, -248)
        field:SetMaxLetters(12)
        field:SetScript("OnEditFocusGained", function() panel.editingPosition = true end)
        field:SetScript("OnEnterPressed", applyPosition)
        field:SetScript("OnEscapePressed", function() discardPosition(); status() end)
        panel[key] = field
    end
    positionInput("PositionX", "X", 254)
    positionInput("PositionY", "Y", 364)
    panel.PositionX:SetScript("OnTabPressed", function(self) self:ClearFocus(); panel.PositionY:SetFocus() end)
    panel.PositionY:SetScript("OnTabPressed", function(self) self:ClearFocus(); panel.PositionX:SetFocus() end)
    button("applyPosition", "Задать", 478, 86, applyPosition, -245)
    panel.Status = label("", "GameFontHighlightSmall", 20, -408, 540, 36)
    panel.AutoPlay = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    panel.AutoPlay:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -496)
    panel.AutoPlay:SetSize(26, 26)
    label("Автозапуск озвучки", "GameFontHighlight", 48, -503, 506, 22)
    panel.AutoPlay:SetScript("OnClick", function(self) WV:SetAutoPlayEnabled(self:GetChecked() == true) end)
    panel.AutoPlayAccept = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    panel.AutoPlayAccept:SetPoint("TOPLEFT", content, "TOPLEFT", 42, -536)
    panel.AutoPlayAccept:SetSize(26, 26)
    panel.AutoPlayAccept.Label = label("При получении задания", "GameFontHighlight", 74, -543, 480, 22)
    panel.AutoPlayAccept:SetScript("OnClick", function(self)
        WV:SetAutoPlayAcceptEnabled(self:GetChecked() == true)
    end)
    panel.AutoPlayAccept.Description = label("Если выключено, запускайте описание кнопкой в журнале или списке заданий.",
        "GameFontHighlightSmall", 74, -571, 480, 32)
    panel.AutoPlayTurnIn = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    panel.AutoPlayTurnIn:SetPoint("TOPLEFT", content, "TOPLEFT", 42, -620)
    panel.AutoPlayTurnIn:SetSize(26, 26)
    panel.AutoPlayTurnIn.Label = label("При сдаче задания", "GameFontHighlight", 74, -627, 480, 22)
    panel.AutoPlayTurnIn:SetScript("OnClick", function(self)
        WV:SetAutoPlayTurnInEnabled(self:GetChecked() == true)
    end)
    panel.AutoPlayTurnIn.Description = label("Управляет всеми репликами сдачи: промежуточными и завершающей.",
        "GameFontHighlightSmall", 74, -655, 480, 32)
    if queueOptions then
        panel.QueueHeading, panel.QueueDivider = section("Плейлист", -700)
        panel.QueueDescriptionsOnly = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
        panel.QueueDescriptionsOnly:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -736)
        panel.QueueDescriptionsOnly:SetSize(26, 26)
        panel.QueueDescriptionsOnly.Label = label("Только описания заданий", "GameFontHighlight", 48, -743, 506, 22)
        panel.QueueDescriptionsOnly.Description = label("Не добавлять реплики выполнения и завершения заданий.",
            "GameFontHighlightSmall", 48, -771, 506, 28)
        panel.QueueDescriptionsOnly:SetScript("OnClick", function(self)
            WV:SetQueueDescriptionsOnly(self:GetChecked() == true)
        end)
        button("queueMove", "Переместить", 20, 170, function()
            WV:PreviewQuestQueue(not WV:IsQuestQueuePreview())
            WV:RefreshHeadOptions()
        end, -808)
        button("queueReset", "Сбросить", 202, 170, function()
            WV:ResetQuestQueueLayout()
            WV:PreviewQuestQueue(true)
            WV:RefreshQuestQueuePositionOptions(true)
            WV:RefreshHeadOptions()
        end, -808)
        local heightCaption = label("Максимальная высота", "GameFontNormal", 20, -850, 280, 20)
        panel.QueueHeight = CreateFrame("Slider", "WowVoiceQueueHeightSlider", content, "OptionsSliderTemplate")
        local heightSlider = panel.QueueHeight
        heightSlider:SetPoint("TOPLEFT", content, "TOPLEFT", 24, -880)
        heightSlider:SetSize(260, 17)
        heightSlider:SetMinMaxValues(280, 600)
        heightSlider:SetValueStep(1)
        heightSlider:SetObeyStepOnDrag(true)
        for _, suffix in ipairs({ "Low", "High", "Text" }) do
            local fs = heightSlider[suffix] or _G["WowVoiceQueueHeightSlider" .. suffix]
            if fs then fs:Hide() end
        end
        local low = label("280", "GameFontHighlightSmall", 20, -903, 60, 16)
        local high = label("600", "GameFontHighlightSmall", 228, -903, 60, 16)
        high:SetJustifyH("RIGHT")
        panel.QueueLabels = { panel.QueueHeading, panel.QueueDivider, panel.QueueDescriptionsOnly.Label,
            panel.QueueDescriptionsOnly.Description, heightCaption, low, high }
        panel.QueueHeightInput = numericField(58, 308, -878)
        local heightInput = panel.QueueHeightInput
        heightInput:SetNumeric(true)
        heightInput:SetMaxLetters(3)
        local function applyHeight(value)
            if WowVoiceDB.autoPlay == false then return false end
            local ok, reason = WV:SetQuestQueueHeight(value)
            status(reason)
            if ok then WV:PreviewQuestQueue(true); WV:RefreshHeadOptions() end
            return ok
        end
        heightSlider:SetScript("OnValueChanged", function(_, value)
            if not panel.refreshingQueue then applyHeight(math.floor(value + 0.5)) end
        end)
        heightInput:SetScript("OnEnterPressed", function(self)
            if applyHeight(tonumber(self:GetText())) then self:ClearFocus() end
        end)
        heightInput:SetScript("OnEscapePressed", function(self) self:ClearFocus(); WV:RefreshHeadOptions(); status() end)
        heightInput:SetScript("OnEditFocusLost", function() WV:RefreshHeadOptions() end)
        local scaleCaption = label("Масштаб плейлиста", "GameFontNormal", 20, -942, 280, 20)
        panel.QueueScale = CreateFrame("Slider", "WowVoiceQueueScaleSlider", content, "OptionsSliderTemplate")
        local scaleSlider = panel.QueueScale
        scaleSlider:SetPoint("TOPLEFT", content, "TOPLEFT", 24, -972)
        scaleSlider:SetSize(260, 17)
        scaleSlider:SetMinMaxValues(80, 120)
        scaleSlider:SetValueStep(1)
        scaleSlider:SetObeyStepOnDrag(true)
        for _, suffix in ipairs({ "Low", "High", "Text" }) do
            local fs = scaleSlider[suffix] or _G["WowVoiceQueueScaleSlider" .. suffix]
            if fs then fs:Hide() end
        end
        local scaleLow = label("80%", "GameFontHighlightSmall", 20, -995, 60, 16)
        local scaleHigh = label("120%", "GameFontHighlightSmall", 228, -995, 60, 16)
        scaleHigh:SetJustifyH("RIGHT")
        local percentLabel = label("%", "GameFontHighlight", 374, -973, 20, 20)
        for _, fs in ipairs({ scaleCaption, scaleLow, scaleHigh, percentLabel }) do
            panel.QueueLabels[#panel.QueueLabels + 1] = fs
        end
        panel.QueueScaleInput = numericField(58, 308, -970)
        local scaleInput = panel.QueueScaleInput
        scaleInput:SetNumeric(true)
        scaleInput:SetMaxLetters(3)
        local function applyQueueScale(percent)
            if WowVoiceDB.autoPlay == false then return false end
            local ok, reason = WV:SetQuestQueueScale(percent and percent / 100)
            status(reason)
            if ok then WV:PreviewQuestQueue(true); WV:RefreshHeadOptions() end
            return ok
        end
        scaleSlider:SetScript("OnValueChanged", function(_, value)
            if not panel.refreshingQueue then applyQueueScale(math.floor(value + 0.5)) end
        end)
        scaleInput:SetScript("OnEnterPressed", function(self)
            if applyQueueScale(tonumber(self:GetText())) then self:ClearFocus() end
        end)
        scaleInput:SetScript("OnEscapePressed", function(self) self:ClearFocus(); WV:RefreshHeadOptions(); status() end)
        scaleInput:SetScript("OnEditFocusLost", function() WV:RefreshHeadOptions() end)
        panel.QueueLabels[#panel.QueueLabels + 1] = label("Координаты верхнего левого угла", "GameFontNormal", 20, -1030, 540, 20)
        local function applyQueuePosition()
            if WowVoiceDB.autoPlay == false then return end
            local function number(text)
                text = text:match("^%s*(.-)%s*$"):gsub(",", ".")
                return text:match("^[+-]?%d*%.?%d+$") and tonumber(text)
            end
            local x, y = number(panel.QueuePositionX:GetText()), number(panel.QueuePositionY:GetText())
            if not x or not y then status("Введите числа в поля X и Y. Например: -120 или 35,5."); return end
            WV:PreviewQuestQueue(true)
            local ok, reason = WV:SetQuestQueuePosition(x, y)
            status(ok and "" or reason)
            WV:RefreshHeadOptions()
        end
        local function positionField(key, caption, x)
            panel.QueueLabels[#panel.QueueLabels + 1] = label(caption, "GameFontHighlightSmall", x, -1064, 20, 20)
            local field = numericField(78, x + 24, -1060)
            field:SetMaxLetters(12)
            field:SetScript("OnEditFocusGained", function() panel.editingQueuePosition = true end)
            field:SetScript("OnEnterPressed", applyQueuePosition)
            field:SetScript("OnEscapePressed", function() WV:RefreshQuestQueuePositionOptions(true); status() end)
            panel[key] = field
        end
        positionField("QueuePositionX", "X", 20)
        positionField("QueuePositionY", "Y", 130)
        panel.QueuePositionX:SetScript("OnTabPressed", function(self) self:ClearFocus(); panel.QueuePositionY:SetFocus() end)
        panel.QueuePositionY:SetScript("OnTabPressed", function(self) self:ClearFocus(); panel.QueuePositionX:SetFocus() end)
        button("applyQueuePosition", "Задать", 244, 86, applyQueuePosition, -1057)
    end
    local voiceHeading = section("Выбор озвучки", -660 - lowerOffset)
    -- Let the font string size itself at the current UI scale. Measuring it
    -- while the settings panel is hidden can leave the title truncated.
    voiceHeading:SetWordWrap(false)
    voiceHeading:SetSize(0, 0)
    panel.SharedVoiceCaption = label("Если доступны обе озвучки", "GameFontHighlight", 20, -698 - lowerOffset, 540, 22)
    panel.SharedVoiceButtons = {}
    for index, item in ipairs({ { "wowvoice", "WowVoice" }, { "catquest", "CatQuest" } }) do
        local choice = CreateFrame("CheckButton", nil, content)
        choice:SetSize(160, 26)
        choice:SetPoint("TOPLEFT", content, "TOPLEFT", 20 + (index - 1) * 180, -726 - lowerOffset)
        -- Like Details/Plater's circular switches: scale a smooth client mask,
        -- rather than enlarging the old 16px radio texture sheet.
        local function circle(size, layer, r, g, b, alpha)
            local texture = choice:CreateTexture(nil, layer)
            texture:SetPoint("CENTER", choice, "LEFT", 12, 0)
            texture:SetSize(size, size)
            texture:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
            texture:SetVertexColor(r, g, b, alpha or 1)
            return texture
        end
        choice.Border = circle(18, "BACKGROUND", 0.6, 0.6, 0.6)
        circle(14, "BORDER", 0.06, 0.06, 0.06)
        choice:SetCheckedTexture(circle(8, "ARTWORK", 1, 0.82, 0.25))
        choice:SetHighlightTexture(circle(20, "HIGHLIGHT", 1, 0.82, 0.25, 0.22), "ADD")
        choice.Label = choice:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        choice.Label:SetPoint("LEFT", choice, "LEFT", 32, 0)
        choice.Label:SetSize(128, 24)
        choice.Label:SetJustifyH("LEFT")
        choice.Label:SetJustifyV("MIDDLE")
        choice.Label:SetText(item[2])
        choice:SetScript("OnClick", function()
            WV:SetSharedQuestVoice(item[1])
            refreshVoicePreference()
        end)
        panel.SharedVoiceButtons[item[1]] = choice
    end
    -- Only this explicit help icon owns the tooltip, even with disabled choices.
    local hint = CreateFrame("Button", nil, content)
    hint:SetPoint("LEFT", voiceHeading, "RIGHT", 6, 0)
    hint:SetSize(22, 22)
    hint:EnableMouse(true)
    -- Blizzard's info art, also used by Burstik and OPie. Crop its empty border.
    local function infoIcon(layer)
        local icon = hint:CreateTexture(nil, layer)
        icon:SetPoint("CENTER", hint, "CENTER", 0, 0)
        icon:SetSize(16, 16)
        icon:SetTexture("Interface\\COMMON\\help-i")
        icon:SetTexCoord(0.25, 0.75, 0.25, 0.75)
        return icon
    end
    hint.Icon = infoIcon("ARTWORK")
    hint:SetHighlightTexture(infoIcon("HIGHLIGHT"), "ADD")
    local function showVoiceTooltip(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Выбор озвучки", 1, 0.82, 0)
        GameTooltip:AddLine(hint.message, 1, 1, 1, true)
        GameTooltip:Show()
    end
    local function hideVoiceTooltip(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end
    hint:SetScript("OnEnter", showVoiceTooltip)
    hint:SetScript("OnLeave", hideVoiceTooltip)
    hint:SetScript("OnHide", hideVoiceTooltip)
    panel.SharedVoiceTooltip = hint
    button("compareVoices", "Послушать озвучку", 20, 180, function() WV:OpenVoiceComparison() end, -766 - lowerOffset)
    panel.VoiceComparisonButton = panel.Buttons.compareVoices
    refreshVoicePreference()
    panel:SetScript("OnShow", function()
        panel.editingPosition = nil
        panel.editingQueuePosition = nil
        refreshVersions()
        WV:RefreshHeadOptions()
        for _, b in pairs(panel.Buttons) do if WV.StyleButton then WV.StyleButton(b) end end
        status()
    end)
    panel:SetScript("OnHide", function()
        panel.draggingScale = nil
        WV:EndHeadScalePreview(true)
        discardPosition()
        input:ClearFocus()
        refreshScale()
        WV:HideHeadPreview()
        if WV.PreviewQuestQueue then WV:PreviewQuestQueue(false) end
        panel.editingQueuePosition = nil
        if panel.QueuePositionX then panel.QueuePositionX:ClearFocus(); panel.QueuePositionY:ClearFocus() end
    end)
end

local function register()
    if category then return true end
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return false end
    createPanel()
    category = Settings.RegisterCanvasLayoutCategory(panel, WV.displayName)
    Settings.RegisterAddOnCategory(category)
    return true
end

function WV:OpenOptions()
    if register() and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff" .. WV.displayName .. "|r: API страницы модификаций Settings недоступен.")
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event)
    if WowVoiceDB or event == "PLAYER_LOGIN" then register() end
end)

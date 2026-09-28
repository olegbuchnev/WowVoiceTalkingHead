-- Built-in options page: Settings -> AddOns -> WowVoice.
local WV = _G.WowVoice
local panel, category

-- Previously published packs predate explicit upstream version metadata.
local legacySourceVersions = {
    WowVoiceSounds = { ["1.0.3-forever.1"] = "1.0.1" },
    CatVoices = { ["0.2.0-wowvoice.1"] = "0.2.0" },
}

local function refreshVersions()
    local metadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local function field(addon, key)
        local value = metadata and metadata(addon, key)
        return type(value) == "string" and value ~= "" and value or nil
    end
    local width = 0
    for addon, text in pairs(panel.VersionLabels) do
        local installed = field(addon, "Version")
        local version = installed
        if legacySourceVersions[addon] then
            version = field(addon, "X-Source-Version") or legacySourceVersions[addon][installed]
        end
        if not version then
            version = metadata and not installed and not field(addon, "Title")
                and "не установлен" or "версия не указана"
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

local function refreshScale()
    if panel.draggingScale then return end
    local percent = math.floor(WV:GetHeadScale() * 100 + 0.5)
    panel.refreshingScale = true
    panel.ScaleSlider:SetValue(percent)
    panel.ScaleInput:SetText(tostring(percent))
    panel.refreshingScale = false
end

local function refreshPosition(force)
    if panel.editingPosition and not force then return end
    local x, y = WV:GetHeadAnchorPosition()
    local function coordinate(value)
        if math.abs(value) < 0.005 then value = 0 end
        return string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", "")
    end
    x, y = coordinate(x), coordinate(y)
    if panel.PositionX:GetText() ~= x then panel.PositionX:SetText(x) end
    if panel.PositionY:GetText() ~= y then panel.PositionY:SetText(y) end
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
    local trackerEnabled = WowVoiceDB.trackerButtons ~= false
    panel.TrackerButtons:SetChecked(trackerEnabled)
    panel.TrackerProgressPulse:SetChecked(WowVoiceDB.trackerProgressPulse ~= false)
    panel.TrackerProgressPulse:SetEnabled(trackerEnabled)
    panel.TrackerProgressPulse:SetAlpha(trackerEnabled and 1 or 0.45)
    panel.TrackerProgressPulse.Label:SetAlpha(trackerEnabled and 1 or 0.45)
    panel.TrackerProgressPulse.Description:SetAlpha(trackerEnabled and 1 or 0.45)
    panel.AutoPlayAccept:SetChecked(WowVoiceDB.autoPlayAccept == true)
    panel.AutoPlayTurnIn:SetChecked(WowVoiceDB.autoPlayTurnIn ~= false)
end

local function createPanel()
    panel = CreateFrame("Frame", "WowVoiceOptionsPanel")
    panel:Hide()
    panel.Buttons = {}
    local scroll = CreateFrame("ScrollFrame", "WowVoiceOptionsScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 0)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(584, 820)
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
        { "CatVoices", "Озвучка Cathey" },
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
    end
    refreshVersions()
    label("При перетаскивании масштаба предпросмотр появится автоматически.\n"
        .. "«Тест / переместить» позволяет перетащить окно. Положение сохраняется.",
        "GameFontHighlightSmall", 20, -58, 540, 28)
    local function section(text, y)
        label(text, "GameFontNormalLarge", 20, y, 540, 22)
        local line = content:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(0.6, 0.52, 0.32, 0.45)
        line:SetSize(544, 1)
        line:SetPoint("TOPLEFT", content, "TOPLEFT", 20, y - 24)
    end
    section("Положение и масштаб", -94)
    section("Автозапуск озвучки", -460)
    section("Кнопки и напоминания", -660)

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
            if ok then WV:EnsureHeadPreview(); WV:FinishAutoHeadPreview(2) end
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
        WV:EnsureHeadPreview()
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
        if ok then WV:EnsureHeadPreview(); WV:FinishAutoHeadPreview(2) end
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
    panel.TrackerButtons = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    panel.TrackerButtons:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -696)
    panel.TrackerButtons:SetSize(26, 26)
    label("Кнопки озвучки в списке заданий", "GameFontHighlight", 48, -703, 506, 22)
    panel.TrackerButtons:SetScript("OnClick", function(self)
        WV:SetTrackerButtonsEnabled(self:GetChecked() == true)
    end)
    panel.TrackerProgressPulse = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    panel.TrackerProgressPulse:SetPoint("TOPLEFT", content, "TOPLEFT", 42, -730)
    panel.TrackerProgressPulse:SetSize(26, 26)
    panel.TrackerProgressPulse.Label = label("Напоминать об озвучке при прогрессе",
        "GameFontHighlight", 74, -737, 480, 22)
    panel.TrackerProgressPulse.Description = label(
        "Подсветка кнопки и подсказка «Вспомнить задание».",
        "GameFontHighlightSmall", 74, -765, 480, 32)
    panel.TrackerProgressPulse:SetScript("OnClick", function(self)
        WV:SetTrackerProgressPulseEnabled(self:GetChecked() == true)
    end)
    panel.AutoPlayAccept = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    panel.AutoPlayAccept:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -496)
    panel.AutoPlayAccept:SetSize(26, 26)
    label("При получении задания", "GameFontHighlight", 48, -503, 506, 22)
    panel.AutoPlayAccept:SetScript("OnClick", function(self)
        WV:SetAutoPlayAcceptEnabled(self:GetChecked() == true)
    end)
    label("Если выключено, запускайте описание кнопкой в журнале или списке заданий.",
        "GameFontHighlightSmall", 48, -531, 506, 32)
    panel.AutoPlayTurnIn = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    panel.AutoPlayTurnIn:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -580)
    panel.AutoPlayTurnIn:SetSize(26, 26)
    label("При сдаче задания", "GameFontHighlight", 48, -587, 506, 22)
    panel.AutoPlayTurnIn:SetScript("OnClick", function(self)
        WV:SetAutoPlayTurnInEnabled(self:GetChecked() == true)
    end)
    label("Управляет всеми репликами сдачи: промежуточными и завершающей.",
        "GameFontHighlightSmall", 48, -615, 506, 32)
    panel:SetScript("OnShow", function()
        panel.editingPosition = nil
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

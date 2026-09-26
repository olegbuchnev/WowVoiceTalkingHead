-- Built-in options page: Settings -> AddOns -> WowVoice.
local WV = _G.WowVoice
local panel, category

local function status(text)
    panel.Status:SetText(text or "")
end

function WV:RefreshHeadOptions()
    if not panel or not panel:IsShown() then return end
    local trackerEnabled = WowVoiceDB.trackerButtons ~= false
    panel.TrackerButtons:SetChecked(trackerEnabled)
    panel.TrackerProgressPulse:SetChecked(WowVoiceDB.trackerProgressPulse ~= false)
    panel.TrackerProgressPulse:SetEnabled(trackerEnabled)
    panel.TrackerProgressPulse:SetAlpha(trackerEnabled and 1 or 0.45)
    panel.TrackerProgressPulse.Label:SetAlpha(trackerEnabled and 1 or 0.45)
    panel.AutoPlayAccept:SetChecked(WowVoiceDB.autoPlayAccept == true)
    panel.AutoPlayTurnIn:SetChecked(WowVoiceDB.autoPlayTurnIn ~= false)
end

local function createPanel()
    panel = CreateFrame("Frame", "WowVoiceOptionsPanel")
    panel:Hide()
    panel.Buttons = {}
    local function label(text, font, x, y, width, height)
        local fs = panel:CreateFontString(nil, "ARTWORK", font)
        fs:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
        fs:SetSize(width, height)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetText(text)
        return fs
    end
    label(WV.displayName, "GameFontNormalLarge", 16, -16, 560, 28)
    label("Нажмите «Тест / переместить».\n"
        .. "В режиме теста перетащите окно мышью. Положение сохраняется.",
        "GameFontHighlightSmall", 20, -52, 540, 42)

    local function button(key, text, x, width, callback)
        local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(width, 26)
        b:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -108)
        b:SetText(text)
        b:SetScript("OnClick", callback)
        panel.Buttons[key] = b
    end
    button("test", "Тест / переместить", 20, 170, function()
        local ok, reason = WV:ToggleHeadPreview()
        status(ok and "Тест без звука: перетащите окно и оцените подсветку кнопок озвучки. Повторное нажатие остановит тест." or reason)
    end)
    button("center", "Центр по горизонтали", 202, 170, function()
        WV:CenterTalkingHead()
        status("Окно выровнено по центру по горизонтали.")
    end)
    button("reset", "Сбросить положение", 384, 180, function()
        WV:ResetHeadPosition()
        status("Положение окна сброшено.")
    end)
    panel.Status = label("", "GameFontHighlightSmall", 20, -154, 540, 48)
    panel.TrackerButtons = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    panel.TrackerButtons:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -216)
    panel.TrackerButtons:SetSize(26, 26)
    label("Кнопки озвучки в списке заданий на экране", "GameFontHighlight", 44, -223, 510, 22)
    panel.TrackerButtons:SetScript("OnClick", function(self)
        WV:SetTrackerButtonsEnabled(self:GetChecked() == true)
    end)
    panel.TrackerProgressPulse = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    panel.TrackerProgressPulse:SetPoint("TOPLEFT", panel, "TOPLEFT", 38, -250)
    panel.TrackerProgressPulse:SetSize(26, 26)
    panel.TrackerProgressPulse.Label = label("Подсвечивать озвучку при прогрессе задания",
        "GameFontHighlight", 70, -257, 484, 22)
    panel.TrackerProgressPulse:SetScript("OnClick", function(self)
        WV:SetTrackerProgressPulseEnabled(self:GetChecked() == true)
    end)
    panel.AutoPlayAccept = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    panel.AutoPlayAccept:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -300)
    panel.AutoPlayAccept:SetSize(26, 26)
    label("Озвучивать при получении задания", "GameFontHighlight", 44, -307, 510, 22)
    panel.AutoPlayAccept:SetScript("OnClick", function(self)
        WV:SetAutoPlayAcceptEnabled(self:GetChecked() == true)
    end)
    label("Если выключено, запускайте описание кнопкой в журнале или списке заданий.",
        "GameFontHighlightSmall", 44, -335, 510, 40)
    panel.AutoPlayTurnIn = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    panel.AutoPlayTurnIn:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -380)
    panel.AutoPlayTurnIn:SetSize(26, 26)
    label("Озвучивать при сдаче задания", "GameFontHighlight", 44, -387, 510, 22)
    panel.AutoPlayTurnIn:SetScript("OnClick", function(self)
        WV:SetAutoPlayTurnInEnabled(self:GetChecked() == true)
    end)
    label("Управляет всеми репликами сдачи: промежуточными и завершающей.",
        "GameFontHighlightSmall", 44, -415, 510, 40)
    panel:SetScript("OnShow", function()
        WV:RefreshHeadOptions()
        for _, b in pairs(panel.Buttons) do if WV.StyleButton then WV.StyleButton(b) end end
        status()
    end)
    panel:SetScript("OnHide", function() WV:HideHeadPreview() end)
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

-- Built-in options page: Settings -> AddOns -> WowVoice.
local WV = _G.WowVoice
local panel, category

local function createRadio(parent)
    local normalAtlas = "common-dropdown-tickradial"
    local checkedAtlas = "common-dropdown-icon-radialtick-yellow"
    local atlasInfo = C_Texture and C_Texture.GetAtlasInfo
    if not atlasInfo or not atlasInfo(normalAtlas) or not atlasInfo(checkedAtlas) then
        return CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate")
    end
    -- Use modern radial artwork without depending on a client-specific template.
    local button = CreateFrame("CheckButton", nil, parent)
    local function texture(atlas, layer)
        local t = button:CreateTexture(nil, layer)
        t:SetAtlas(atlas, true)
        t:SetPoint("CENTER", button, "CENTER")
        return t
    end
    button:SetNormalTexture(texture(normalAtlas, "ARTWORK"))
    button:SetCheckedTexture(texture(checkedAtlas, "OVERLAY"))
    local highlight = texture(normalAtlas, "HIGHLIGHT")
    highlight:SetBlendMode("ADD")
    button:SetHighlightTexture(highlight)
    return button
end

local function status(text)
    panel.Status:SetText(text or "")
end

function WV:RefreshHeadOptions()
    if not panel or not panel:IsShown() then return end
    local settings = self:GetHeadSettings()
    panel.Enabled:SetChecked(settings.enabled)
    panel.TrackerButtons:SetChecked(WowVoiceDB.trackerButtons ~= false)
    for key, choice in pairs(panel.Presets) do
        choice:SetChecked(key == settings.preset)
    end
end

local function createPanel()
    panel = CreateFrame("Frame", "WowVoiceOptionsPanel")
    panel:Hide()
    panel.Presets, panel.Buttons = {}, {}
    local function label(text, font, x, y, width, height)
        local fs = panel:CreateFontString(nil, "ARTWORK", font)
        fs:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
        fs:SetSize(width, height)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetText(text)
        return fs
    end
    label("WowVoice", "GameFontNormalLarge", 16, -16, 560, 28)
    panel.Enabled = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    panel.Enabled:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -52)
    panel.Enabled:SetSize(26, 26)
    label("Показывать говорящую голову", "GameFontHighlight", 44, -59, 420, 22)
    panel.Enabled:SetScript("OnClick", function(self)
        WV:SetHeadEnabled(self:GetChecked() == true)
    end)

    for i, preset in ipairs(WV:GetHeadPresets()) do
        local key, name = preset.key, preset.name
        local y = -98 - (i - 1) * 30
        local text = label(name, "GameFontNormal", 50, y - 2, 490, 0)
        local choice = createRadio(panel)
        choice:SetSize(18, 18)
        -- Lower the label optically while keeping the radio in its original position.
        choice:SetPoint("CENTER", text, "LEFT", -20, 2)
        choice.Label = text
        choice:SetScript("OnClick", function()
            WV:SetHeadPreset(key)
            status()
        end)
        panel.Presets[key] = choice
    end

    label("Выберите оформление и нажмите «Тест / переместить».\n"
        .. "В режиме теста перетащите окно мышью. Положение сохраняется.",
        "GameFontHighlightSmall", 20, -202, 540, 42)

    local function button(key, text, x, width, callback)
        local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(width, 26)
        b:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -258)
        b:SetText(text)
        b:SetScript("OnClick", callback)
        panel.Buttons[key] = b
    end
    button("test", "Тест / переместить", 20, 170, function()
        local ok, reason = WV:ToggleHeadPreview()
        status(ok and "Тест без звука. Перетащите окно; повторное нажатие остановит тест." or reason)
    end)
    button("center", "По центру экрана", 202, 170, function()
        WV:CenterTalkingHead()
        status("Окно выровнено по центру по горизонтали.")
    end)
    button("reset", "Сбросить положение", 384, 180, function()
        WV:ResetHeadPosition()
        status("Положение окна сброшено.")
    end)
    panel.Status = label("", "GameFontHighlightSmall", 20, -304, 540, 48)
    panel.TrackerButtons = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    panel.TrackerButtons:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -366)
    panel.TrackerButtons:SetSize(26, 26)
    label("Кнопки озвучки в списке заданий на экране", "GameFontHighlight", 44, -373, 510, 22)
    panel.TrackerButtons:SetScript("OnClick", function(self)
        WV:SetTrackerButtonsEnabled(self:GetChecked() == true)
    end)
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
    category = Settings.RegisterCanvasLayoutCategory(panel, "WowVoice")
    Settings.RegisterAddOnCategory(category)
    return true
end

function WV:OpenOptions()
    if register() and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffWowVoice|r: API страницы модификаций Settings недоступен.")
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event)
    if WowVoiceDB or event == "PLAYER_LOGIN" then register() end
end)

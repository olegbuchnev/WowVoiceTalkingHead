local Lab = WowVoiceQueueLab
local window, rows, viewport, scrollbar
local offset, dirty, refreshing = 0, false, false
local VISIBLE = 5
local phase = { a = "Описание", p = "Сдача", c = "Сдача" }

local function label(parent, text, x, y, width, font)
    local value = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    value:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    value:SetSize(width, 20)
    value:SetJustifyH("LEFT")
    value:SetWordWrap(false)
    value:SetText(text)
    return value
end

local function button(parent, text, x, y, width, action)
    local value = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    value:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    value:SetSize(width, 24)
    value:SetText(text)
    value:SetScript("OnClick", action)
    return value
end

local function makeRow(parent, y)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    row:SetSize(586, 50)
    row.Background = row:CreateTexture(nil, "BACKGROUND")
    row.Background:SetAllPoints(row)
    row.Title = label(row, "", 8, -3, 352, "GameFontNormal")
    row.Info = label(row, "", 8, -25, 352)
    row.Abandon = button(row, "Отказаться", 366, -13, 108, function(self)
        local record = self.pressedRecord or row.record
        self.pressedRecord = nil
        if record then Lab:Abandon(record.id) end
    end)
    row.Abandon:SetScript("OnMouseDown", function(self) self.pressedRecord = row.record end)
    row.Submit = button(row, "Сдать", 481, -13, 95, function(self)
        local record = self.pressedRecord or row.record
        self.pressedRecord = nil
        if record then Lab:TurnIn(record.id) end
    end)
    row.Submit:SetScript("OnMouseDown", function(self) self.pressedRecord = row.record end)
    row.Submit:SetScript("OnHide", function(self) self.pressedRecord = nil end)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function()
        if not GameTooltip or not row.record then return end
        GameTooltip:SetOwner(row, "ANCHOR_TOP")
        GameTooltip:SetText(row.record.title)
        GameTooltip:AddLine(row.record.npc .. " | ID " .. row.record.id, 1, 1, 1)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return row
end

function Lab:Refresh(force)
    if not window then return end
    window.Status:SetText(self.message or "Примите случайное задание, чтобы начать.")
    local current = self.state.current
    window.Current:SetText(current and ("Играет: " .. current.title .. " | " .. phase[current.section])
        or "Сейчас ничего не играет")
    local list = self.state:AcceptedQuests()
    window.Count:SetText("Принятые задания: " .. #list)
    if not force and MouseIsOver and MouseIsOver(viewport) then dirty = true; return end
    dirty = false
    local maximum = math.max(0, #list - VISIBLE)
    offset = math.min(offset, maximum)
    refreshing = true
    scrollbar:SetMinMaxValues(0, maximum)
    scrollbar:SetValue(offset)
    scrollbar:SetShown(maximum > 0)
    refreshing = false
    for i, row in ipairs(rows) do
        local quest = list[offset + i]
        row.record = quest and quest.intro
        row:SetShown(quest ~= nil)
        if quest then
            local isCurrent = current and current.id == quest.id
            row.Title:SetText(quest.title)
            row.Info:SetText(quest.intro.npc .. " | ID " .. quest.id)
            row.Background:SetColorTexture(isCurrent and 0.24 or 0.12, isCurrent and 0.18 or 0.10, 0.07, 0.8)
            row.Submit:SetEnabled(quest.accepted)
            row.Abandon:SetEnabled(quest.accepted)
        end
    end
end

function Lab:Open()
    if window then window:Show(); self:Refresh(true); return end
    window = CreateFrame("Frame", "WowVoiceQueueLabWindow", UIParent, "BackdropTemplate")
    self.window = window
    window:SetSize(650, 470)
    window:SetScale(math.min(1, (UIParent:GetWidth() - 32) / 650, (UIParent:GetHeight() - 32) / 470))
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(self) self:StartMoving() end)
    window:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    window:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    window:SetBackdropColor(0.055, 0.055, 0.055, 0.98)
    window:SetBackdropBorderColor(0.5, 0.4, 0.2, 1)
    label(window, "Тест игровых диалогов", 20, -17, 560, "GameFontNormalLarge")
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() window:Hide() end)
    label(window, "Настоящий журнал не меняется. Закрытие окна очищает стенд.", 20, -46, 610)
    button(window, "Принять случайный квест", 20, -77, 220, function() self:Accept() end)
    button(window, "Очистить", 537, -77, 87, function() self:Reset(); offset = 0; self:Refresh(true) end)
    window.Current = label(window, "", 20, -113, 610, "GameFontNormal")
    window.Count = label(window, "", 20, -143, 610)
    viewport = CreateFrame("Frame", nil, window)
    viewport:SetPoint("TOPLEFT", window, "TOPLEFT", 20, -169)
    viewport:SetSize(586, VISIBLE * 54)
    rows = {}
    for i = 1, VISIBLE do rows[i] = makeRow(viewport, -(i - 1) * 54) end
    scrollbar = CreateFrame("Slider", "WowVoiceQueueLabScroll", window, "UIPanelScrollBarTemplate")
    scrollbar:SetPoint("TOPLEFT", viewport, "TOPRIGHT", 5, -16)
    scrollbar:SetSize(16, VISIBLE * 54 - 32)
    scrollbar:SetValueStep(1)
    scrollbar:SetObeyStepOnDrag(true)
    scrollbar:SetScript("OnValueChanged", function(_, value)
        if refreshing then return end
        offset = math.floor(value + 0.5); self:Refresh(true)
    end)
    viewport:EnableMouseWheel(true)
    viewport:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta); self:Refresh(true)
    end)
    window.Status = label(window, "", 20, -444, 610)
    local elapsed = 0
    window:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.15 then return end
        elapsed = 0
        if dirty and (not MouseIsOver or not MouseIsOver(viewport)) then self:Refresh(true) end
    end)
    window:SetScript("OnHide", function()
        window:StopMovingOrSizing()
        if GameTooltip then GameTooltip:Hide() end
        self:Reset()
        offset = 0
    end)
    UISpecialFrames = UISpecialFrames or {}
    table.insert(UISpecialFrames, "WowVoiceQueueLabWindow")
    self:Refresh(true)
end

SLASH_WOWVOICEQUEUELAB1 = "/tt"
SlashCmdList.WOWVOICEQUEUELAB = function(input)
    if strlower(strtrim(input or "")) == "reset" then Lab:Reset() end
    Lab:Open()
end

local originalCommand = SlashCmdList.WOWVOICETALKINGHEAD
SlashCmdList.WOWVOICETALKINGHEAD = function(input)
    local command = strlower(strtrim(input or ""))
    if command == "queuelab" or command == "queuetest" then Lab:Open()
    else return originalCommand(input) end
end

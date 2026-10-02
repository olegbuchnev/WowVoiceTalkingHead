local L = WowVoiceLocale
-- Public voice catalogue, created only when opened from the options page.
local WV = WowVoice
local Comparison = WowVoiceComparison
local unpack = unpack or table.unpack
local panel
local questIDs, questSummary, audioRevision, catQuestPresent

local function indexedQuestIDs()
    local hasCatQuest = Comparison.HasCatQuest()
    if questIDs and audioRevision == WV.audioRevision and catQuestPresent == hasCatQuest then return questIDs end
    audioRevision = WV.audioRevision
    catQuestPresent = hasCatQuest
    questIDs = {}
    -- Loaded CatQuest uses its current index; otherwise use our offline snapshot.
    -- Known recordings stay visible while unavailable; completion-only quests are excluded.
    for id in pairs(Comparison.QuestIDs()) do questIDs[#questIDs + 1] = id end
    table.sort(questIDs)
    local wowvoice, catquest = 0, 0
    for _, id in ipairs(questIDs) do
        if Comparison.Known(id, "wowvoice") then wowvoice = wowvoice + 1 end
        if Comparison.Known(id, "catquest") then catquest = catquest + 1 end
    end
    questSummary = string.format("WowVoice: %d    CatQuest: %d    Всего без повторов: %d",
        wowvoice, catquest, #questIDs)
    return questIDs
end

local function backdrop(frame, alpha)
    frame:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground", tile = true, edgeSize = 1, tileSize = 5 })
    frame:SetBackdropColor(0, 0, 0, alpha)
    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
end

local colors = { wowvoice = {0.25, 0.7, 1}, catquest = {1, 0.55, 0.2} }
local function playIcon(parent, color)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\AddOns\\WowVoiceTalkingHead\\Media\\Play.tga")
    icon:SetSize(24, 24)
    icon:SetPoint("CENTER", parent, "CENTER", 0, 0)
    icon:SetVertexColor(unpack(color))
    return icon
end

local function unavailableMark(parent)
    local mark = parent:CreateTexture(nil, "OVERLAY")
    mark:SetTexture("Interface\\AddOns\\WowVoiceTalkingHead\\Media\\QueueClose.png")
    -- This glyph's diagonal tips reach the play icon's rim at equal texture
    -- size. Anchor to the icon itself: legend frames are smaller than buttons.
    mark:SetAllPoints(parent.Icon)
    mark:SetVertexColor(0.25, 0.25, 0.25)
    mark:Hide()
    return mark
end

local function sourceAppearance(widget, source, available)
    local color = colors[source]
    widget.Icon:SetVertexColor(color[1], color[2], color[3], available and 1 or 0.4)
    if available then widget.UnavailableMark:Hide() else widget.UnavailableMark:Show() end
end

local function attachQuestSuggestions(frame, input)
    local step, padding, gap = 58, 6, 6
    local popup = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    popup:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -116)
    popup:SetFrameLevel(frame:GetFrameLevel() + 20)
    popup:EnableMouse(true)
    backdrop(popup, 1)
    popup:Hide()
    popup.Rows, popup.matches = {}, {}
    frame.Suggestions = popup
    local viewport = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
    viewport:SetPoint("TOPLEFT", popup, "TOPLEFT", padding, -padding)
    viewport:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -28, padding)
    local grid = CreateFrame("Frame", nil, viewport)
    grid:SetPoint("TOPLEFT", viewport, "TOPLEFT", 0, 0)
    viewport:SetScrollChild(grid)
    popup.Viewport, popup.Grid = viewport, grid
    local selectedID, selectedSource
    local function updateSelection(row)
        for source, button in pairs(row.PlayButtons) do
            local known = row.questID and Comparison.Known(row.questID, source)
            if known then button:Show() else button:Hide() end
            local available = row.questID and Comparison.Resolve(row.questID, source) ~= nil
            button:SetEnabled(available == true)
            sourceAppearance(button, source, available)
            if available and row.questID == selectedID and source == selectedSource then
                local color = colors[source]
                button.SelectedMark:SetVertexColor(color[1], color[2], color[3], 1)
                button.SelectedMark:Show()
            else
                button.SelectedMark:Hide()
            end
        end
    end
    frame.ListenQuest = function(id, source)
        if not source then
            source = Comparison.Resolve(id, "wowvoice") and "wowvoice" or "catquest"
        end
        if not Comparison.Resolve(id, source) then
            DEFAULT_CHAT_FRAME:AddMessage("WowVoice TalkingHead: для описания этого квеста нет записи в установленном аудиопаке")
            return false
        end
        input:ClearFocus()
        local ok = Comparison.Play(id, source)
        if ok then selectedID, selectedSource = id, source end
        for _, row in ipairs(popup.Rows) do updateSelection(row) end
        return ok
    end
    -- Pool only visible cells, while the scroll child represents every match.
    -- A one-digit prefix can contain thousands of IDs without thousands of frames.
    local function render(offset)
        if not popup.columns then return end
        offset = math.max(0, math.min(popup.maxScroll, offset or viewport:GetVerticalScroll()))
        local firstRow = math.floor(offset / step)
        local visibleRows = math.ceil(popup.viewportHeight / step) + 1
        local count = math.max(0, math.min(#popup.matches - firstRow * popup.columns, visibleRows * popup.columns))
        for index = 1, count do
            local row = popup.Rows[index]
            if not row then
                row = CreateFrame("Frame", nil, grid, "BackdropTemplate")
                backdrop(row, 0.6)
                row.Label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row.Label:SetPoint("TOP", row, "TOP", 0, -4)
                row.Label:SetHeight(18)
                row.PlayButtons = {}
                for _, source in ipairs({"wowvoice", "catquest"}) do
                    local button = CreateFrame("Button", nil, row)
                    button:SetSize(24, 24)
                    button:SetPoint("BOTTOM", row, "BOTTOM", source == "wowvoice" and -13 or 13, 4)
                    button.Icon = playIcon(button, colors[source])
                    button.UnavailableMark = unavailableMark(button)
                    button.SelectedMark = button:CreateTexture(nil, "OVERLAY")
                    button.SelectedMark:SetTexture("Interface\\AddOns\\WowVoiceTalkingHead\\Media\\PlaySelected.tga")
                    button.SelectedMark:SetAllPoints(button.Icon)
                    button.SelectedMark:Hide()
                    button:SetScript("OnEnter", function(self)
                        if self:IsEnabled() then self.Icon:SetSize(26, 26) end
                    end)
                    button:SetScript("OnLeave", function(self) self.Icon:SetSize(24, 24) end)
                    button:SetScript("OnClick", function(self)
                        if self:IsEnabled() then frame.ListenQuest(row.questID, source) end
                    end)
                    row.PlayButtons[source] = button
                end
                popup.Rows[index] = row
            end
            local position = firstRow * popup.columns + index - 1
            row.questID = popup.matches[position + 1]
            updateSelection(row)
            row.Label:SetText(tostring(row.questID))
            row:SetSize(popup.cellWidth, step - gap)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", grid, "TOPLEFT", (position % popup.columns) * (popup.cellWidth + gap),
                -math.floor(position / popup.columns) * step)
            row:Show()
        end
        for index = count + 1, #popup.Rows do
            popup.Rows[index].questID = nil
            updateSelection(popup.Rows[index])
            popup.Rows[index]:Hide()
        end
    end
    viewport:HookScript("OnVerticalScroll", function(_, offset) render(offset) end)
    viewport:EnableMouseWheel(true)
    viewport:SetScript("OnMouseWheel", function(self, delta)
        local offset = math.max(0, math.min(popup.maxScroll or 0, self:GetVerticalScroll() - delta * step * 3))
        self:SetVerticalScroll(offset)
        render(offset)
    end)
    local function refresh()
        local ids = indexedQuestIDs()
        L.SetOptionsText(frame.QuestRange, #ids > 0 and (ids[1] .. "–" .. ids[#ids]) or "Индекс пуст")
        L.SetOptionsText(frame.CatalogSummary, questSummary)
        for index, source in ipairs({"wowvoice", "catquest"}) do
            local legend = frame.SourceLegend[source]
            local available = Comparison.SourceAvailable(source)
            sourceAppearance(legend.Marker, source, available)
            L.SetOptionsText(legend.Caption, legend.Name .. (available and "" or " — недоступна"))
            local columnWidth = (frame:GetWidth() - 40) / 2
            legend.Marker:ClearAllPoints()
            legend.Marker:SetPoint("TOPLEFT", frame, "TOPLEFT", 20 + (index - 1) * columnWidth, -88)
            legend.Caption:ClearAllPoints()
            legend.Caption:SetPoint("LEFT", legend.Marker, "RIGHT", 4, 0)
            legend.Caption:SetWidth(columnWidth - 28)
        end
        frame.CatalogSummary:SetWidth(math.max(240, frame:GetWidth() - 40))
        local hasFilter = (input:GetText() or "") ~= ""
        frame.ClearFilter:SetEnabled(hasFilter)
        if hasFilter then frame.ClearFilter:Show() else frame.ClearFilter:Hide() end
        local searchPrefix = strtrim(input:GetText() or "")
        local matches = {}
        for _, id in ipairs(ids) do
            if tostring(id):sub(1, #searchPrefix) == searchPrefix then
                matches[#matches + 1] = id
            end
        end
        popup.matches, popup.matchCount = matches, #matches
        local width = math.max(240, frame:GetWidth() - 40)
        local gridWidth = width - padding - 28
        popup.columns = math.max(1, math.min(12, math.floor((gridWidth + gap) / 62)))
        popup.cellWidth = (gridWidth - (popup.columns - 1) * gap) / popup.columns
        local gridHeight = math.ceil(#matches / popup.columns) * step - gap
        popup.viewportHeight = math.max(step, frame:GetHeight() - 136 - 2 * padding)
        popup.maxScroll = math.max(0, gridHeight - popup.viewportHeight)
        popup:SetSize(width, popup.viewportHeight + 2 * padding)
        grid:SetSize(gridWidth, math.max(popup.viewportHeight, gridHeight))
        viewport:SetVerticalScroll(0)
        viewport:UpdateScrollChildRect()
        render(0)
        popup:Show()
    end
    input:SetScript("OnTextChanged", refresh)
    frame.ResetQuestSearch = function()
        selectedID, selectedSource = nil, nil
        if input:GetText() ~= "" then
            input:SetText("")
        else
            refresh()
        end
    end
    frame:HookScript("OnShow", refresh)
    frame:HookScript("OnSizeChanged", refresh)
    WV.RefreshAudioSourceDebug = function() refresh() end
    input:SetScript("OnEscapePressed", function() input:ClearFocus() end)
    frame:HookScript("OnHide", function() popup:Hide() end)
end

local function showOptions()
    if not panel then return end
    panel.ResetQuestSearch()
    panel:Hide()
    panel.Scroll:Hide()
    panel.Options.Scroll:Show()
    WV:HideHeadPreview()
end

local function createPanel(options)
    -- Fixed page viewport: only the quest grid needs a scrollbar.
    local scroll = CreateFrame("ScrollFrame", "WowVoiceLocalDebugScroll", options)
    scroll:SetPoint("TOPLEFT", options, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", options, "BOTTOMRIGHT", 0, 0)
    scroll:Hide()
    local frame = CreateFrame("Frame", "WowVoiceLocalDebugPanel", scroll)
    frame:SetSize(584, 400)
    -- SetScrollChild alone does not establish our content's layout anchor.
    -- In particular this view is constructed while its viewport is hidden.
    frame:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    scroll:SetScrollChild(frame)
    scroll:SetScript("OnSizeChanged", function(self, width, height)
        frame:SetSize(math.max(584, width), math.max(180, height))
        self:UpdateScrollChildRect()
    end)
    frame.Scroll, frame.Options, frame.Buttons = scroll, options, {}

    local function label(text, x, y, width, height, font)
        local value = frame:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
        value:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
        value:SetSize(width, height)
        value:SetJustifyH("LEFT")
        L.SetOptionsText(value, text)
        return value
    end
    label("Озвучка заданий", 126, -16, 438, 26, "GameFontNormalLarge")
    local back = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    back:SetSize(90, 26)
    back:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -16)
    L.SetOptionsText(back, "Назад")
    back:SetScript("OnClick", showOptions)
    frame.Back, frame.Buttons.Back = back, back
    label("ID квеста:", 20, -60, 90, 20, "GameFontNormal")
    local input = CreateFrame("EditBox", "WowVoiceLocalDebugQuestID", frame, "BackdropTemplate")
    input:SetSize(140, 20)
    input:SetPoint("TOPLEFT", frame, "TOPLEFT", 116, -60)
    input:SetAutoFocus(false)
    input:SetFontObject("GameFontHighlightSmall")
    input:SetJustifyH("LEFT")
    backdrop(input, 0.5)
    input:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(0.5, 0.5, 0.5, 1) end)
    input:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8) end)
    input:SetNumeric(true)
    input:SetMaxLetters(5)
    input:SetText("")
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame.QuestID = input
    local function readID()
        local value = strtrim(input:GetText() or "")
        local id = tonumber(value)
        if not value:match("^%d+$") or not id or id <= 0 then
            return
        end
        input:ClearFocus()
        return id
    end
    local function play()
        local id = readID()
        if not id then return end
        frame.ListenQuest(id)
    end
    input:SetScript("OnEnterPressed", play)
    -- Same Blizzard search-clear atlas used by Details' search fields.
    input:SetTextInsets(6, 21, 0, 0)
    local clear = CreateFrame("Button", nil, input)
    clear:SetSize(16, 16)
    clear:SetPoint("RIGHT", input, "RIGHT", -3, 0)
    local function clearTexture(layer, shade, offset)
        local texture = clear:CreateTexture(nil, layer)
        texture:SetAtlas("common-search-clearbutton")
        texture:SetSize(14, 14)
        texture:SetPoint("CENTER", clear, "CENTER", offset, -offset)
        texture:SetVertexColor(shade, shade, shade)
        return texture
    end
    clear:SetNormalTexture(clearTexture("ARTWORK", 0.65, 0))
    local highlight = clearTexture("HIGHLIGHT", 1, 0)
    highlight:SetBlendMode("ADD")
    clear:SetHighlightTexture(highlight)
    clear:SetPushedTexture(clearTexture("ARTWORK", 1, 1))
    clear:SetScript("OnClick", function()
        input:SetText("")
        input:SetFocus()
    end)
    frame.ClearFilter = clear
    local range = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    range:SetPoint("LEFT", input, "RIGHT", 12, 0)
    range:SetTextColor(0.7, 0.7, 0.7)
    frame.QuestRange = range
    frame.CatQuestLegend, frame.SourceLegend = {}, {}
    for index, entry in ipairs({{"wowvoice", "WowVoice"}, {"catquest", "CatQuest"}}) do
        local marker = CreateFrame("Frame", nil, frame)
        marker:SetSize(20, 20)
        marker:SetPoint("TOPLEFT", frame, "TOPLEFT", 20 + (index - 1) * 150, -88)
        marker.Icon = playIcon(marker, colors[entry[1]])
        marker.UnavailableMark = unavailableMark(marker)
        local caption = label(entry[2], 44 + (index - 1) * 150, -88, 120, 20)
        frame.SourceLegend[entry[1]] = { Marker = marker, Caption = caption, Name = entry[2] }
        if entry[1] == "catquest" then frame.CatQuestLegend = {marker, caption} end
    end
    local summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 2)
    summary:SetHeight(16)
    summary:SetJustifyH("LEFT")
    summary:SetTextColor(0.7, 0.7, 0.7)
    frame.CatalogSummary = summary
    frame:SetScript("OnShow", function()
        for _, value in pairs(frame.Buttons) do
            if WV.StyleButton then WV.StyleButton(value) end
        end
    end)
    frame:SetScript("OnHide", function() input:ClearFocus() end)
    attachQuestSuggestions(frame, input)
    frame:Hide()
    return frame
end

local function showDebug(options, value)
    if not panel then
        panel = createPanel(options)
        options:HookScript("OnHide", showOptions)
    end
    if value and value ~= "" then panel.QuestID:SetText(value) end
    WV:EndHeadScalePreview(true)
    WV:HideHeadPreview()
    options.PositionX:ClearFocus()
    options.PositionY:ClearFocus()
    options.ScaleInput:ClearFocus()
    options.editingPosition = nil
    options.Scroll:Hide()
    panel.Scroll:Show()
    panel:SetSize(math.max(584, panel.Scroll:GetWidth()), math.max(180, panel.Scroll:GetHeight()))
    panel:Show()
    panel.Scroll:UpdateScrollChildRect()
    panel.Scroll:SetVerticalScroll(0)
end

function WV:OpenVoiceComparison(value)
    self:OpenOptions()
    local options = _G.WowVoiceOptionsPanel
    if options and options:IsShown() then showDebug(options, strtrim(value or "")) end
end
SLASH_WOWVOICELOCALDEBUG1 = "/wvvoices"
SlashCmdList.WOWVOICELOCALDEBUG = function(value) WV:OpenVoiceComparison(value) end

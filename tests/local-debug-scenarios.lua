local function isSelected(row)
    assert(not row.Selection, 'Tiles must not have a selection outline')
    for _, button in pairs(row.PlayButtons) do
        if button.SelectedMark.visible then return true end
    end
    return false
end
local function clickTile(row, source)
    source = source or (row.PlayButtons.wowvoice:IsEnabled() and "wowvoice" or "catquest")
    local button = row.PlayButtons[source]
    button.scripts.OnClick(button)
end
local options = WowVoiceOptionsPanel
-- Settings supplies these bounds in the client. Unlike SetScrollChild, they
-- establish where the viewport is actually rendered on screen.
options:SetSize(620, 640)
options:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)
local button = options.VoiceComparisonButton
assert(button and button.text == 'Послушать озвучку' and button.parent == options.Content)
WV:RefreshHeadOptions()
assert(options.VoiceComparisonButton == button, 'Repeated refresh must not duplicate the button')
assert(not WowVoiceLocalDebugPanel, 'Debug view must be created on demand')
options.Scroll:SetVerticalScroll(125)
SlashCmdList.WOWVOICELOCALDEBUG('')
local panel = WowVoiceLocalDebugPanel
assert(panel:IsVisible() and not options.Scroll:IsShown(), 'Debug must replace the main view')
assert(panel.parent == panel.Scroll and panel.Scroll.parent == options, 'Debug must stay inside Settings')
local function assertVisibleControls()
    local sx, sy = panel.Scroll:GetCenter()
    local sw, sh = panel.Scroll:GetWidth(), panel.Scroll:GetHeight()
    for _, control in ipairs({panel.Back, panel.QuestID, panel.ClearFilter}) do
        local x, y = control:GetCenter()
        assert(x and y, 'Shown debug control has no screen position')
        assert(x - control:GetWidth()/2 >= sx - sw/2 and x + control:GetWidth()/2 <= sx + sw/2
            and y - control:GetHeight()/2 >= sy - sh/2 and y + control:GetHeight()/2 <= sy + sh/2,
            'Debug control is clipped outside the viewport')
    end
end
assertVisibleControls()
assert(#UISpecialFrames == 0 and not panel.backdrop, 'Debug must not create a standalone window')
assert(not panel.Play, 'Playback must use quest cells instead of a separate button')
local buttonCount = 0
for _ in pairs(panel.Buttons) do buttonCount = buttonCount + 1 end
assert(buttonCount == 1 and not panel.Status and panel.QuestRange)
assert(#panel.regions == 6 and panel.regions[1]:GetText() == 'Озвучка заданий', 'Expected heading, field, range, two source labels and catalogue summary')
assert(not panel.ClearFilter:IsEnabled())
assert(not panel.ClearFilter:IsShown() and panel.ClearFilter.parent == panel.QuestID)
assert(panel.ClearFilter.normalTexture.atlas == 'common-search-clearbutton')
assert(panel.ClearFilter.highlightTexture.atlas == 'common-search-clearbutton')
panel.QuestID:SetText('861')
panel.Back.scripts.OnClick()
assert(not panel:IsShown() and not panel.Scroll:IsShown() and options.Scroll:IsShown())
assert(options.Scroll:GetVerticalScroll() == 125, 'Navigation must preserve main view scroll position')
WV:OpenOptions()
button.scripts.OnClick()
assert(panel:IsVisible() and panel.QuestID:GetText() == '', 'Back must clear the filter')
assertVisibleControls()
options:Hide()
assert(not panel:IsShown() and options.Scroll:IsShown(), 'Closing Settings must reset navigation')
WV:OpenOptions()
assert(not panel:IsShown() and options.Scroll:IsVisible(), 'Settings must reopen at the main view')

-- No quest log and no saved description: ID playback still starts the head.
C_QuestLog.GetNumQuestLogEntries = function() return 0 end
C_QuestLog.GetInfo = function() error('No quest rows should be read') end
SlashCmdList.WOWVOICELOCALDEBUG('179')
clickTile(panel.Suggestions.Rows[1])
assert(#plays > 0 and plays[#plays].file:find('179a', 1, true))
assert(frames.TalkingHeadRu:IsShown())
local playingCount, stopCount = #plays, #stops
assert(isSelected(panel.Suggestions.Rows[1]))
local summary = panel.CatalogSummary:GetText()
assert(panel.ClearFilter:IsEnabled())
assert(panel.ClearFilter:IsShown())
panel.ClearFilter.scripts.OnClick()
assert(panel.QuestID:GetText() == '' and panel.QuestID.focus and not panel.ClearFilter:IsEnabled())
assert(not panel.ClearFilter:IsShown(), 'Clear icon must disappear after clearing the filter')
assert(panel.Suggestions.matchCount > 1000 and panel.CatalogSummary:GetText() == summary)
assert(#plays == playingCount and #stops == stopCount, 'Clearing the filter must not affect playback')
panel.QuestID:SetText('179')
assert(isSelected(panel.Suggestions.Rows[1]), 'Clearing only the filter must preserve selected source')
panel.Back.scripts.OnClick()
button.scripts.OnClick()
assert(panel.QuestID:GetText() == '' and panel.Suggestions.Viewport:GetVerticalScroll() == 0)
local fullCount = panel.Suggestions.matchCount
assert(fullCount > 1000, 'Back must restore the full catalogue')
for _, row in ipairs(panel.Suggestions.Rows) do assert(not isSelected(row)) end
panel.QuestID:SetText('179')
assert(not isSelected(panel.Suggestions.Rows[1]), 'Cleared selection must not reappear after filtering')
assert(#plays == playingCount and #stops == stopCount and frames.TalkingHeadRu:IsShown(),
    'View navigation must not interrupt or restart quest playback')
clickTile(panel.Suggestions.Rows[1])
playingCount, stopCount = #plays, #stops
assert(isSelected(panel.Suggestions.Rows[1]))
options:Hide()
assert(panel.QuestID:GetText() == '' and panel.Suggestions.Viewport:GetVerticalScroll() == 0,
    'Closing Settings must clear the Debug filter and scroll')
WV:OpenOptions()
button.scripts.OnClick()
assert(panel.QuestID:GetText() == '' and panel.Suggestions.matchCount == fullCount)
panel.QuestID:SetText('179')
assert(not isSelected(panel.Suggestions.Rows[1]), 'Closing Settings must clear the selected source')
assert(#plays == playingCount and #stops == stopCount, 'Closing Settings must preserve playback')
WV:Silence()
assert(not frames.TalkingHeadRu:IsShown())
local count = #plays
for _, value in ipairs({'0', '-1', '1.5', 'abc', '1e3', ''}) do
    panel.QuestID:SetText(value)
    panel.QuestID.scripts.OnEnterPressed()
    assert(#plays == count, 'Invalid ID played audio: ' .. value)
end
panel.QuestID:SetText('999999')
panel.QuestID.scripts.OnEnterPressed()
assert(#plays == count and has('нет записи'))
panel.QuestID:SetText('179')
command('off')
clickTile(panel.Suggestions.Rows[1])
assert(#plays == count and has('озвучка выключена'))
command('on')
panel.QuestID.scripts.OnEnterPressed()
assert(#plays == count + 1 and plays[#plays].file:find('179a', 1, true), 'Enter must replay a valid ID')
WV:Silence()
print('PASS: minimal Debug page, click-to-play, Back clears filter/selection, preserved playback and ID validation')

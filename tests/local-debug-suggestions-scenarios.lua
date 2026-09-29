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
local panel = WowVoiceLocalDebugPanel
local input, popup = panel.QuestID, panel.Suggestions
local coordinates = WowVoiceOptionsPanel.PositionX
assert(input.template == coordinates.template and input.height == coordinates.height
    and input.fontObject == coordinates.fontObject and input.backdrop.edgeSize == coordinates.backdrop.edgeSize,
    'Quest field must match coordinate input styling')

-- Independently collect introduction IDs from the active sources and compare the
-- complete result counts, boundaries and the numerically sorted first page.
local known = {}
for key in pairs(WowVoiceDur) do
    local id = tonumber(key:match('^(%d+)a$'))
    if id then known[id] = true end
end
local source = WowVoiceAudioSources.Status()
for key in pairs(source and source.entries or {}) do
    local id = tonumber(key:match('^(%d+)a$'))
    if id and not WowVoiceDur[id .. 'a'] and not WowVoiceDur[id .. 'p'] and not WowVoiceDur[id .. 'c'] then
        known[id] = true
    end
end
for key in pairs(WowVoiceCatQuestAudio.entries) do
    local id = tonumber(key:match('^(%d+)a$'))
    if id then known[id] = true end
end
local sorted = {}
for id in pairs(known) do sorted[#sorted+1] = id end
table.sort(sorted)
assert(panel.QuestRange:GetText() == sorted[1] .. '–' .. sorted[#sorted])
local wowvoiceCount, catquestCount = 0, 0
for key in pairs(WowVoiceDur) do if key:match('^%d+a$') then wowvoiceCount = wowvoiceCount + 1 end end
for key in pairs(WowVoiceCatQuestAudio.entries) do if key:match('^%d+a$') then catquestCount = catquestCount + 1 end end
assert(panel.CatalogSummary:GetText() == string.format(
    'WowVoice: %d    CatQuest: %d    Всего без повторов: %d', wowvoiceCount, catquestCount, #sorted))
local function search(prefix)
    input:SetText(prefix)
    input:SetFocus()
    local expected = {}
    for _, id in ipairs(sorted) do
        if tostring(id):find(prefix, 1, true) == 1 then expected[#expected+1] = id end
    end
    assert(popup:IsShown() and popup.matchCount == #expected)
    assert(#popup.matches == #expected, 'Search results were truncated')
    for index, id in ipairs(expected) do
        assert(popup.matches[index] == id, 'Unexpected or duplicate ID in suggestions')
    end
    return #expected
end
assert(search('1') > 8)
assert(popup.columns == 8 and not popup.Footer)
assert(popup:GetWidth() == panel:GetWidth() - 40)
assert(popup:GetHeight() + 116 <= panel.Scroll:GetHeight(), 'Popup escapes viewport')
assert(popup:GetHeight() + 136 == panel:GetHeight(), 'List must fill the remaining page height')
assert(#popup.Rows < popup.matchCount, 'Long prefixes must pool visible cells')
local selected = popup.Rows[3].questID
local playSource, requested = WowVoiceComparison.Play, {}
WowVoiceComparison.Play = function(id, source)
    requested[#requested + 1] = id
    return playSource(id, source)
end
local results = popup.matches
popup.mouseOver = true
input:ClearFocus()
assert(popup:IsShown(), 'Mouse-down focus loss must keep suggestions clickable')
clickTile(popup.Rows[3])
assert(input:GetText() == '1' and popup:IsShown() and #requested == 1 and requested[1] == selected,
    'Clicking an ID must immediately request playback of that quest')
assert(popup.matches == results, 'Selection must preserve the search results')
assert(isSelected(popup.Rows[3]), 'Clicked play button must be highlighted')
clickTile(popup.Rows[4])
assert(not isSelected(popup.Rows[3]) and isSelected(popup.Rows[4]),
    'Only the newly selected play button must be highlighted')
assert(input:GetText() == '1', 'Selecting another quest must not edit the filter')
popup.mouseOver = false
assert(search('179') > 0 and popup.Rows[1].questID == 179)
-- Every result of a broad two-digit prefix remains reachable by scrolling.
assert(search('94') > 100)
for _, row in ipairs(popup.Rows) do
    assert(not isSelected(row), 'Reused cells must not inherit another play button highlight')
end
local seen, iterations = {}, 0
while true do
    for _, row in ipairs(popup.Rows) do
        if row:IsShown() then seen[row.questID] = true end
    end
    if popup.Viewport:GetVerticalScroll() == popup.maxScroll then break end
    popup.Viewport.scripts.OnMouseWheel(popup.Viewport, -1)
    iterations = iterations + 1
    assert(iterations < 100, 'Scrolling did not reach the final row')
end
for _, id in ipairs(popup.matches) do assert(seen[id], 'A matching ID is unreachable') end
local last
for _, row in ipairs(popup.Rows) do if row:IsShown() then last = row end end
assert(last.questID == popup.matches[#popup.matches])
selected = last.questID
results = popup.matches
local scrollOffset = popup.Viewport:GetVerticalScroll()
clickTile(last)
assert(input:GetText() == '94' and #requested == 3 and requested[3] == selected and popup:IsShown(),
    'Reused cells must play their current quest ID after scrolling')
assert(popup.matches == results, 'Playback must preserve the filtered results')
assert(popup.Viewport:GetVerticalScroll() == scrollOffset, 'Selection must not jump back to the top')
assert(isSelected(last))
popup.Viewport.scripts.OnMouseWheel(popup.Viewport, 1000)
for _, row in ipairs(popup.Rows) do
    assert(not isSelected(row), 'Scrolling away must not move selection onto a reused cell')
end
popup.Viewport.scripts.OnMouseWheel(popup.Viewport, -1000)
local restored = false
for _, row in ipairs(popup.Rows) do
    if row.questID == selected then restored = isSelected(row) end
end
assert(restored, 'Scrolling back must restore the selected play button highlight')
-- Resizing changes the column count while retaining all results and bounds.
panel:SetSize(900, 400)
search('94')
panel.scripts.OnSizeChanged(panel)
assert(popup.columns == 12 and popup:GetHeight() + 116 <= panel:GetHeight())
panel:SetSize(584, 640)
search(tostring(sorted[#sorted]))
assert(popup.Rows[1].questID == sorted[#sorted], 'Supplemental upper boundary missing')
assert(search('9999999999') == 0 and popup:IsShown())
assert(popup:GetHeight() + 136 == panel:GetHeight(), 'Empty results must retain list size')
assert(search('') == #sorted, 'Empty input must show the full catalogue')
assert(WowVoiceDur['247c'] and not WowVoiceDur['247a'], '247 must exercise completion-only audio')
for _, id in ipairs(popup.matches) do
    assert(id ~= 247 and (WowVoiceDur[id .. 'a'] or WowVoiceCatQuestAudio.entries[id .. 'a']),
        'Every listed quest must have a known introduction')
end
search('247')
for _, id in ipairs(popup.matches) do assert(id ~= 247, 'Completion-only quest must not appear in filtered results') end
for _, value in ipairs({'x', '-1', '1.5'}) do
    input:SetText(value)
    assert(popup:IsShown() and popup.matchCount == 0, 'Invalid input must clear rows without collapsing the list')
    for _, row in ipairs(popup.Rows) do assert(not row:IsShown()) end
end
search('1')
input.scripts.OnEscapePressed()
assert(popup:IsShown() and not input.focus)
search('1')
input:ClearFocus()
assert(popup:IsShown(), 'Clicking outside must keep results visible')
search('1')
WowVoiceOptionsPanel:Hide()
assert(not popup:IsShown())
WowVoice:OpenOptions()
WowVoiceOptionsPanel.VoiceComparisonButton.scripts.OnClick()
assert(popup:IsShown(), 'Returning to Debug must restore the results without focus')
input:SetText('179')
input:SetFocus()
popup.mouseOver = true
local before = #plays
clickTile(popup.Rows[1])
assert(#plays == before + 1 and plays[#plays].file:find('179a', 1, true), 'Click must start quest audio')
assert(popup:IsShown(), 'Playback must preserve the list')
popup.mouseOver = false
WowVoice:Silence()
WowVoiceComparison.Play = playSource
-- Consecutive clicks must replace active audio on the first click, including
-- switching back to a previously selected quest without editing the filter.
search('17')
local function cellFor(id)
    for _, row in ipairs(popup.Rows) do
        if row:IsShown() and row.questID == id then return row end
    end
    error('Missing visible quest ' .. id)
end
local matches = popup.matches
local previous
for _, id in ipairs({179, 170, 179, 170}) do
    local row = cellFor(id)
    local count = #plays
    clickTile(row)
    assert(#plays == count + 1 and plays[#plays].file:find(id .. 'a.ogg', 1, true),
        'Each consecutive click must immediately play its quest')
    if previous then assert(stops[#stops] == previous, 'Previous recording must stop') end
    previous = plays[#plays].handle
    assert(isSelected(row) and input:GetText() == '17' and popup.matches == matches)
end
WowVoice:Silence()
local originalPlayMusic, originalStopMusic = PlayMusic, StopMusic
local backgroundAudio, streams = cvars.Sound_EnableSoundWhenGameIsInBG, {}
PlayMusic = function(path) streams[#streams + 1] = path; return true end
StopMusic = function() end
cvars.Sound_EnableSoundWhenGameIsInBG = '0'
for _, id in ipairs({179, 170, 179, 170}) do
    local row, count = cellFor(id), #streams
    clickTile(row)
    assert(#streams == count + 1 and streams[#streams]:find(id .. 'a.ogg', 1, true),
        'Music playback must also switch on every click')
    assert(isSelected(row) and input:GetText() == '17' and popup.matches == matches)
end
WowVoice:Silence()
PlayMusic, StopMusic = originalPlayMusic, originalStopMusic
cvars.Sound_EnableSoundWhenGameIsInBG = backgroundAudio
print('PASS: full-page persistent quest grid, full catalogue/prefixes, 8-12 columns, virtualized scrolling, selection preserves results/scroll and playback/focus lifecycle')

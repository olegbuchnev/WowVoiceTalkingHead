event('ADDON_LOADED')
local WV = WowVoice
local events = frames.WowVoiceTrackerEvents
local deferred = {}
C_Timer = {After=function(_, fn) deferred[#deferred+1]=fn end}
local function flush()
    local pending = deferred; deferred = {}
    for _, fn in ipairs(pending) do fn() end
end

-- Questie can load after the native tracker has already been hooked.
QuestObjectiveTracker = CreateFrame('Frame', nil, UIParent)
QuestObjectiveTracker.usedBlocks = {}
function QuestObjectiveTracker:Update() end
function QuestObjectiveTracker:FreeBlock() end
events.scripts.OnEvent(events, 'ADDON_LOADED', 'Blizzard_ObjectiveTracker')

local host = CreateFrame('Frame', nil, UIParent)
local scroll = CreateFrame('ScrollFrame', nil, host)
function scroll:IsObjectType(kind) return kind == 'ScrollFrame' end
function scroll:GetTop() return 600 end
function scroll:GetBottom() return 200 end
local child = CreateFrame('Frame', nil, scroll)
local lines = {}
local function row(id, mode, y)
    local line = CreateFrame('Button', nil, child)
    line.mode, line.Quest, line.y = mode or 'quest', {Id=id}, y or 500
    line.label = line:CreateFontString(nil, 'ARTWORK', 'QuestTitleFont')
    line.label:SetPoint('TOPLEFT', line, 'TOPLEFT', 24, 0)
    line.label:SetWidth(320)
    function line.label:GetTop() return line.y end
    line.expandQuest = CreateFrame('Button', nil, line)
    line.expandQuest:SetPoint('TOPRIGHT', line, 'TOPLEFT', 16, 1)
    line.expandQuest:SetSize(17, 17)
    function line:GetScript(script) return self.scripts[script] end
    line:SetScript('OnEnter', function() line.nativeHover=true end)
    line:SetScript('OnLeave', function() line.nativeHover=false end)
    lines[#lines+1] = line
    return line
end
local first, complete, objective = row(179), row(192, 'quest', 440), row(179, 'objective', 470)
local missing, zone = row(999999, 'quest', 380), row(0, 'zone', 550)
complete.expandQuest:Hide()
local pool, tracker = {}, {}
function pool.UpdateQuestTitleLines(callback)
    for _, line in ipairs(lines) do if line.mode == 'quest' then callback(line) end end
end
function pool.ResetLinesForChange()
    for _, line in ipairs(lines) do line.mode=nil end
end
function tracker:Update() end
function tracker:UpdateFormatting() end
QuestieLoader = {ImportModule=function(_, name)
    if name == 'TrackerLinePool' then return pool end
    if name == 'QuestieTracker' then return tracker end
    error('unnecessary module dependency: ' .. name)
end}
events.scripts.OnEvent(events, 'ADDON_LOADED', 'Questie')
flush()
local function playFor(line)
    for _, frame in ipairs(allFrames) do if frame.questieLine == line then return frame end end
end
local play, done = assert(playFor(first)), assert(playFor(complete))
assert(play.visible and done.visible and play.questID==179 and done.questID==192)
assert(not playFor(objective) and not playFor(missing) and not playFor(zone))
assert(play:GetParent()==host, 'left column must be outside horizontal scroll clipping')
assert(play.points[1][2]==first.expandQuest and done.points[1][2]==complete.expandQuest)
assert(play.points[1][4]==done.points[1][4], 'completed quests retain the same column')
assert(not complete.expandQuest.visible, 'do not show native controls')
assert(first.label.point[4]==24 and first.label.width==320, 'native indent/width must stay intact')
play.scripts.OnEnter(play); assert(first.nativeHover)
play.scripts.OnLeave(play); assert(not first.nativeHover)
play.scripts.OnClick(play)
assert(plays[#plays].file:find('179a.ogg', 1, true))
WV:Silence()

-- A secondary quest item and wrapped titles change text geometry, not the column.
first.label:SetPoint('TOPLEFT', first, 'TOPLEFT', 52, 0)
first.label:SetHeight(48)
first.expandQuest:Hide()
tracker:UpdateFormatting(); flush()
assert(play.visible and play.points[1][2]==first.expandQuest and first.label.point[4]==52)
assert(first.label.width==320 and first.label.height==48)
local anchorY = play.points[1][5]
first.label:SetFont('Font', 20, '')
tracker:UpdateFormatting(); flush()
assert(play.points[1][5]~=anchorY and play.points[1][5]==-10, 'align with the first title line')
assert(play.width==24 and play.Icon.width==24)
assert(math.abs(play.ProgressGlow.width-33.6)<0.0001, 'glow follows changed quest font size')
assert(play.points[1][4] < -3, 'gap scales with the quest font')
first.label:SetFont('Font', 9, '')
tracker:UpdateFormatting(); flush()
assert(play.width==13 and play.points[1][5]==-4.5)
first.label:SetFont('Font', 20, '')
tracker:UpdateFormatting(); flush()
host:SetScale(1.5)
child:SetScale(1.2)
tracker:UpdateFormatting(); flush()
assert(math.abs(play:GetEffectiveScale()-first:GetEffectiveScale())<0.0001)
child:SetScale(1); host:SetScale(1)

-- Independently parented buttons must follow vertical clipping and row hiding.
first.y=610
scroll.scripts.OnVerticalScroll(scroll, 30); flush()
assert(not play.visible and done.visible)
local count=#plays
play.scripts.OnClick(play); assert(#plays==count)
first.y=205
scroll.scripts.OnVerticalScroll(scroll, 80); flush()
assert(not play.visible, 'hide partially clipped controls at the bottom')
first.y=500
scroll.scripts.OnVerticalScroll(scroll, 0); flush()
assert(play.visible)
first:Hide(); assert(not play.visible and not play.active)
first:Show(); flush(); assert(play.visible)

-- Pool reset/reuse must never leave a clickable ID from the previous occupant.
pool.ResetLinesForChange()
assert(not play.visible and not done.visible)
first.mode='objective'; first.Quest={Id=192}
tracker:Update(); flush()
assert(not play.visible)
first.mode='quest'; first.Quest={Id=861}
tracker:Update(); flush()
assert(play.visible and play.questID==861)
play.scripts.OnClick(play)
assert(plays[#plays].file:find('861a.ogg', 1, true))
WV:Silence()
first.mode='zone' -- even before an update, the click must reject a recycled row
count=#plays
play.scripts.OnClick(play); assert(#plays==count)
first.mode='quest'; first.Quest={Id=999998}
tracker:Update(); flush(); assert(not play.visible)
first.Quest={Id=179}; tracker:Update(); flush()

-- Common options, progress preview, failure handling and no duplicate hooks.
WV:SetTrackerButtonsEnabled(false); assert(not play.visible)
WV:SetTrackerButtonsEnabled(true); assert(play.visible)
WV:SetTrackerPulsePreview(true); assert(play.ProgressGlow.visible)
WV:SetTrackerPulsePreview(false); assert(not play.ProgressGlow.visible)
WV:OpenOptions()
local options = frames.WowVoiceOptionsPanel
for _, explicitTest in ipairs({false, true}) do
    for _, numeric in ipairs({false, true}) do
        WV:HideHeadPreview()
        if explicitTest then options.Buttons.test.scripts.OnClick(); assert(play.ProgressGlow.visible) end
        if numeric then
            options.ScaleInput:SetText('110')
            options.ScaleInput.scripts.OnEnterPressed(options.ScaleInput)
        else
            options.ScaleSlider.scripts.OnMouseDown(options.ScaleSlider, 'LeftButton')
            options.ScaleSlider:SetValue(115)
        end
        assert(not play.ProgressGlow.visible and not done.ProgressGlow.visible, 'Scaling lit Questie buttons')
        if not numeric then options.ScaleSlider.scripts.OnMouseUp(options.ScaleSlider, 'LeftButton') end
        assert(not play.ProgressGlow.visible)
        WV:HideHeadPreview()
    end
end
local created=#allFrames
for _=1,5 do
    events.scripts.OnEvent(events, 'ADDON_LOADED', 'OtherAddon')
    tracker:Update(); tracker:UpdateFormatting()
end
assert(#deferred==1, 'coalesce Questie redraw/formatting callbacks')
flush()
assert(#allFrames==created)
assert(hookCounts[tostring(tracker)..'.Update']==1)
assert(hookCounts[tostring(tracker)..'.UpdateFormatting']==1)
assert(hookCounts[tostring(pool)..'.ResetLinesForChange']==1)
soundOK=false
play.scripts.OnClick(play)
assert(not play.visible, 'failed recordings hide Questie replay just like native replay')
soundOK=true
print('PASS: optional Questie adapter, completed/item/wrapped rows, fixed column, scroll clipping, scale, pooling, settings and shared playback')

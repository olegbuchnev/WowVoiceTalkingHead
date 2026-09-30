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
    line:SetSize(360, 22)
    function line:GetCenter() return 200, self.y - self:GetHeight() / 2 end
    function line:GetChildren()
        local children = {}
        for _, frame in ipairs(allFrames) do
            if frame:GetParent() == self then children[#children+1] = frame end
        end
        return table.unpack(children)
    end
    line.label = line:CreateFontString(nil, 'ARTWORK', 'QuestTitleFont')
    -- Questie's margins are 14 + 30 - (18 - fontSize); the minus is 8px before the title.
    line.label:SetPoint('TOPLEFT', line, 'TOPLEFT', 44, 0)
    line.label:SetWidth(320)
    line.label:SetHeight(18)
    function line.label:GetHeight() return self.height end
    function line.label:GetCenter()
        local _, anchor, _, x, y = self:GetPoint()
        local cx, cy = anchor:GetCenter()
        return cx - anchor:GetWidth()/2 + x + self.width/2,
            cy + anchor:GetHeight()/2 + y - self.height/2
    end
    function line.label:GetTop() return line.y end
    line.expandQuest = CreateFrame('Button', nil, line)
    line.expandQuest:SetPoint('TOPRIGHT', line, 'TOPLEFT', 36, 1)
    line.expandQuest:SetSize(18, 18)
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
local function left(frame)
    local x = frame:GetCenter()
    return x - frame:GetWidth() / 2
end
local function right(frame)
    return left(frame) + frame:GetWidth()
end
local function before(playButton, nativeButton)
    assert(right(playButton) < left(nativeButton), 'play hit area overlaps a native Questie control')
end
local function nearTitle(playButton, line)
    local _, size = line.label:GetFont()
    local gap = left(line.label) - right(playButton)
    assert(gap > 0 and gap <= math.max(2, size * 3 / 14) + 0.001,
        'hidden minus must not leave a vacant control slot before the title')
end
assert(play.visible and done.visible and play.questID==179 and done.questID==192)
assert(not playFor(objective) and not playFor(missing) and not playFor(zone))
assert(play:GetParent()==host, 'left column must be outside horizontal scroll clipping')
before(play, first.expandQuest)
nearTitle(done, complete)
assert(right(play)>left(first), 'rows without items keep play close to the title, even when the minus is hidden')
assert(not complete.expandQuest.visible, 'do not show native controls')
assert(first.label.point[4]==44 and first.label.width==320, 'native indent/width must stay intact')
play.scripts.OnEnter(play); assert(first.nativeHover)
play.scripts.OnLeave(play); assert(not first.nativeHover)
play.scripts.OnClick(play)
assert(plays[#plays].file:find('179a.ogg', 1, true))
WV:Silence()

-- Completed quests and hidden minus controls must put play directly before text.
first.expandQuest:Hide(); tracker:Update(); flush()
nearTitle(play, first)
for _, size in ipairs({9, 12, 20}) do
    complete.label:SetFont('Font', size, '')
    tracker:UpdateFormatting(); flush()
    nearTitle(done, complete)
end
complete.label:SetFont('Font', 18, '')
first.expandQuest:Show(); tracker:Update(); flush()
before(play, first.expandQuest)
local minusPosition = right(play)
first.expandQuest:SetAlpha(0); tracker:UpdateFormatting(); flush()
assert(right(play)==minusPosition, 'a fading minus still reserves its native control slot')
first.expandQuest:SetAlpha(1)

-- Questie places its primary item at the row's left edge and hides the minus.
local function questItem(line, id, x)
    local item = CreateFrame('Button', nil, line, 'SecureActionButtonTemplate')
    item:SetSize(30, 30)
    item:SetPoint('TOPLEFT', line, 'TOPLEFT', x, 0)
    item.itemId, item.questID = 12345, id
    item.attributes = {type1='item', item1='item:12345'}
    function item:GetAttribute(key) return self.attributes[key] end
    function item:SetAttribute(key, value) self.attributes[key] = value end
    return item
end
local item = questItem(first, 179, 0)
first.expandQuest:Hide()
tracker:UpdateFormatting(); flush()
assert(play.visible and not first.expandQuest.visible)
before(play, item)
assert(right(play)<right(done), 'only rows with items move play left')
local itemPosition = right(play)
item:SetAlpha(0); tracker:UpdateFormatting(); flush()
assert(right(play)==itemPosition, 'hover fading must not move play')
item:SetAlpha(1)
assert(item:GetParent()==first and item.points[1][4]==0 and item.width==30 and item.visible,
    'native item position and hit area must stay intact')

-- A secondary item moves the wrapped title, while both items keep their hit areas.
local secondItem = questItem(first, 179, 32)
first.label:SetPoint('TOPLEFT', first, 'TOPLEFT', 76, 0)
first.label:SetHeight(48)
tracker:UpdateFormatting(); flush()
assert(play.visible and first.label.point[4]==76)
before(play, item); before(play, secondItem)
assert(first.label.width==320 and first.label.height==48)
local anchorY = play.points[1][5]
first.label:SetFont('Font', 20, '')
tracker:UpdateFormatting(); flush()
assert(play.points[1][5]~=anchorY and play.points[1][5]==-10, 'align with the first title line')
assert(play.width==24 and play.Icon.width==24)
assert(math.abs(play.ProgressGlow.width-33.6)<0.0001, 'glow follows changed quest font size')
assert(play.points[1][4] < -3, 'gap scales with the quest font')
before(play, item); before(play, secondItem)
first.label:SetFont('Font', 9, '')
tracker:UpdateFormatting(); flush()
assert(play.width==13 and play.points[1][5]==-4.5)
before(play, item); before(play, secondItem)
first.label:SetFont('Font', 20, '')
tracker:UpdateFormatting(); flush()
host:SetScale(1.5)
child:SetScale(1.2)
tracker:UpdateFormatting(); flush()
assert(math.abs(play:GetEffectiveScale()-first:GetEffectiveScale())<0.0001)
child:SetScale(1); host:SetScale(1)

-- Hiding items must move play back even without a tracker redraw.
item:Hide(); flush()
before(play, secondItem)
secondItem:Hide(); flush()
assert(right(play)>left(first), 'hidden pooled items do not reserve space')
nearTitle(play, first)
item:Show(); flush()
before(play, item)

-- Stale identities, detached controls and FakeHide attributes do not count.
item.questID=192; tracker:Update(); flush()
assert(right(play)>left(first), 'an item from the previous quest must not reserve space')
item.questID=179; item:SetParent(UIParent); tracker:Update(); flush()
assert(right(play)>left(first), 'items detached from the row do not reserve space')
item:SetParent(first); item:SetAttribute('type1', nil); tracker:Update(); flush()
assert(right(play)>left(first), 'FakeHide disables the item even before Hide')
item:SetAttribute('type1', 'item'); tracker:Update(); flush()
before(play, item)

-- Removing items restores compact placement without overlapping the minus.
item:Hide(); secondItem:Hide(); first.expandQuest:Show()
first.label:SetPoint('TOPLEFT', first, 'TOPLEFT', 44, 0)
tracker:UpdateFormatting(); flush()
before(play, first.expandQuest)
assert(right(play)>left(first))

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
item:Show() -- Still belongs to quest 179 when the title row is recycled.
tracker:Update(); flush()
assert(play.visible and play.questID==861)
assert(right(play)>left(first), 'a recycled row ignores the previous quest item')
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
WowVoiceDB.trackerButtons=false
WV:RefreshTrackerButtons(); assert(play.visible, 'obsolete opt-out cannot hide Questie buttons')
WowVoiceDB.trackerButtons=nil
WV:SetTrackerPulsePreview(true); assert(play.ProgressGlow.visible)
WV:SetTrackerPulsePreview(false); assert(not play.ProgressGlow.visible)
WV:OpenOptions()
local options = frames.WowVoiceOptionsPanel
for _, explicitTest in ipairs({false, true}) do
    for _, numeric in ipairs({false, true}) do
        WV:HideHeadPreview()
        if explicitTest then WV:ToggleHeadPreview(); assert(play.ProgressGlow.visible) end
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
flush() -- Drain portrait work scheduled by the now-public playlist before measuring redraw coalescing.
local created=#allFrames
local deferredBefore = #deferred
for _=1,5 do
    events.scripts.OnEvent(events, 'ADDON_LOADED', 'OtherAddon')
    tracker:Update(); tracker:UpdateFormatting()
end
assert(#deferred==deferredBefore + 1, 'coalesce Questie redraw/formatting callbacks')
flush()
assert(#allFrames==created)
assert(hookCounts[tostring(tracker)..'.Update']==1)
assert(hookCounts[tostring(tracker)..'.UpdateFormatting']==1)
assert(hookCounts[tostring(pool)..'.ResetLinesForChange']==1)
soundOK=false
play.scripts.OnClick(play)
assert(not play.visible, 'failed recordings hide Questie replay just like native replay')
soundOK=true
print('PASS: optional Questie adapter, compact completed rows, conditional item/minus placement, wrapping, scroll clipping, scale, pooling, settings and shared playback')

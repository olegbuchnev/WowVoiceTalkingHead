event('ADDON_LOADED')
local WV = WowVoice
local events = frames.WowVoiceTrackerEvents
events.scripts.OnEvent(events, 'PLAYER_LOGIN') -- optional module absent

local host = CreateFrame('Frame', nil, UIParent)
host:SetSize(400, 500)
host:SetPoint('TOPRIGHT', UIParent, 'TOPRIGHT', -20, -50)
local scroll = CreateFrame('ScrollFrame', nil, host)
function scroll:IsObjectType(kind) return kind == 'ScrollFrame' end
function scroll:GetTop() return 600 end
function scroll:GetBottom() return 200 end
local child = CreateFrame('Frame', nil, scroll)
local rows, callbacks, registrations, refreshes = {}, {}, 0, 0
local function row(id)
    local line = CreateFrame('Button', nil, child)
    line:SetSize(340, 36)
    line:SetScript('OnClick', function() line.nativeClick = true end)
    local title = line:CreateFontString(nil, 'ARTWORK', 'QuestTitleFont')
    title:SetFont('Font', 14, '')
    title:SetWidth(300)
    title:SetPoint('TOPLEFT', line, 'TOPLEFT', 0, 0)
    local slot = CreateFrame('Frame', nil, line)
    slot:SetWidth(32)
    slot:SetPoint('TOPLEFT', line, 'TOPRIGHT', 0, 0)
    local data = {id=id, line=line, title=title, slot=slot, kind='quest'}
    rows[#rows+1] = data
    return data
end
local first, second, missing = row(179), row(192), row(999999)
local function render()
    for _, data in ipairs(rows) do
        if data.kind == 'quest' then
            data.slot:Show()
            for _, callback in pairs(callbacks) do callback(data.slot, data.id, data.title) end
        else data.slot:Hide() end
    end
end
EllesmereUI = {
    RegisterQuestTrackerRow=function(id, callback, width)
        registrations = registrations + 1
        assert(id == 'TalkingHeadRu' and width == 32, 'use own addon ID and reserve space for play/glow')
        if callbacks[id] then return false end
        callbacks[id] = callback
        return true
    end,
    RefreshQuestTrackerRows=function() refreshes = refreshes + 1; render() end,
}
events.scripts.OnEvent(events, 'ADDON_LOADED', 'EllesmereUIQuestTracker')
local function playFor(data)
    for _, frame in ipairs(allFrames) do if frame.ellesmereSlot == data.slot then return frame end end
end
local play, other = assert(playFor(first)), assert(playFor(second))
assert(registrations == 1 and refreshes == 1 and not playFor(missing))
assert(play.visible and other.visible and play:GetParent() == first.slot)
assert(play.template == nil and play.width == 18, 'never create protected children of the custom tracker')
assert(play.points[1][2] == first.slot and play.points[1][4] < 0, 'button stays inside its reserved slot')
assert(first.title.width == 300 and first.title.point[4] == 0, 'never modify EUI title layout')
assert(#plays == 0, 'registration and redraw are silent')
first.line.scripts.OnClick(first.line)
assert(first.line.nativeClick, 'native row actions stay intact')
play.scripts.OnClick(play)
assert(plays[#plays].file:find('179a.ogg', 1, true))
WV:Silence()
local frameCount, soundCount = #allFrames, #plays
for i=1,5 do
    events.scripts.OnEvent(events, 'ADDON_LOADED', 'OtherAddon')
    WV:RefreshTrackerButtons(); render()
end
assert(registrations == 1 and #allFrames == frameCount and #plays == soundCount)

-- Row identity is supplied again on every render, never parsed from its title.
first.id = 861; render()
assert(play.questID == 861)
play.scripts.OnClick(play)
assert(plays[#plays].file:find('861a.ogg', 1, true))
WV:Silence()
first.id = 999999; render()
assert(not play.visible and not play.active)
soundCount = #plays
play.scripts.OnClick(play)
assert(#plays == soundCount)
first.id = 179; render()
assert(play.visible and play.active)
first.kind = 'objective'; render(); WV:RefreshTrackerButtons()
assert(not play.active and not play.visible, 'a slot reused as an objective cannot regain a stale play button')
play.scripts.OnClick(play)
assert(#plays == soundCount)
first.kind = 'quest'; first.id = 192; render()
assert(play.active and play.visible and play.questID == 192)

-- Parent scrolling, positioning and scale belong to EUI, with no overlay on UIParent.
host:Hide(); play.scripts.OnClick(play)
assert(#plays == soundCount and not play:IsVisible())
host:Show(); render()
host:SetScale(1.5)
assert(play:GetEffectiveScale() == first.slot:GetEffectiveScale())
local anchor = host.points[1]
WV:RefreshTrackerButtons()
assert(host.points[1] == anchor and host.width == 400 and host.height == 500)
first.title:SetFont('Font', 24, ''); render()
assert(play.width == 24 and math.abs(play.ProgressGlow.width - 33.6) < 0.001, 'large fonts remain inside the reserved width')

-- Existing playback, pulse and unavailable-audio behavior is shared with other trackers.
WV:SetTrackerPulsePreview(true)
assert(play.ProgressGlow.visible and other.ProgressGlow.visible)
WV:SetTrackerPulsePreview(false)
assert(not play.ProgressGlow.visible)
TalkingHeadRuDB.enabled = false
play.scripts.OnClick(play)
assert(#plays == soundCount)
TalkingHeadRuDB.enabled = true
local canPresent = WV.CanPresentQuest
WV.CanPresentQuest = function() return false end
WV:RefreshTrackerButtons()
assert(not play.visible and not other.visible)
WV.CanPresentQuest = canPresent
WV:RefreshTrackerButtons()
assert(play.visible and other.visible, 'audio availability refresh does not need an EUI redraw')

-- Reminder candidates must exclude clipped custom rows, not just hidden frames.
first.id = 861; render()
C_QuestLog.GetNumQuestLogEntries = function() return 1 end
C_QuestLog.GetInfo = function() return {questID=861} end
local centerY = 650
function play:GetCenter() return 700, centerY end
WV:TestQuestReminder(861)
assert(not frames.WowVoiceQuestReminderPreview, 'rows above the scroll viewport cannot trigger a reminder')
centerY = 450
WV:TestQuestReminder(861)
assert(frames.WowVoiceQuestReminderPreview.visible and play.ProgressGlow.visible)
WV:TestQuestReminder(false)
centerY = 205
WV:TestQuestReminder(861)
assert(not frames.WowVoiceQuestReminderPreview.visible, 'partially clipped buttons are excluded too')
print('PASS: EllesmereUI Custom tracker public API, late loading, single registration, shared playback, recycled rows, parent visibility/scale, font sizing and native layout preservation')

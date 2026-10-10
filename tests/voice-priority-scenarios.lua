event('ADDON_LOADED')
local WV, S = WowVoice, WowVoiceAudioSources
local function order() return table.concat(WV:GetVoicePriority(), ',') end
for _, first in ipairs({'wowvoice','catquest','wayfarer'}) do
    TalkingHeadRuDB.voicePriority = nil
    TalkingHeadRuDB.sharedQuestVoice = first
    event('ADDON_LOADED')
    assert(WV:GetVoicePriority()[1] == first, 'Migration must preserve the former first choice')
end
TalkingHeadRuDB.voicePriority = {'invalid','wayfarer','wayfarer',false,'catquest'}
assert(order() == 'wayfarer,catquest,wowvoice', 'Repair saved duplicates/unknown entries without losing valid ranks')
local before = order()
assert(not WV:SetVoicePriority({'catquest','catquest','wowvoice'}))
assert(not WV:SetVoicePriority({'wayfarer'}))
assert(not WV:SetVoicePriority({'wowvoice',{},'wayfarer'}))
assert(order() == before)
local name = 'Wayfarer_Voices_Shared'
local loaded = {WowVoiceSounds=true,CatQuest_Voices=true,Wayfarer=true,[name]=true}
C_AddOns.IsAddOnLoaded = function(id) return loaded[id] == true end
C_AddOns.GetAddOnMetadata = function() return 'new-version' end
CatQuestVoicePack = {quests={[99997]={d=4}, [179]={d=4}}}
Wayfarer = {Packs={list={{name=name,format=1,q={
    [99997]={a={d=5},p={d=2},c={d=3}}, [179]={a={d=5}},
}}}}}
local permutations = {
    {'wowvoice','catquest','wayfarer'}, {'wowvoice','wayfarer','catquest'},
    {'catquest','wowvoice','wayfarer'}, {'catquest','wayfarer','wowvoice'},
    {'wayfarer','wowvoice','catquest'}, {'wayfarer','catquest','wowvoice'},
}
local paths = {wowvoice='WowVoiceSounds',catquest='CatQuest_Voices',wayfarer=name}
for _, priority in ipairs(permutations) do
    assert(WV:SetVoicePriority(priority))
    assert(WV:SoundPath(179,'a'):find(paths[priority[1]],1,true))
    local expected = priority[1] == 'wowvoice' and priority[2] or priority[1]
    assert(WV:SoundPath(99997,'a'):find(paths[expected],1,true), 'Missing first recording must use the saved second choice')
    assert(WV:SoundPath(99997,'p'):find(name,1,true) and WV:SoundPath(99997,'c'):find(name,1,true))
end
WV:SetVoicePriority({'wowvoice','wayfarer','catquest'})
loaded[name] = false; WV:RefreshAudioSources()
assert(WV:SoundPath(99997,'a'):find('CatQuest_Voices',1,true))
assert(order() == 'wowvoice,wayfarer,catquest')
event('ADDON_LOADED'); assert(order() == 'wowvoice,wayfarer,catquest')
loaded[name] = true; WV:RefreshAudioSources()
assert(WV:SoundPath(99997,'a'):find(name,1,true))
assert(WV:ReplayQuest(99997))
local handle, count = plays[#plays].handle, #plays
WV:SetVoicePriority({'wowvoice','catquest','wayfarer'})
assert(#plays == count and stops[#stops] ~= handle, 'Changing order must not replace current playback')
WV:Silence()
assert(WV:ReplayQuest(99997) and plays[#plays].file:find('CatQuest_Voices',1,true))
WV:Silence()
command('options')
local rows = frames.WowVoiceOptionsPanel.VoicePriorityRows
local options = frames.WowVoiceOptionsPanel
local ghost = options.VoicePriorityGhost
local oldCursor, oldMouse = GetCursorPosition, IsMouseButtonDown
local oldSetCursor, cursorTexture, cursorChanges = SetCursor, nil, 0
SetCursor = function(texture) cursorTexture = texture; cursorChanges = cursorChanges + 1; return true end
local moveCursor = 'Interface/CURSOR/UI-Cursor-Move.crosshair'
local cursorX, cursorY, mouseDown = 0, 0, false
GetCursorPosition = function() return cursorX, cursorY end
IsMouseButtonDown = function() return mouseDown end
-- Scaled, vertically scrolled content: hit testing must use screen coordinates.
options.Content:SetScale(0.8)
options.Content.GetCenter = function() return 280, 460 end
for index, row in ipairs(rows) do
    row.GetCenter = function() return 100 + (index - 1) * 180, 300 end
    row.IsMouseOver = function(self)
        local x, y = self:GetCenter()
        local scale = self:GetEffectiveScale()
        return math.abs(cursorX / scale - x) <= self:GetWidth() / 2
            and math.abs(cursorY / scale - y) <= self:GetHeight() / 2
    end
    assert(not row.Earlier and not row.Later and row.mouseEnabled)
end
local function point(index)
    local x, y = rows[index]:GetCenter()
    local scale = rows[index]:GetEffectiveScale()
    cursorX, cursorY = x * scale, y * scale
end
local grabX, grabY = 0, 0
local function cursorLocked()
    local x, y = ghost:GetCenter()
    local scale = ghost:GetEffectiveScale()
    assert(math.abs(x * scale + grabX - cursorX) < 0.001 and math.abs(y * scale + grabY - cursorY) < 0.001,
        'the original grab point must stay under the cursor at every UI scale')
end
local function start(index, offsetX, offsetY)
    point(index); mouseDown = true
    grabX, grabY = offsetX or 0, offsetY or 0
    cursorX, cursorY = cursorX + grabX, cursorY + grabY
    rows[index].scripts.OnMouseDown(rows[index], 'LeftButton')
    assert(ghost:IsShown() and ghost.scripts.OnUpdate)
    assert(ghost.Label.alpha == rows[index].Label.alpha, 'grabbing an unavailable library must preserve its dimmed label')
    assert(cursorTexture == moveCursor, 'grab must show the OPie move cursor')
    local gx, gy = ghost:GetCenter()
    local rx, ry = rows[index]:GetCenter()
    assert(math.abs(gx-rx) < 0.001 and math.abs(gy-ry) < 0.001, 'pressing must never move the card')
    cursorLocked()
end
local function drop(from, target)
    local saved = order()
    start(from); point(target)
    ghost.scripts.OnUpdate()
    cursorLocked()
    assert(order() == saved, 'Drag preview must not persist intermediate ranks')
    mouseDown = false
    rows[from].scripts.OnDragStop(rows[from])
    assert(not ghost:IsShown() and not ghost.scripts.OnUpdate)
    assert(cursorTexture == moveCursor, 'drop over a card must keep its hover cursor')
    assert(rows[target].backdropBorderColor[1] == 1 and rows[target].backdropBorderColor[2] == 0.82,
        'drop must preserve the target card hover border after refreshing priorities')
    rows[from].scripts.OnMouseUp(rows[from], 'LeftButton')
    assert(cursorTexture == moveCursor, 'a duplicate release must not reset the hover cursor')
end
assert(rows[1].sourceID == 'wowvoice')
local originalOrder = order()
rows[1].scripts.OnEnter(rows[1]); assert(cursorTexture == moveCursor)
rows[1].scripts.OnLeave(rows[1]); assert(cursorTexture == nil)
local changes = cursorChanges
options.CancelVoicePriorityDrag()
assert(cursorChanges == changes, 'idle cleanup must not reset another UI cursor')
rows[1].scripts.OnEnter(rows[1])
rows[1].scripts.OnHide(rows[1]); assert(cursorTexture == nil, 'hiding a hovered card must restore the cursor')
rows[1].scripts.OnMouseDown(rows[1], 'RightButton')
assert(not ghost:IsShown(), 'right-click must not grab a card')
for _, scale in ipairs({0.8, 1.25}) do
    options.Content:SetScale(scale)
    start(1, 55 * scale, -10 * scale)
    rows[1].scripts.OnLeave(rows[1])
    assert(cursorTexture == moveCursor, 'dragging outside the original card keeps the move cursor')
    ghost.scripts.OnUpdate()
    cursorLocked()
    cursorX, cursorY = cursorX + 20, cursorY + 40
    rows[1].scripts.OnDragStart(rows[1])
    ghost.scripts.OnUpdate()
    cursorLocked()
    assert(ghost.Label:GetText() == rows[1].Label:GetText() and order() == originalOrder)
    options.CancelVoicePriorityDrag(); mouseDown = false
    assert(not ghost:IsShown())
    assert(cursorTexture == nil, 'cancelling must restore the cursor')
end
options.Content:SetScale(0.8)
start(1)
mouseDown = false
rows[1].scripts.OnMouseUp(rows[1], 'LeftButton')
assert(order() == originalOrder and not ghost:IsShown(), 'click without movement must keep the order')
assert(cursorTexture == moveCursor, 'a single click must preserve the cursor without another OnEnter')
assert(rows[1].backdropBorderColor[1] == 1 and rows[1].backdropBorderColor[2] == 0.82,
    'a single click must preserve the highlighted border')
rows[1].scripts.OnDragStop(rows[1])
assert(cursorTexture == moveCursor, 'a second finish event must preserve the hover cursor')
rows[1].scripts.OnLeave(rows[1]); assert(cursorTexture == nil)
assert(rows[1].backdropBorderColor[1] == 0.4, 'leaving the card restores its normal border')
drop(3, 2)
assert(order() == 'wowvoice,wayfarer,catquest' and rows[2].sourceID == 'wayfarer')
drop(2, 1)
assert(order() == 'wayfarer,wowvoice,catquest' and rows[1].Label:GetText() == '1. Wayfarer')
drop(1, 2)
assert(order() == 'wowvoice,wayfarer,catquest')
loaded[name] = false; WV:RefreshAudioSources()
assert(not rows[2].available and rows[2].mouseEnabled, 'Unavailable libraries can be ranked for later use')
drop(2, 1)
assert(order() == 'wayfarer,wowvoice,catquest' and WV:GetSharedQuestVoice() == 'wowvoice')
drop(1, 3)
assert(order() == 'catquest,wowvoice,wayfarer', 'Dropping first on third swaps only those cards; the middle stays in place')
local unchanged = order()
drop(2, 2); assert(order() == unchanged)
start(1); cursorY = 0; mouseDown = false; rows[1].scripts.OnDragStop(rows[1])
assert(order() == unchanged and not ghost:IsShown(), 'Dropping outside cancels')
assert(cursorTexture == nil, 'release outside the cards must restore the default cursor')
start(1); point(3); rows[1].scripts.OnHide(rows[1]); mouseDown = false
rows[1].scripts.OnDragStop(rows[1])
assert(order() == unchanged and not ghost:IsShown(), 'Closing the panel must cancel the drag')
start(1); point(3); WV:RefreshAudioSources(); mouseDown = false
assert(order() == unchanged and not ghost:IsShown(), 'External refresh cancels stale drag state')
start(3); point(1); mouseDown = false; ghost.scripts.OnUpdate()
assert(order() == 'wayfarer,wowvoice,catquest', 'Release outside the source must still finish the drag')
assert(cursorTexture == moveCursor, 'missing mouse-up recovery over a card must preserve its hover cursor')
rows[1].scripts.OnEnter(rows[1]); assert(cursorTexture == moveCursor)
options:Hide(); assert(cursorTexture == nil, 'closing settings without a drag must restore the cursor')
SetCursor = oldSetCursor
GetCursorPosition, IsMouseButtonDown = oldCursor, oldMouse
local saved = order()
assert(WowVoiceComparison.Play(179,'catquest'))
assert(order() == saved, 'Catalogue preview must not change any rank')
WV:Silence()
print('PASS: full source priority, six permutations, sparse coverage, migration, reload, immediate grab without jumping, OPie move cursor lifecycle, swaps, cancellation, missing mouse-up and playback isolation')

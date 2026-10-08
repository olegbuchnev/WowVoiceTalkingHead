local WV = WowVoice
local head, anchor = frames.TalkingHeadRu, frames.TalkingHeadRuAnchor
local panel = frames.WowVoiceOptionsPanel
local oldEnum = Enum
Enum = { FontStringScaleAnimationMode = { Vertex = 1 } }
UIParent.scale = 0.75
frames.WowVoiceHeadScaleEvents.scripts.OnEvent()
panel:Show()
local function near(a, b, message)
    assert(math.abs(a - b) < 0.00001, (message or 'coordinate changed')..': '..a..' / '..b)
end
-- Independent screen-space geometry: nine grid coordinates, from bottom to top.
local points = {
    {'BOTTOMLEFT', 0, 0}, {'BOTTOM', 0.5, 0}, {'BOTTOMRIGHT', 1, 0},
    {'LEFT', 0, 0.5}, {'CENTER', 0.5, 0.5}, {'RIGHT', 1, 0.5},
    {'TOPLEFT', 0, 1}, {'TOP', 0.5, 1}, {'TOPRIGHT', 1, 1},
}
local function visibleOffset(p)
    local scale = anchor:GetWidth()/head:GetWidth()
    return (p[2]-0.5)*(anchor:GetWidth()-28*scale)+scale,
        (p[3]-0.5)*(anchor:GetHeight()-28*scale)-scale
end
local function location(p)
    local x, y = anchor:GetCenter()
    local ax, ay = visibleOffset(p)
    return x + ax, y + ay
end
local function selected(point)
    local count = 0
    for key, dot in pairs(panel.AnchorPoints) do
        if dot:GetChecked() then count = count + 1; assert(key == point) end
        assert(dot:GetWidth() >= 32 and dot:GetHeight() >= 32)
    end
    assert(count == 1, 'the anchor selector must always have exactly one choice')
end
for _, p in ipairs(points) do
    panel:Show()
    WV:ResetHeadSettings()
    WV:ApplyHeadSettings({width=570,height=155,scale=1,x=37,y=51})
    local before = WV:GetHeadSettings()
    local played, stopped = #plays, #stops
    panel.AnchorPoints[p[1]].scripts.OnClick()
    local after = WV:GetHeadSettings()
    near(after.x, before.x, 'selecting a point must not move the panel')
    near(after.y, before.y)
    local shownX, shownY = WV:GetHeadAnchorPosition()
    local ax, ay = visibleOffset(p)
    near(shownX, before.x + ax, 'all points must share the screen-center origin')
    near(shownY, before.y + ay)
    assert(head:IsShown() and head.mouseEnabled, 'selecting an anchor opens an idle preview')
    assert(#plays == played and #stops == stopped)
    selected(p[1])
    -- Clicking the selected dot cannot switch it off.
    panel.AnchorPoints[p[1]]:SetChecked(false)
    panel.AnchorPoints[p[1]].scripts.OnClick()
    selected(p[1])
    local px, py = location(p)
    for _, scale in ipairs({1.25, 0.73, 1}) do
        assert(WV:SetHeadScale(scale))
        local x, y = location(p)
        near(x, px, 'numeric scale must hold the chosen point'); near(y, py)
    end
    local saved = TalkingHeadRuDB.headPosition
    local camera = head.Model.cameraRefreshes
    panel.ScaleSlider.scripts.OnMouseDown(panel.ScaleSlider, 'LeftButton')
    local group = head.TextScaleLayer.Group
    local geometry = {}
    for _, entry in ipairs({{anchor, 'SetSize'}, {anchor, 'ClearAllPoints'},
        {anchor, 'SetPoint'}, {head, 'SetScale'}}) do
        local object, method = entry[1], entry[2]
        local original = object[method]
        geometry[#geometry + 1] = {object, method, original}
        object[method] = function(self, ...)
            assert(not group.playing, 'finish parent geometry before starting the text transform: '..p[1]..' '..method)
            return original(self, ...)
        end
    end
    local play = group.Play
    group.Play = function(self, ...)
        local x, y = location(p)
        near(x, px, 'text transform must start at the final anchored position'); near(y, py)
        return play(self, ...)
    end
    for _, percent in ipairs({112.3, 88.4, 123.7}) do
        panel.ScaleSlider:SetValue(percent)
        head.scripts.OnUpdate(head)
        local x, y = location(p)
        near(x, px, 'live scaling must hold the chosen point'); near(y, py)
        assert(TalkingHeadRuDB.headPosition == saved, 'dragging must not rewrite the saved position')
        assert(head.Model.cameraRefreshes == camera, 'anchor selection must not reintroduce camera flicker')
    end
    group.Play = play
    for _, entry in ipairs(geometry) do entry[1][entry[2]] = entry[3] end
    panel.ScaleSlider.scripts.OnMouseUp(panel.ScaleSlider, 'LeftButton')
    local x, y = location(p)
    near(x, px, 'rounding on release must hold the chosen point'); near(y, py)
    assert(WV:GetHeadScale() == 1.24)
    panel.ScaleInput:SetText('83')
    panel.ScaleInput.scripts.OnEnterPressed(panel.ScaleInput)
    x, y = location(p); near(x, px); near(y, py)
    local settings, stored = WV:GetHeadSettings(), TalkingHeadRuDB.headPosition
    panel.ScaleSlider.scripts.OnMouseDown(panel.ScaleSlider, 'LeftButton')
    panel.ScaleSlider:SetValue(143.7)
    head.scripts.OnUpdate(head)
    panel:Hide()
    after = WV:GetHeadSettings()
    near(after.x, settings.x, 'closing options must restore the pre-drag position')
    near(after.y, settings.y); near(after.scale, settings.scale)
    assert(TalkingHeadRuDB.headAnchor == p[1])
    assert(TalkingHeadRuDB.headPosition[1] == stored[1] and TalkingHeadRuDB.headPosition[2] == stored[2])
    near(TalkingHeadRuDB.headPosition[3], stored[3], 'cancel must restore saved offsets')
    near(TalkingHeadRuDB.headPosition[4], stored[4])
    -- A newly shown panel restores the same anchor and screen-relative offsets.
    panel:Show()
    WV:EnsureHeadPreview()
    selected(p[1])
    x, y = location(p); near(x, px); near(y, py)
    assert(stored[1] == p[1] and stored[2] == p[1])
    UIParent:SetSize(2200, 1300)
    frames.WowVoiceHeadScaleEvents.scripts.OnEvent()
    x, y = location(p)
    ax, ay = visibleOffset(p)
    near(x, 2200 * p[2] + stored[3] + ax - (p[2]-.5)*anchor:GetWidth(), 'legacy saved geometry stays unchanged')
    near(y, 1300 * p[3] + stored[4] + ay - (p[3]-.5)*anchor:GetHeight())
    UIParent:SetSize(1920, 1080)
    frames.WowVoiceHeadScaleEvents.scripts.OnEvent()
    -- Moving in test mode must retain the choice and persist the new offsets.
    local storedBeforeMove = TalkingHeadRuDB.headPosition
    panel.PositionX:SetFocus(); panel.PositionX:SetText('999')
    WV:SetWindowsUnlocked(true)
    head.scripts.OnDragStart()
    assert(head.draggingPosition and not panel.editingPosition and not panel.PositionX.focus)
    for _, center in ipairs({{45, -60}, {-110, 93}}) do
        anchor:ClearAllPoints(); anchor:SetPoint('CENTER', UIParent, 'CENTER', center[1], center[2])
        head.scripts.OnUpdate(head)
        ax, ay = visibleOffset(p)
        assert(math.abs(tonumber(panel.PositionX:GetText()) - (center[1] + ax)) <= 0.005001,
            'X must follow the selected point before mouse release')
        assert(math.abs(tonumber(panel.PositionY:GetText()) - (center[2] + ay)) <= 0.005001,
            'Y must follow the selected point before mouse release')
        assert(TalkingHeadRuDB.headPosition == storedBeforeMove, 'live display must not save position every frame')
    end
    anchor:ClearAllPoints(); anchor:SetPoint('CENTER', UIParent, 'CENTER', -82, 63)
    head.scripts.OnDragStop()
    assert(not head.draggingPosition)
    after = WV:GetHeadSettings()
    near(after.x, -82); near(after.y, 63)
    assert(TalkingHeadRuDB.headPosition[1] == p[1] and TalkingHeadRuDB.headAnchor == p[1])
    panel.Buttons.center.scripts.OnClick()
    after = WV:GetHeadSettings(); near(after.x, -head:GetScale()); near(after.y, 63)
    local visibleCenterX = location({'CENTER', 0.5, 0.5})
    near(visibleCenterX, UIParent:GetWidth()/2, 'center button must center the visible panel')
    if p[2] == 0.5 then near(tonumber(panel.PositionX:GetText()), 0) end
    selected(p[1])
    -- Set up the independent cursor-drag fixture at the native frame center.
    assert(WV:ApplyHeadSettings({width=after.width,height=after.height,scale=after.scale,x=0,y=63}))
    -- The native frame rectangle may lag while StartMoving is active. Keep it
    -- unchanged here and require live coordinates from physical cursor pixels.
    local oldCursor = GetCursorPosition
    local cursorX, cursorY = 700, 500
    GetCursorPosition = function() return cursorX, cursorY end
    WV:SetWindowsUnlocked(true)
    head.scripts.OnDragStart()
    cursorX, cursorY = 737.5, 477.5 -- +50, -30 UI units at UI scale 0.75.
    head.scripts.OnUpdate(head)
    ax, ay = visibleOffset(p)
    assert(math.abs(tonumber(panel.PositionX:GetText()) - (50 + ax)) <= 0.005001)
    assert(math.abs(tonumber(panel.PositionY:GetText()) - (33 + ay)) <= 0.005001)
    near(WV:GetHeadSettings().x, 0, 'fixture must keep native geometry stale during movement')
    cursorX, cursorY = 100000, -100000
    head.scripts.OnUpdate(head)
    local clampedX = (UIParent:GetWidth()-anchor:GetWidth())/2 + 13*head:GetScale() + ax
    local clampedY = -(UIParent:GetHeight()-anchor:GetHeight())/2 + ay
    assert(math.abs(tonumber(panel.PositionX:GetText()) - clampedX) <= 0.005001)
    assert(math.abs(tonumber(panel.PositionY:GetText()) - clampedY) <= 0.005001)
    cursorX, cursorY = 737.5, 477.5
    anchor:ClearAllPoints(); anchor:SetPoint('CENTER', UIParent, 'CENTER', 50, 33)
    head.scripts.OnDragStop()
    after = WV:GetHeadSettings(); near(after.x, 50); near(after.y, 33)
    GetCursorPosition = oldCursor
    -- Signed fractional coordinates are relative to the same screen center,
    -- independent of UI scale. Switching between X and Y must retain both drafts.
    local wantedX = p[2] == 0 and 36.25 or p[2] == 1 and -36.25 or 23.5
    local wantedY = p[3] == 0 and 62.75 or p[3] == 1 and -62.75 or -41.25
    panel.PositionX:SetFocus()
    panel.PositionX:SetText(tostring(wantedX):gsub('%.', ','))
    panel.PositionX.scripts.OnTabPressed(panel.PositionX)
    assert(panel.PositionY.focus and not panel.PositionX.focus)
    panel.PositionY:SetText(tostring(wantedY))
    WV:RefreshHeadOptions()
    assert(panel.PositionX:GetText():find(',', 1, true), 'unrelated refresh must preserve coordinate drafts')
    panel.PositionY.scripts.OnEnterPressed(panel.PositionY)
    local offsetX, offsetY = WV:GetHeadAnchorPosition()
    near(offsetX, wantedX); near(offsetY, wantedY)
    x, y = location(p)
    near(x, UIParent:GetWidth()/2 + wantedX, 'X must use screen center for every selected point')
    near(y, UIParent:GetHeight()/2 + wantedY)
    assert(not panel.PositionX.focus and not panel.PositionY.focus and not panel.editingPosition)
    WV:SetHeadScale(0.73)
    near(tonumber(panel.PositionX:GetText()), wantedX)
    near(tonumber(panel.PositionY:GetText()), wantedY)
    local saved = TalkingHeadRuDB.headPosition
    panel.PositionX:SetFocus(); panel.PositionX:SetText('-')
    panel.Buttons.applyPosition.scripts.OnClick()
    assert(TalkingHeadRuDB.headPosition == saved and panel.PositionX:GetText() == '-')
    panel.PositionX:SetText('999')
    panel.PositionX.scripts.OnEscapePressed()
    near(tonumber(panel.PositionX:GetText()), wantedX)
    assert(TalkingHeadRuDB.headPosition == saved)
    -- A valid X and invalid Y must not partially commit.
    panel.PositionX:SetFocus(); panel.PositionX:SetText('12')
    panel.PositionY:SetText('wrong')
    panel.Buttons.applyPosition.scripts.OnClick()
    assert(TalkingHeadRuDB.headPosition == saved)
    panel:Hide(); panel:Show()
    near(tonumber(panel.PositionX:GetText()), wantedX)
    near(tonumber(panel.PositionY:GetText()), wantedY)
    -- Changing the anchor recalculates displayed offsets without moving the panel.
    before = WV:GetHeadSettings()
    panel.AnchorPoints.CENTER.scripts.OnClick()
    after = WV:GetHeadSettings(); near(after.x, before.x); near(after.y, before.y)
    local centerX, centerY = visibleOffset({'CENTER', 0.5, 0.5})
    assert(math.abs(tonumber(panel.PositionX:GetText()) - after.x - centerX) <= 0.005001)
    assert(math.abs(tonumber(panel.PositionY:GetText()) - after.y - centerY) <= 0.005001)
    -- (0, 0) puts the chosen point at screen center, even for an edge or corner.
    WV:SetHeadAnchor(p[1])
    assert(WV:SetHeadAnchorPosition(0, 0))
    x, y = location(p)
    near(x, UIParent:GetWidth()/2); near(y, UIParent:GetHeight()/2)
    WV:SetHeadScale(1.1)
    x, y = location(p)
    near(x, UIParent:GetWidth()/2); near(y, UIParent:GetHeight()/2)
end
-- Growth near the screen edge must stay visible; reversing a drag uses its
-- original pivot rather than accumulating the clamped position at each step.
WV:ApplyHeadSettings({width=570,height=155,scale=0.5,x=10000,y=10000})
WV:SetHeadAnchor('BOTTOMLEFT')
local edge = WV:GetHeadSettings()
WV:BeginHeadScalePreview()
WV:SetHeadScale(1.5, true); head.scripts.OnUpdate(head)
local bounds = WV:GetHeadSettings()
assert(bounds.x + anchor:GetWidth()/2 - 13*bounds.scale <= UIParent:GetWidth()/2 + 0.00001)
assert(bounds.x - anchor:GetWidth()/2 + 15*bounds.scale >= -UIParent:GetWidth()/2 - 0.00001)
assert(bounds.y + anchor:GetHeight()/2 - 15*bounds.scale <= UIParent:GetHeight()/2 + 0.00001)
assert(bounds.y - anchor:GetHeight()/2 >= -UIParent:GetHeight()/2 - 0.00001)
WV:SetHeadScale(0.5, true); head.scripts.OnUpdate(head)
local back = WV:GetHeadSettings(); near(back.x, edge.x); near(back.y, edge.y)
WV:EndHeadScalePreview(true)
local savedPoint, savedPosition = TalkingHeadRuDB.headAnchor, TalkingHeadRuDB.headPosition
assert(not WV:SetHeadAnchor('INVALID'))
assert(TalkingHeadRuDB.headAnchor == savedPoint and TalkingHeadRuDB.headPosition == savedPosition)
for _, bad in ipairs({math.huge, -math.huge, 'wrong'}) do
    assert(not WV:SetHeadAnchorPosition(bad, 1))
    assert(not WV:SetHeadAnchorPosition(1, bad))
    assert(TalkingHeadRuDB.headPosition == savedPosition)
end
assert(not WV:SetHeadAnchorPosition(0/0, 1))
-- Choosing a point during real playback leaves sound/model identity untouched.
WV:SetWindowsUnlocked(false)
WV:HideHeadPreview()
assert(WV:ReplayQuest(179))
local played, stopped, model = #plays, #stops, head.Model:GetDisplayInfo()
panel.AnchorPoints.TOPRIGHT.scripts.OnClick()
assert(#plays == played and #stops == stopped and head.Model:GetDisplayInfo() == model)
panel.PositionX:SetText('-50.5'); panel.PositionY:SetText('-60.25')
panel.Buttons.applyPosition.scripts.OnClick()
assert(#plays == played and #stops == stopped and head.Model:GetDisplayInfo() == model)
head.scripts.OnDragStart()
assert(not anchor.moving, 'choosing a point must not turn real playback into a movable test')
panel.Buttons.reset.scripts.OnClick()
assert(TalkingHeadRuDB.headPosition == nil and TalkingHeadRuDB.headAnchor == nil)
assert(WV:GetHeadScale() == 0.5 and WV:GetHeadAnchor() == 'BOTTOM')
selected('BOTTOM')
near(tonumber(panel.PositionX:GetText()), head:GetScale())
panel:Hide()
assert(head:IsShown(), 'closing options must leave real playback running')
WV:Silence()
panel:Show()
panel.PositionX:SetText('0'); panel.PositionY:SetText('120,5')
panel.Buttons.applyPosition.scripts.OnClick()
assert(head:IsShown() and TalkingHeadRuDB.headAnchor == 'BOTTOM')
local offsetX, offsetY = WV:GetHeadAnchorPosition()
near(offsetX, 0); near(offsetY, 120.5)
panel.PositionX:SetText('99999'); panel.PositionY:SetText('-99999')
panel.Buttons.applyPosition.scripts.OnClick()
local clamped = WV:GetHeadSettings()
assert(clamped.x + anchor:GetWidth()/2 - 13*clamped.scale <= UIParent:GetWidth()/2)
assert(clamped.x - anchor:GetWidth()/2 + 15*clamped.scale >= -UIParent:GetWidth()/2)
assert(math.abs(clamped.y) + anchor:GetHeight()/2 <= UIParent:GetHeight()/2)
offsetX, offsetY = WV:GetHeadAnchorPosition()
near(tonumber(panel.PositionX:GetText()), offsetX)
near(tonumber(panel.PositionY:GetText()), offsetY)
panel:Hide()
Enum = oldEnum
-- Dragging and numeric positioning use the visible top edge at every scale.
for _, scale in ipairs({0.5, 1, 1.5}) do
    WV:ApplyHeadSettings({width=570,height=155,scale=scale,x=0,y=100000})
    local atTop = WV:GetHeadSettings()
    local borderTop = -head.EditBorder.points[1][5] * scale
    near(atTop.y + anchor:GetHeight()/2 - borderTop, UIParent:GetHeight()/2,
        'the edit border must reach the screen top')
    near(anchor.clampRectInsets[3], -borderTop, 'native dragging must use the same top edge')
    assert(anchor.clampRectInsets[4] == 0, 'the bottom bound must keep the progress bar on screen')
    WV:EnsureHeadPreview()
    WV:SetWindowsUnlocked(true)
    head.scripts.OnDragStart()
    head.scripts.OnDragStop()
    near(WV:GetHeadSettings().y, atTop.y, 'releasing the mouse must not pull the head down')
    WV:HideHeadPreview()
    WV:EnsureHeadPreview()
    near(WV:GetHeadSettings().y, atTop.y, 'restoring the head must preserve the edge position')
    for _, side in ipairs({-1, 1}) do
        WV:ApplyHeadSettings({width=570,height=155,scale=scale,x=side*100000,y=atTop.y})
        local atSide = WV:GetHeadSettings()
        local inset = side == -1 and head.EditBorder.points[1][4] or -head.EditBorder.points[2][4]
        near(atSide.x + side*(anchor:GetWidth()/2-inset*scale), side*UIParent:GetWidth()/2,
            'the yellow side border must reach the screen edge')
        near(anchor.clampRectInsets[side == -1 and 1 or 2], -side*inset*scale,
            'native dragging must use the same side edge')
        WV:SetWindowsUnlocked(true)
    head.scripts.OnDragStart()
        head.scripts.OnDragStop()
        near(WV:GetHeadSettings().x, atSide.x, 'release must retain the side edge position')
        WV:HideHeadPreview()
        WV:EnsureHeadPreview()
        near(WV:GetHeadSettings().x, atSide.x, 'restoring must retain the side edge position')
    end
end
UIParent.scale = 1
frames.WowVoiceHeadScaleEvents.scripts.OnEvent()
near(head.EditBorder.backdrop.edgeSize*head.EditBorder:GetEffectiveScale(), 1,
    'changing UI scale must retain a one-pixel edit outline')
WV:ResetHeadSettings()
WV:SetWindowsUnlocked(false)
print('PASS: nine anchor points, exclusive selection, fixed pivots, fractional drag/release, numeric input, cancellation, screen resize, movement, bounds, reset and uninterrupted playback')
print('PASS: common screen-center origin for all anchor coordinates, zero placement, decimal commas, atomic entry, Tab, Escape, drafts, validation, clamped readback and preview')
print('PASS: all nine pivots finish parent geometry before starting the vertex text transform')
print('PASS: mouse movement updates selected-point coordinates live, replaces numeric drafts and saves on release')
print('PASS: cursor-driven coordinate readout with stale native geometry, UI scaling, all pivots and screen clamps')

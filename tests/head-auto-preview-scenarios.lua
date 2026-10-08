local WV = WowVoice
local panel, head = frames.WowVoiceOptionsPanel, frames.TalkingHeadRu
local slider, input = panel.ScaleSlider, panel.ScaleInput
local function toggleFrames()
    panel.LockFrames:SetChecked(WV:IsWindowsUnlocked())
    panel.LockFrames.scripts.OnClick(panel.LockFrames)
end
local oldEnum = Enum
Enum = { FontStringScaleAnimationMode = { Vertex = 1 } }
panel:Show()
WV:Silence()
WV:ResetHeadSettings()
local function advance(seconds)
    now = now + seconds
    if head:IsShown() then head.scripts.OnUpdate(head) end
end
local function scale(value)
    input:SetText(tostring(value))
    input.scripts.OnEnterPressed(input)
end
local function position(x, y)
    panel.PositionX:SetText(tostring(x)); panel.PositionY:SetText(tostring(y))
    panel.Buttons.applyPosition.scripts.OnClick()
end
local function opaque()
    assert(head:IsShown() and head.visualAlpha == 1, 'preview must stay fully visible during the hold')
end
local function fading()
    assert(head:IsShown() and head.visualAlpha > 0 and head.visualAlpha < 1, 'use the normal gradual fade')
    assert(head.Name.alpha == head.visualAlpha and head.TextScroll.alpha == head.visualAlpha)
end
local played, stopped = #plays, #stops
-- An automatic slider preview starts fading on release, without a two-second hold.
slider.scripts.OnMouseDown(slider, 'LeftButton')
slider:SetValue(112.3); head.scripts.OnUpdate(head)
head.scripts.OnDragStart()
assert(not head.draggingPosition and not frames.TalkingHeadRuAnchor.moving,
    'a scale preview cannot move a frame while the common lock is checked')
advance(4); opaque()
slider.scripts.OnMouseUp(slider, 'LeftButton')
advance(0.5); fading()
advance(0.5); assert(not head:IsShown())
assert(TalkingHeadRuDB.headScale == 1.12 and not head.Model:GetPaused())
-- Numeric scale and X/Y both hold for two seconds, then fade for one second.
for _, apply in ipairs({function() scale(95) end, function() position(12.5, -24.25) end}) do
    apply(); opaque()
    advance(1.9); opaque()
    advance(0.1); opaque()
    advance(0.5); fading()
    advance(0.5); assert(not head:IsShown())
end
-- Repeated application, even of the same value, renews the two-second hold.
scale(105); advance(1.5); position(-15, 20)
advance(1.5); opaque()
position(-15, 20); advance(1.9); opaque()
advance(0.1); advance(0.5); fading()
-- A new drag revives that same model and holds it as long as the mouse is down.
local reloads, setUnit = 0, head.Model.SetUnit
head.Model.SetUnit = function(self, ...)
    reloads = reloads + 1
    return setUnit(self, ...)
end
slider.scripts.OnMouseDown(slider, 'LeftButton')
slider:SetValue(118.4); head.scripts.OnUpdate(head)
advance(4); opaque()
assert(reloads == 0, 'reviving an automatic preview must not reload its portrait')
slider.scripts.OnMouseUp(slider, 'LeftButton')
advance(0.5); fading()
-- Pressing Test during the fade pins the panel without reloading it.
toggleFrames()
advance(4); opaque()
assert(reloads == 0)
head.Model.SetUnit = setUnit
scale(86); position(0, 0); advance(4); opaque()
slider.scripts.OnMouseDown(slider, 'LeftButton')
slider:SetValue(102); head.scripts.OnUpdate(head)
slider.scripts.OnMouseUp(slider, 'LeftButton')
advance(4); opaque()
toggleFrames(); assert(not head:IsShown())
-- Explicit Test opened from idle also remains visible after all setting changes.
toggleFrames()
scale(92); position(10, 20); advance(4); opaque()
toggleFrames(); assert(not head:IsShown())
-- Invalid input cannot create a preview, and page close cancels pending expiry.
scale(999); assert(not head:IsShown())
position('wrong', 5); assert(not head:IsShown())
scale(96); panel:Hide(); advance(4); assert(not head:IsShown())
panel:Show()
assert(#plays == played and #stops == stopped, 'silent preview timing must never play audio')
-- A new real briefing must not inherit the previous preview's deadline.
scale(97); advance(1)
assert(WV:ReplayQuest(179))
local text, playCount, stopCount = head.Body:GetText(), #plays, #stops
advance(4); opaque()
scale(98); position(-20, 30); advance(4); opaque()
slider.scripts.OnMouseDown(slider, 'LeftButton')
slider:SetValue(111); head.scripts.OnUpdate(head)
slider.scripts.OnMouseUp(slider, 'LeftButton')
advance(4); opaque()
assert(head.Body:GetText() == text and #plays == playCount and #stops == stopCount)
panel:Hide(); assert(head:IsShown())
WV:Silence()
Enum = oldEnum
WV:ResetHeadSettings()
print('PASS: automatic drag release fades immediately; numeric scale/coordinates hold two seconds then fade; renewal, revival, explicit Test, invalid input, cleanup and real playback isolation')

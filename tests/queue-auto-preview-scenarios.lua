local WV, Q, Lab = WowVoice, WowVoice.questQueue, WowVoiceQueueLab
Lab:Reset()
WV:OpenOptions()
local panel, head, player = frames.WowVoiceOptionsPanel, WowVoiceTalkingHead, frames.WowVoiceQuestQueuePlayer
local function advance(seconds)
    now = now + seconds
    if head:IsShown() then head.scripts.OnUpdate(head) end
    if player:IsShown() then player.scripts.OnUpdate(player, seconds) end
end
local function scale(value)
    panel.QueueScaleInput:SetText(tostring(value))
    panel.QueueScaleInput.scripts.OnEnterPressed(panel.QueueScaleInput)
end
local function locked()
    assert(panel.LockFrames:GetChecked() and not WV:IsWindowsUnlocked() and not player.editing)
    assert(not player.EditOverlay:IsShown() and not head.EditBorder:IsShown())
    player.EditOverlay.scripts.OnDragStart()
    head.scripts.OnDragStart()
    assert(not player.dragging and not head.draggingPosition)
end
local function opaque()
    assert(player:IsShown() and player.alpha == 1 and not head:IsShown())
end
local function fading()
    assert(player:IsShown() and player.alpha > 0 and player.alpha < 1)
    assert(not head:IsShown())
end
local playCount, stopCount = #plays, #stops
scale(107); opaque(); locked()
assert(Q:Count() == 0 and player.preview and player:GetHeight() == WV:GetQuestQueueHeight())
advance(1.9); opaque()
advance(0.1); advance(0.5); fading()
scale(107); opaque(); locked() -- Same value revives the queue without unlocking.
advance(2); advance(0.5); fading()
advance(0.5)
assert(not player:IsShown() and not player.preview and not head:IsShown())
-- Slider stays visible while held, then holds two seconds before fading.
local slider = panel.QueueScale
slider.scripts.OnMouseDown(slider, 'LeftButton')
slider:SetValue(112)
advance(4); opaque(); locked()
slider.scripts.OnMouseUp(slider, 'LeftButton')
advance(1.9); opaque()
advance(0.1); advance(0.5); fading()
advance(0.5); assert(not player:IsShown() and not head:IsShown())
-- The head scale preview never opens the queue.
panel.ScaleInput:SetText('105')
panel.ScaleInput.scripts.OnEnterPressed(panel.ScaleInput)
assert(head:IsShown() and not player:IsShown())
advance(2); advance(1)
-- Queue changes leave a separately running head preview's deadline alone.
panel.ScaleInput:SetText('106')
panel.ScaleInput.scripts.OnEnterPressed(panel.ScaleInput)
advance(1); scale(108)
advance(1); advance(1)
assert(not head:IsShown() and player:IsShown() and player.alpha == 1)
advance(1); assert(not player:IsShown())
scale(999); assert(not player:IsShown() and not head:IsShown())
assert(#plays == playCount and #stops == stopCount)
-- An explicit unlock pins the same sample; scale never relocks it.
scale(100)
panel.LockFrames:SetChecked(false); panel.LockFrames.scripts.OnClick(panel.LockFrames)
scale(106); advance(4)
assert(player:IsShown() and head:IsShown() and player.editing and not player.autoPreview)
panel:Hide()
assert(not player:IsShown() and not player.preview and not head:IsShown())
-- Real audio and the gameplay queue survive automatic expiry and page close.
local pool = Lab:Pool()
Lab:Accept(pool[1].id); Lab:Accept(pool[2].id)
WV:OpenOptions()
local current, count, sounds, stopsBefore = Q.current, Q:Count(), #plays, #stops
scale(110); locked()
advance(2); advance(1)
assert(player:IsShown() and not player.preview and head:IsShown())
assert(Q.current == current and Q:Count() == count and #plays == sounds and #stops == stopsBefore)
scale(109); panel:Hide()
assert(not player.autoPreview and not player.preview and player:IsShown() and head:IsShown())
assert(Q.current == current and Q:Count() == count and #plays == sounds and #stops == stopsBefore)
-- A press on a sample cannot turn into real playback when the preview expires.
WV:OpenOptions()
scale(108)
local sampleRow
for _, frame in ipairs(allFrames) do
    if frame.Title and frame.record and frame.record.context.queueOwner == 'preview'
        and frame.record ~= player.preview.current then sampleRow = frame; break end
end
assert(sampleRow)
local inputs = {sampleRow, sampleRow.Play, sampleRow.Next, sampleRow.Remove}
for _, control in ipairs(inputs) do
    assert(not control:IsEnabled())
    control.scripts.OnMouseDown(control)
end
advance(2); advance(1)
for _, control in ipairs(inputs) do control.scripts.OnClick(control) end
assert(Q.current == current and Q:Count() == count and #plays == sounds and #stops == stopsBefore,
    'releasing a sample press after expiry must neither play nor modify the real queue')
-- Once restored, a new click on an actual quest still works normally.
local waitingRow
for _, frame in ipairs(allFrames) do
    if frame.Title and frame.record == Q:Waiting() then waitingRow = frame; break end
end
assert(waitingRow and waitingRow:IsEnabled())
waitingRow.scripts.OnMouseDown(waitingRow); waitingRow.scripts.OnClick(waitingRow)
assert(Q.current ~= current and #plays == sounds + 1)
panel:Hide()
Lab:Reset()
print('PASS: queue geometry previews stay locked, show only the queue, hold and fade, renew, pin explicitly, and preserve real playback')

local WV, Q, Lab = WowVoice, WowVoice.questQueue, WowVoiceQueueLab
Lab:Reset()
WV:OpenOptions()
local panel, pool = frames.WowVoiceOptionsPanel, Lab:Pool()
local function toggleFrames()
    panel.LockFrames:SetChecked(WV:IsWindowsUnlocked())
    panel.LockFrames.scripts.OnClick(panel.LockFrames)
end
assert(panel.LockFrames:GetChecked() and not panel.Buttons.test and not panel.Buttons.queueMove)
assert(panel.QueueHeight and panel.QueueDescriptionsOnly)
assert(panel.QueueHeight.minValue == 280 and panel.QueueHeight.maxValue == 600)
assert(panel.QueueScale.minValue == 80 and panel.QueueScale.maxValue == 120)
assert(WV:GetQuestQueueHeight() == 280 and not panel.QueueDescriptionsOnly:GetChecked())
WV:ToggleHeadPreview(true)
assert(WowVoiceTalkingHead.EditBorder:IsShown() and not WV:IsQuestQueuePreview(),
    'unlocking the head alone must not unlock the playlist')
WV:ToggleHeadPreview(true)
assert(not WowVoiceTalkingHead.EditBorder:IsShown() and not WV:IsQuestQueuePreview())

-- Empty-queue positioning uses display-only samples, never gameplay quests or audio.
local sounds = #plays
local originalChat = ChatFrame1
ChatFrame1 = CreateFrame('Frame', nil, UIParent)
ChatFrame1:SetSize(420, 180)
ChatFrame1:SetPoint('BOTTOMLEFT', UIParent, 'BOTTOMLEFT', 20, 40)
toggleFrames()
local player = frames.WowVoiceQuestQueuePlayer
local anchorPoint, relative, relativePoint, dx, dy = player:GetPoint()
assert(anchorPoint == 'TOPLEFT' and relative == ChatFrame1 and relativePoint == 'TOPLEFT')
assert(dx == 0 and dy == 280 + 24 and not WowVoiceDB.queuePosition,
    'the default reserves room for the playlist above the chat without saving a manual override')
assert(not panel.Buttons.queueResetPosition)
assert(player:IsShown() and player.editing and player:GetHeight() == 280)
assert(Q:Count() == 0 and #plays == sounds and player.EditOverlay:IsShown())
assert(player.clampRectInsets[2] == player.EditOverlay.points[2][4]
    and player.clampRectInsets[2] == -12,
    'native dragging must let the yellow right edge reach the screen edge')
assert(WowVoiceTalkingHead:IsShown() and WowVoiceTalkingHead.EditBorder:IsShown(),
    'unlocking the playlist also opens a framed, silent head preview')
assert(not panel.LockFrames:GetChecked())
local preview = player.preview
assert(preview and #preview.groups == 6 and preview.current.status == 'playing')
for _, frame in ipairs(allFrames) do
    if frame.groupKey and frame:IsShown() then assert(not frame.Remove, 'sample portraits have no delete controls') end
end
local originalSample = preview.current
local survivor = preview.groups[1].records[2] or preview.groups[2].records[1]
for _, group in ipairs(preview.groups) do
    for _, record in ipairs(group.records) do
        local matched = false
        for _, entry in ipairs(WowVoiceIndex[record.context.title] or {}) do
            if entry.q == record.context.questId and entry.i == group.speaker.npcID then matched = true end
        end
        assert(matched, 'preview must preserve actual quest titles and giver relationships')
    end
end
player.scripts.OnUpdate(player, 3)
assert(preview.current == originalSample, 'samples should not advance after only three seconds')
preview.elapsed = 5.99
player.scripts.OnUpdate(player, 0.3) -- A long triggering frame must not skip the new animation.
assert(preview.current == survivor and preview.current ~= originalSample and #preview.groups == 6)
local moving, sampleRow
for _, frame in ipairs(allFrames) do
    if frame.record == survivor and frame.Title then moving, sampleRow = frame.motion, frame end
end
assert(moving and moving.from > moving.target, 'surviving rows should slide upward')
local previewViewport = sampleRow:GetParent():GetParent()
assert(math.abs(select(2, previewViewport:GetCenter()) - previewViewport:GetHeight()/2
    - (select(2, player:GetCenter()) - player:GetHeight()/2)) < 0.00001,
    'the edit outline ends exactly at the visible viewport bottom')
assert(moving.elapsed == 0 and sampleRow.viewY == moving.from,
    'the triggering frame predates the animation, even if its dt exceeds the slide duration')
assert(Q:Count() == 0 and #plays == sounds and player:GetHeight() == 280)
sampleRow.Play.scripts.OnClick(sampleRow.Play)
sampleRow.Next.scripts.OnClick(sampleRow.Next)
sampleRow.Remove.scripts.OnClick(sampleRow.Remove)
assert(Q:Count() == 0 and #plays == sounds, 'preview controls must never dispatch gameplay actions')
player.scripts.OnUpdate(player, 0.05)
assert(sampleRow.motion and sampleRow.viewY < moving.from and sampleRow.viewY > moving.target)
player.scripts.OnUpdate(player, 0.15)
assert(not sampleRow.motion and sampleRow.viewY == moving.target)
player.EditOverlay.scripts.OnDragStart()
assert(player.moving)
local heldSample = preview.current
player.scripts.OnUpdate(player, 4)
assert(preview.current == heldSample, 'keep sample order stable while dragging')
player:ClearAllPoints()
player:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', 180, 750)
player.EditOverlay.scripts.OnDragStop()
assert(not player.moving and WowVoiceDB.queuePosition.x == 180 and WowVoiceDB.queuePosition.y == 750)
local headScale = WowVoiceTalkingHead:GetScale()
local originalScale = player:GetScale()
panel.QueueScale:SetValue(110)
assert(WV:GetQuestQueueScale() == 1.1 and math.abs(player:GetScale() - originalScale * 1.1) < 0.001)
local _, _, _, scaledX, scaledY = player:GetPoint()
assert(math.abs(scaledX * player:GetScale() - 180) < 0.001
    and math.abs(scaledY * player:GetScale() - 750) < 0.001,
    'scaling holds the saved screen position, rather than scaling the offsets')
assert(WowVoiceTalkingHead:GetScale() == headScale and #plays == sounds)
panel.QueueScaleInput:SetText('79')
panel.QueueScaleInput.scripts.OnEnterPressed(panel.QueueScaleInput)
assert(WV:GetQuestQueueScale() == 1.1)
panel.QueueScaleInput:SetText('115')
panel.QueueScaleInput.scripts.OnEnterPressed(panel.QueueScaleInput)
assert(WV:GetQuestQueueScale() == 1.15)
panel.QueueHeight:SetValue(460)
assert(WV:GetQuestQueueHeight() == 460 and player:GetHeight() == 460 and player:GetWidth() == 380)
assert(player:GetPoint() == 'TOPLEFT' and WowVoiceDB.queuePosition.y == 750,
    'height changes keep the saved top edge fixed')
panel.QueueHeightInput:SetText('279')
panel.QueueHeightInput.scripts.OnEnterPressed(panel.QueueHeightInput)
assert(WV:GetQuestQueueHeight() == 460 and panel.Status.text ~= '')
panel.QueueHeightInput:SetText('520')
panel.QueueHeightInput.scripts.OnEnterPressed(panel.QueueHeightInput)
assert(WV:GetQuestQueueHeight() == 520 and player:GetHeight() == 520)
panel:Hide()
assert(not WV:IsQuestQueuePreview() and not player:IsShown() and Q:Count() == 0 and #plays == sounds)
assert(not player.preview, 'closing options discards preview records and their timer')
assert(panel.LockFrames:GetChecked() and not WV:IsWindowsUnlocked(), 'closing options locks both frames')
assert(not WowVoiceTalkingHead:IsShown() and not WowVoiceTalkingHead.EditBorder:IsShown())
event('ADDON_LOADED')
assert(WV:GetQuestQueueHeight() == 520 and WowVoiceDB.queuePosition.y == 750,
    'saved position and height survive settings initialization')
assert(WV:GetQuestQueueScale() == 1.15)

-- Real playback is preserved while positioning, resizing and closing options.
Lab:Accept(pool[1].id); Lab:Accept(pool[2].id)
local current = Q.current
sounds = #plays
WV:OpenOptions()
toggleFrames()
panel.QueueHeight:SetValue(600)
assert(player:GetHeight() == 600 and Q.current == current and #plays == sounds)
local realCount = Q:Count()
for _ = 1, 4 do player.scripts.OnUpdate(player, 6.1) end
assert(Q.current == current and Q:Count() == realCount and #plays == sounds,
    'cycling the preview cannot advance, replace or append to live audio')
assert(WowVoiceTalkingHead.EditBorder:IsShown())
WowVoiceTalkingHead.scripts.OnDragStart()
assert(frames.WowVoiceTalkingHeadAnchor.moving and WowVoiceTalkingHead.draggingPosition,
    'the linked head is movable even during live audio')
toggleFrames()
assert(not player.editing and player:GetHeight() < 600 and Q.current == current)
assert(not WowVoiceTalkingHead.EditBorder:IsShown() and not WowVoiceTalkingHead.draggingPosition
    and not frames.WowVoiceTalkingHeadAnchor.moving and WowVoiceTalkingHead:IsShown(),
    'locking the playlist finishes the head drag while preserving live playback')
WowVoiceTalkingHead.scripts.OnDragStart()
assert(not WowVoiceTalkingHead.draggingPosition, 'the live head must be locked again')
toggleFrames()
WowVoiceTalkingHead.Close.scripts.OnClick()
assert(panel.LockFrames:GetChecked() and not player.editing and Q.current == current and #plays == sounds,
    'closing an unlocked head locks both frames without stopping current audio')
local onlyDescriptions = WowVoiceDB.queueDescriptionsOnly
panel.Buttons.queueReset.scripts.OnClick()
assert(WV:GetQuestQueueHeight() == 280 and player:GetHeight() == 280)
assert(WV:GetQuestQueueScale() == 1 and not WowVoiceDB.queuePosition and select(2, player:GetPoint()) == ChatFrame1)
assert(WowVoiceDB.queueDescriptionsOnly == onlyDescriptions, 'layout reset leaves playback preferences intact')
panel:Hide()
assert(player:IsShown() and not player.editing and Q.current == current and #plays == sounds)
Lab:Reset()

-- The master switch blocks new entries and closes editing, preserving playback.
WV:OpenOptions()
Lab:Accept(pool[1].id); Lab:Accept(pool[2].id)
local acceptPreference, turnInPreference = WowVoiceDB.autoPlayAccept, WowVoiceDB.autoPlayTurnIn
panel.QueueHeight:SetValue(460)
toggleFrames()
player.EditOverlay.scripts.OnDragStart()
player:ClearAllPoints()
player:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', 220, 790)
panel.QueueHeightInput:SetFocus()
local queuedCount, queuedCurrent, queuedSounds = Q:Count(), Q.current, #plays
panel.AutoPlay:SetChecked(false)
panel.AutoPlay.scripts.OnClick(panel.AutoPlay)
assert(Q:Count() == queuedCount and Q.current == queuedCurrent and #plays == queuedSounds and player:IsShown())
assert(not player.moving and not player.editing and not WV:IsQuestQueuePreview())
assert(WowVoiceDB.queuePosition.x == 220 and WowVoiceDB.queuePosition.y == 790,
    'disabling during a drag saves the current position before hiding the preview')
assert(WV:GetQuestQueueHeight() == 460 and not panel.QueueHeightInput.focus)
assert(not panel.QueueHeightInput.mouseEnabled and panel.QueueHeightInput.alpha == 0.45)
assert(not panel.QueueScaleInput.mouseEnabled and panel.QueueScaleInput.alpha == 0.45)
assert(not panel.QueuePositionX.mouseEnabled and not panel.QueuePositionY.mouseEnabled
    and not panel.Buttons.applyQueuePosition:IsEnabled())
for _, control in ipairs({panel.QueueHeight, panel.QueueScale, panel.Buttons.queueReset}) do
    assert(not control:IsEnabled() and control.alpha == 0.45)
end
for _, label in ipairs(panel.QueueLabels) do assert(label.alpha == 0.45) end
assert(panel.LockFrames:GetChecked())
toggleFrames()
assert(player.editing and WowVoiceTalkingHead.EditBorder:IsShown() and not panel.LockFrames:GetChecked()
    and #plays == queuedSounds, 'the common lock can position both frames while automatic startup is disabled')
toggleFrames()
assert(not player.editing and panel.LockFrames:GetChecked() and not WowVoiceTalkingHead.EditBorder:IsShown())
WV:PreviewQuestQueue(true)
assert(not player.editing, 'stale preview requests must not reopen editing while autoplay is off')
player.EditOverlay.scripts.OnDragStop()
assert(player:IsShown() and WowVoiceDB.queuePosition.y == 790)
assert(not panel.AutoPlayAccept:IsEnabled() and not panel.AutoPlayTurnIn:IsEnabled())
assert(not panel.QueueDescriptionsOnly:IsEnabled())
sounds = #plays
Lab:Accept(pool[3].id); Lab:TurnIn(pool[1].id)
assert(Q:Count() == queuedCount and Q.current == queuedCurrent and #plays == sounds)
assert(WV:ReplayQuest(pool[1].id))
assert(#plays == sounds + 1 and not Q.current and Q:Count() == queuedCount-1,
    'manual replay replaces the current line without adding a new entry when autoplay is off')
WV:Silence()
Q:Clear()
event('ADDON_LOADED')
assert(WowVoiceDB.autoPlay == false)
panel.AutoPlay:SetChecked(true)
panel.AutoPlay.scripts.OnClick(panel.AutoPlay)
assert(panel.AutoPlayAccept:IsEnabled() and panel.AutoPlayTurnIn:IsEnabled())
assert(WowVoiceDB.autoPlayAccept == acceptPreference and WowVoiceDB.autoPlayTurnIn == turnInPreference)
assert(panel.QueueHeight:IsEnabled() and panel.QueueHeightInput.mouseEnabled)
assert(panel.QueueScale:IsEnabled() and panel.QueueScaleInput.mouseEnabled)
assert(WV:GetQuestQueueHeight() == 460 and WowVoiceDB.queuePosition.y == 790)
for _, label in ipairs(panel.QueueLabels) do assert(label.alpha == 1) end
assert(not WV:IsQuestQueuePreview(), 're-enabling should not reopen the editor automatically')
-- Also preserve a position from a completed drag, while the editor is still open.
toggleFrames()
assert(player:IsShown() and player:GetPoint() == 'TOPLEFT')
WV:SetAutoPlayEnabled(false)
assert(not player:IsShown() and not player.editing and WowVoiceDB.queuePosition.y == 790)
WV:SetAutoPlayEnabled(true)
Lab:Reset()

-- Descriptions-only is opt-in and filters future turn-ins without pruning old ones.
local candidate
for _, item in ipairs(pool) do
    if WowVoiceDur[item.id .. 'p'] then candidate = item; break end
end
assert(candidate)
Lab:Accept(candidate.id)
Lab:TurnIn(candidate.id)
assert(Q:Count() == 3 and Q.current.context.section == 'a')
panel.QueueDescriptionsOnly:SetChecked(true)
panel.QueueDescriptionsOnly.scripts.OnClick(panel.QueueDescriptionsOnly)
assert(Q:Count() == 3 and Q.current.context.section == 'a')
local function turnInContext()
    return { questId = candidate.id, section = 'c', title = candidate.title,
        queueOwner = 'lab', speaker = { npcID = 1234, name = 'NPC' } }
end
Q:Offer(turnInContext())
assert(Q:Count() == 3)
Q:Clear()
sounds = #plays
Q:Offer(turnInContext())
assert(Q:Count() == 0 and #plays == sounds, 'the filter applies even while idle')
assert(Q:Start({ context = turnInContext() }), 'explicit playback is not suppressed by the queue filter')
assert(#plays == sounds + 1)
Q:Clear()
WV:SetQueueDescriptionsOnly(false)
Q:Offer(turnInContext())
assert(Q.current and Q.current.context.section == 'c')
Q:Clear()
panel:Hide()
ChatFrame1 = originalChat
-- Alignment only adjusts the playlist's Y, using visible head bounds in UI units.
WV:OpenOptions()
local oldCursor, oldUIScale = GetCursorPosition, UIParent.scale
local cursorX, cursorY = 700, 500
GetCursorPosition = function() return cursorX, cursorY end
local function near(a, b) assert(math.abs(a-b) < 0.00001, tostring(a)..' ~= '..tostring(b)) end
for _, uiScale in ipairs({1, 0.75}) do
    UIParent.scale = uiScale
    frames.WowVoiceHeadScaleEvents.scripts.OnEvent()
    frames.WowVoiceQuestQueueRoot.scripts.OnEvent()
    near(player.EditOverlay.backdrop.edgeSize*player.EditOverlay:GetEffectiveScale(), 1)
    for _, scale in ipairs({0.8, 1.2}) do
        WV:ApplyHeadSettings({width=570,height=155,scale=1,x=300,y=150})
        WV:SetHeadAnchor('TOPLEFT')
        WV:SetQuestQueueScale(scale)
        WV:PreviewQuestQueue(true)
        local left, top = WV:GetTalkingHeadPanelBounds()
        for _, border in ipairs({player.EditOverlay, frames.WowVoiceTalkingHead.EditBorder}) do
            near(border.backdrop.edgeSize*border:GetEffectiveScale(), 1)
            assert(border.backdropBorderColor[4] == 1, 'edit outlines must have the same color on different backgrounds')
        end
        local ratio = player:GetEffectiveScale()/UIParent:GetEffectiveScale()
        local width = (player:GetWidth()-12)*ratio
        assert(100+width < left)
        player:ClearAllPoints()
        player:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', 100/ratio, (top-8)/ratio)
        local headX, headY = frames.WowVoiceTalkingHeadAnchor:GetCenter()
        player.EditOverlay.scripts.OnDragStart()
        player.scripts.OnUpdate(player, 0.01)
        assert(player.AlignmentGuide:IsShown())
        assert(math.abs(tonumber(panel.QueuePositionX:GetText())-(100-UIParent:GetWidth()/2)) < 0.00501)
        assert(math.abs(tonumber(panel.QueuePositionY:GetText())-(top-UIParent:GetHeight()/2)) < 0.00501,
            'coordinates must show the snapped position before releasing the mouse')
        near(player.dragging.finalY, top)
        near(player.dragging.finalX, 100)
        local toolbar = player.Next:GetParent()
        near(select(2, toolbar:GetCenter()) + toolbar:GetHeight()/2,
            select(2, player:GetCenter()) + player:GetHeight()/2)
        near(select(2, previewViewport:GetCenter()) - previewViewport:GetHeight()/2,
            select(2, player:GetCenter()) - player:GetHeight()/2)
        near(player:GetHeight(), WV:GetQuestQueueHeight())
        local _, headTopCoordinate = WV:GetHeadAnchorPosition()
        local _, queueTopCoordinate = WV:GetQuestQueuePosition()
        near(headTopCoordinate, queueTopCoordinate)
        assert(panel.PositionY:GetText() == panel.QueuePositionY:GetText(),
            'aligned yellow top edges must show identical Y coordinates')
        cursorX = cursorX + 25*uiScale
        cursorY = cursorY - 5*uiScale -- 13 units away: hold existing snap.
        player.scripts.OnUpdate(player, 0.01)
        near(player.dragging.finalX, 125)
        near(player.dragging.finalY, top)
        cursorY = cursorY - 10*uiScale -- 23 units away: release.
        player.scripts.OnUpdate(player, 0.01)
        assert(not player.AlignmentGuide:IsShown())
        near(player.dragging.finalY, top-23)
        cursorY = cursorY + 15*uiScale
        player.scripts.OnUpdate(player, 0.01)
        assert(player.AlignmentGuide:IsShown())
        player.EditOverlay.scripts.OnDragStop()
        near(WowVoiceDB.queuePosition.x, 125)
        near(WowVoiceDB.queuePosition.y, top)
        assert(not player.AlignmentGuide:IsShown())
        local hx, hy = frames.WowVoiceTalkingHeadAnchor:GetCenter()
        near(hx, headX); near(hy, headY)
        -- Overlapping panels do not trigger this side-by-side alignment.
        player:ClearAllPoints()
        player:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', left/ratio, (top-8)/ratio)
        player.EditOverlay.scripts.OnDragStart()
        player.scripts.OnUpdate(player, 0.01)
        assert(not player.AlignmentGuide:IsShown())
        near(player.dragging.finalY, top-8)
        WV:PreviewQuestQueue(false)
        assert(not player.dragging and not player.AlignmentGuide:IsShown())
        WV:ApplyHeadSettings({width=570,height=155,scale=1,x=0,y=0})
        WV:SetQuestQueueHeight(280)
        WV:PreviewQuestQueue(true)
        local hl, ht, hr, hb = WV:GetTalkingHeadPanelBounds()
        local height = player:GetHeight()*ratio
        for _, side in ipairs({'beside-left', 'beside-right', 'above', 'below'}) do
            local beside = side == 'beside-left' or side == 'beside-right'
            for _, edge in ipairs(beside and {'top', 'bottom'} or {'left', 'right'}) do
                local wantedX = beside and (side == 'beside-left' and hl-width-30 or hr+30)
                    or (edge == 'left' and hl or hr-width)
                local wantedY = beside and (edge == 'top' and ht or hb+height)
                    or (side == 'above' and ht+height+30 or hb-30)
                player:ClearAllPoints()
                player:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT',
                    (wantedX + (beside and 0 or -6))/ratio,
                    (wantedY + (beside and -6 or 0))/ratio)
                player.EditOverlay.scripts.OnDragStart()
                player.scripts.OnUpdate(player, 0.01)
                assert(player.dragging.snapped == edge and player.AlignmentGuide:IsShown(),
                    string.format('%s %s: wanted %.1f,%.1f actual %.1f,%.1f height %.1f head %.1f,%.1f',
                        side, edge, wantedX, wantedY, player.dragging.finalX, player.dragging.finalY, height, ht, hb))
                near(player.dragging.finalX, wantedX)
                near(player.dragging.finalY, wantedY)
                local guide = player.AlignmentGuide
                if beside then
                    near(guide:GetHeight(), 1)
                    near(guide.points[1][5], edge == 'top' and ht or hb)
                    cursorX = cursorX + 5*uiScale
                    wantedX = wantedX + 5
                else
                    near(guide:GetWidth(), 1)
                    near(guide.points[1][4], edge == 'left' and hl or hr)
                    cursorY = cursorY + 5*uiScale
                    wantedY = wantedY + 5
                end
                player.scripts.OnUpdate(player, 0.01)
                near(player.dragging.finalX, wantedX)
                near(player.dragging.finalY, wantedY)
                player.EditOverlay.scripts.OnDragStop()
                near(WowVoiceDB.queuePosition.x, wantedX)
                near(WowVoiceDB.queuePosition.y, wantedY)
                assert(not player.AlignmentGuide:IsShown())
            end
        end
        WV:PreviewQuestQueue(false)
    end
end
GetCursorPosition, UIParent.scale = oldCursor, oldUIScale
frames.WowVoiceHeadScaleEvents.scripts.OnEvent()
-- Numeric placement is atomic, accepts signed decimals and shares the screen-center origin.
local beforePosition = WowVoiceDB.queuePosition
panel.QueuePositionX:SetFocus()
panel.QueuePositionX:SetText('-120,5')
panel.QueuePositionX.scripts.OnTabPressed(panel.QueuePositionX)
assert(panel.QueuePositionY.focus and not panel.QueuePositionX.focus)
panel.QueuePositionY:SetText('bad')
panel.Buttons.applyQueuePosition.scripts.OnClick()
assert(WowVoiceDB.queuePosition == beforePosition, 'invalid Y must not partially apply X')
WV:RefreshHeadOptions()
assert(panel.QueuePositionX:GetText() == '-120,5' and panel.QueuePositionY:GetText() == 'bad')
panel.QueuePositionY:SetText('200.25')
panel.QueuePositionY.scripts.OnEnterPressed()
local nx, ny = WV:GetQuestQueuePosition()
near(nx, -120.5); near(ny, 200.25)
assert(not panel.QueuePositionX.focus and not panel.QueuePositionY.focus and not panel.editingQueuePosition)
assert(player.autoPreview and not player.editing and panel.LockFrames:GetChecked())
panel.QueuePositionX:SetFocus(); panel.QueuePositionX:SetText('999')
panel.QueuePositionX.scripts.OnEscapePressed()
near(tonumber(panel.QueuePositionX:GetText()), nx)
beforePosition = WowVoiceDB.queuePosition
assert(not WV:SetQuestQueuePosition(math.huge, 0) and not WV:SetQuestQueuePosition(0, 0/0))
assert(WowVoiceDB.queuePosition == beforePosition)
panel.QueuePositionX:SetText('99999'); panel.QueuePositionY:SetText('99999')
panel.Buttons.applyQueuePosition.scripts.OnClick()
local ratio = player:GetEffectiveScale()/UIParent:GetEffectiveScale()
near(tonumber(panel.QueuePositionX:GetText()), UIParent:GetWidth()/2-(player:GetWidth()-12)*ratio)
near(tonumber(panel.QueuePositionY:GetText()), UIParent:GetHeight()/2)
panel.QueuePositionX:SetFocus(); panel.QueuePositionX:SetText('123')
panel.Buttons.queueReset.scripts.OnClick()
assert(not panel.editingQueuePosition and not WowVoiceDB.queuePosition)
panel:Hide()
assert(not panel.QueuePositionX.focus and not panel.QueuePositionY.focus)
-- Even an untouched default location uses the visible top-left as its scale pivot.
WV:OpenOptions()
local scaleChat = CreateFrame('Frame', nil, UIParent)
scaleChat:SetSize(420, 180)
scaleChat:SetPoint('BOTTOMLEFT', UIParent, 'BOTTOMLEFT', 20, 40)
for _, chat in ipairs({false, scaleChat}) do
    ChatFrame1 = chat or nil
    WV:ResetQuestQueueLayout()
    WV:PreviewQuestQueue(true)
    assert(not WowVoiceDB.queuePosition)
    local pivotX, pivotY = WV:GetQuestQueuePosition()
    for _, percent in ipairs({80, 120, 100}) do
        panel.QueueScale:SetValue(percent)
        local x, y = WV:GetQuestQueuePosition()
        near(x, pivotX); near(y, pivotY)
        near(tonumber(panel.QueuePositionX:GetText()), pivotX)
        near(tonumber(panel.QueuePositionY:GetText()), pivotY)
    end
    panel.QueueScaleInput:SetText('115')
    panel.QueueScaleInput.scripts.OnEnterPressed(panel.QueueScaleInput)
    local x, y = WV:GetQuestQueuePosition()
    near(x, pivotX); near(y, pivotY)
    WV:PreviewQuestQueue(false)
    WV:PreviewQuestQueue(true)
    x, y = WV:GetQuestQueuePosition()
    near(x, pivotX); near(y, pivotY)
end
ChatFrame1 = originalChat
panel:Hide()
print('PASS: playlist scaling holds the top-left corner before any manual placement, through slider, numeric input and reopening')
print('PASS: playlist coordinate entry, signed decimals, atomic validation, drafts, Tab/Escape, clamped readback, reset and live snapped readout')
print('PASS: top-edge alignment, horizontal freedom, release threshold, saved placement, overlap exclusion and scale conversion')
print('PASS: all four visible edges align from both sides, with correctly oriented guides and freedom along the other axis')
print('PASS: playlist geometry, animated silent sample/giver preview, live queue isolation, master autoplay/manual replay and descriptions-only filter')

-- DialogueUI fades UIParent, then hides it. Anchor targets do not inherit
-- visibility; actual parents do. Exercise both modes with a normal UI control.
local function visibleAlpha(frame)
    return frame:IsVisible() and frame:GetEffectiveAlpha() or 0
end
local uiShown, uiAlpha, uiScale = UIParent:IsVisible(), UIParent.alpha, UIParent.scale
local control = CreateFrame('Frame', nil, UIParent)
local queueRoot = frames.WowVoiceQuestQueueRoot
Lab:Reset()
WV:SetAutoPlayEnabled(true)
WV:SetAutoPlayAcceptEnabled(true)
Lab:Accept(pool[1].id)
Lab:Accept(pool[2].id)
local current, count, soundCount = Q.current, Q:Count(), #plays
local initialX, initialY = WV:GetQuestQueuePosition()
UIParent:Show()
UIParent:SetAlpha(0)
assert(visibleAlpha(control) == 0 and visibleAlpha(player) > 0 and WowVoiceTalkingHead:IsVisible(),
    'DialogueUI fade must not fade the playlist or talking head')
UIParent:Hide()
assert(visibleAlpha(control) == 0 and visibleAlpha(player) > 0,
    'DialogueUI hiding UIParent must not hide the playlist')
local x, y = WV:GetQuestQueuePosition()
near(x, initialX); near(y, initialY)
for _, scale in ipairs({0.75, 1}) do
    UIParent.scale = scale
    frames.WowVoiceHeadScaleEvents.scripts.OnEvent()
    queueRoot.scripts.OnEvent()
    near(player:GetEffectiveScale(), WowVoiceTalkingHead:GetEffectiveScale() * WV:GetQuestQueueScale())
    assert(visibleAlpha(player) > 0)
end
assert(Q.current == current and Q:Count() == count and #plays == soundCount,
    'UI hiding and scale changes must preserve queue playback')
UIParent.scale = uiScale
UIParent:SetAlpha(uiAlpha or 1)
if uiShown then UIParent:Show() else UIParent:Hide() end
frames.WowVoiceHeadScaleEvents.scripts.OnEvent()
queueRoot.scripts.OnEvent()
Lab:Reset()
control:Hide()
print('PASS: DialogueUI-style UIParent fade/hide preserves playlist visibility, placement, effective scale and active playback')

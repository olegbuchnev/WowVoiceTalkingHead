local L = WowVoiceLocale
local WV = WowVoice
local Q = WV.questQueue
local root, player, scroll, content, bar, controls
local headers, rows, tiles = {}, {}, {}
local offset, extent, updating, elapsed = 0, 0, false, 0
local browsing, scrollAnchor = false, nil
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local SLIDE_DURATION = 0.2
local HIDE_DURATION = 0.25
local MIN_HEIGHT, MAX_HEIGHT = 280, 600
local TILE_GAP, TILE_PADDING, TILE_INSET = 8, 6, 8
local PANEL_RIGHT = 12
local SCROLL_TOP = 28
local refreshScrollLayout
local MAX_EDGE_TRIM = 24
local PREVIEW_INTERVAL = 6
local AUTO_PREVIEW_FADE = 1
local SNAP_ENTER, SNAP_LEAVE = 10, 16
local previewPool

-- A display-only sample: never submit these records to the gameplay queue.
local function previewCandidates()
    if previewPool then return previewPool end
    previewPool = {}
    local byNPC, seen = {}, {}
    for title, entries in pairs(WowVoiceIndex or {}) do
        for _, entry in ipairs(entries) do
            if entry.i and entry.n and not seen[entry.q] and WowVoiceDur[entry.q .. "a"] then
                seen[entry.q] = true
                local npc = byNPC[entry.i]
                if not npc then
                    npc = { id = entry.i, name = entry.n, quests = {} }
                    byNPC[entry.i] = npc
                    previewPool[#previewPool + 1] = npc
                end
                npc.quests[#npc.quests + 1] = { id = entry.q, title = title }
            end
        end
    end
    return previewPool
end

local function fillPreview(preview)
    local pool, available, used = previewCandidates(), {}, {}
    for _, group in ipairs(preview.groups) do used[group.speaker.npcID] = true end
    for _, npc in ipairs(pool) do if not used[npc.id] then available[#available + 1] = npc end end
    while #preview.groups < 6 and #available > 0 do
        local npc = table.remove(available, math.random(#available))
        local candidates = {}
        for _, quest in ipairs(npc.quests) do candidates[#candidates + 1] = quest end
        preview.serial = preview.serial + 1
        local group = { key = "preview:" .. preview.serial, speaker = { npcID = npc.id, name = npc.name }, records = {} }
        for _ = 1, math.min(#candidates, math.random(1, 3)) do
            local quest = table.remove(candidates, math.random(#candidates))
            local replay = WV:GetReplaySpeaker(quest.id)
            if replay and replay.speaker and replay.speaker.npcID == npc.id then
                group.speaker.displayID = replay.speaker.displayID or group.speaker.displayID
            end
            group.records[#group.records + 1] = { group = group, status = "waiting",
                context = { questId = quest.id, title = quest.title, section = "a", queueOwner = "preview" } }
        end
        preview.groups[#preview.groups + 1] = group
    end
    preview.current = preview.groups[1] and preview.groups[1].records[1]
    if preview.current then preview.current.status = "playing" end
end

local function newPreview()
    local preview = { enabled = true, groups = {}, serial = 0, elapsed = 0 }
    function preview:Count()
        local count = 0
        for _, group in ipairs(self.groups) do count = count + #group.records end
        return count
    end
    function preview:CanSelect(record) return record ~= self.current end
    function preview:Waiting()
        for _, group in ipairs(self.groups) do
            for _, record in ipairs(group.records) do if record ~= self.current then return record end end
        end
    end
    function preview:CanPlayNext(record)
        local nextRecord = self.groups[1] and (self.groups[1].records[2]
            or self.groups[2] and self.groups[2].records[1])
        return record ~= self.current and record ~= nextRecord
    end
    fillPreview(preview)
    return preview
end

function WV:GetQuestQueueHeight()
    local height = WowVoiceDB and tonumber(WowVoiceDB.queueHeight)
    if not height or height ~= height then height = MIN_HEIGHT end
    return math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, math.floor(height + 0.5)))
end

function WV:GetQuestQueueScale()
    local scale = WowVoiceDB and tonumber(WowVoiceDB.queueScale)
    if not scale or scale ~= scale then scale = 1 end
    return math.max(0.8, math.min(1.2, scale))
end

local function positionPlayer(head)
    if player.dragging then return end
    root:SetScale(UIParent:GetEffectiveScale())
    local ratio = head:GetEffectiveScale() / UIParent:GetEffectiveScale() * WV:GetQuestQueueScale()
    player:SetScale(ratio)
    WV:UpdateFrameEditBorder(player.EditOverlay)
    player:ClearAllPoints()
    local saved = WowVoiceDB and WowVoiceDB.queuePosition
    if type(saved) == "table" and type(saved.x) == "number" and type(saved.y) == "number"
        and saved.x == saved.x and saved.y == saved.y and math.abs(saved.x) < 100000 and math.abs(saved.y) < 100000 then
        player:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.x / ratio, saved.y / ratio)
    elseif ChatFrame1 and ChatFrame1.GetCenter and ChatFrame1:GetCenter() then
        -- Reserve the selected height above chat; keep the top stable as short
        -- queues shrink, so changing the number of rows does not move the list.
        player:SetPoint("TOPLEFT", ChatFrame1, "TOPLEFT", 0, WV:GetQuestQueueHeight() + 24 / ratio)
    else
        player:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 20 / ratio,
            WV:GetQuestQueueHeight() + 240 / ratio)
    end
end

local function updateDrag()
    local drag = player and player.dragging
    if type(drag) ~= "table" then return end
    local cursorX, cursorY = GetCursorPosition()
    local uiScale = UIParent:GetEffectiveScale()
    local ratio = player:GetEffectiveScale() / uiScale
    local x = drag.x + (cursorX - drag.cursorX) / uiScale
    local y = drag.y + (cursorY - drag.cursorY) / uiScale
    local width = (player:GetWidth() - PANEL_RIGHT) * ratio
    local height = player:GetHeight() * ratio
    x = math.max(0, math.min(UIParent:GetWidth() - width, x))
    y = math.max(height, math.min(UIParent:GetHeight(), y))
    local left, top, right, bottom = WV:GetTalkingHeadPanelBounds()
    local best, bestDistance
    local function consider(edge, axis, target, line)
        local value = axis == "x" and x or y
        local low = axis == "x" and 0 or height
        local high = axis == "x" and UIParent:GetWidth() - width or UIParent:GetHeight()
        local distance = math.abs(value - target)
        local threshold = drag.snapped == edge and SNAP_LEAVE or SNAP_ENTER
        if target < low or target > high or distance > threshold then return end
        -- Keep the current edge until released instead of flickering between guides.
        if not best or (drag.snapped == edge)
            or (best.edge ~= drag.snapped and distance < bestDistance) then
            best = { edge = edge, axis = axis, target = target, line = line }
            bestDistance = distance
        end
    end
    if left then
        if x + width <= left or x >= right then
            consider("top", "y", top, top)
            consider("bottom", "y", bottom + height, bottom)
        end
        if y <= bottom or y - height >= top then
            consider("left", "x", left, left)
            consider("right", "x", right - width, right)
        end
    end
    drag.snapped = best and best.edge or nil
    if best then
        if best.axis == "x" then x = best.target else y = best.target end
    end
    player:ClearAllPoints()
    player:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / ratio, y / ratio)
    drag.finalX, drag.finalY = x, y
    if WV.RefreshQuestQueuePositionOptions then WV:RefreshQuestQueuePositionOptions(true) end
    local guide = player.AlignmentGuide
    if best then
        guide:ClearAllPoints()
        if best.axis == "y" then
            guide:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", math.min(x, left), best.line)
            guide:SetSize(math.max(x + width, right) - math.min(x, left), 1)
        else
            local low = math.min(y - height, bottom)
            guide:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", best.line, low)
            guide:SetSize(1, math.max(y, top) - low)
        end
        guide:Show()
    else guide:Hide() end
end

local function finishDrag()
    if not player or not player.dragging then return end
    updateDrag()
    local drag = player.dragging
    player:StopMovingOrSizing()
    player.dragging = nil
    player.AlignmentGuide:Hide()
    if type(drag) == "table" then
        WowVoiceDB.queuePosition = { x = drag.finalX, y = drag.finalY }
        if WV.RefreshQuestQueuePositionOptions then WV:RefreshQuestQueuePositionOptions(true) end
        return
    end
    local x, y = player:GetCenter()
    if x and y then
        local ratio = player:GetEffectiveScale() / UIParent:GetEffectiveScale()
        WowVoiceDB.queuePosition = { x = (x - player:GetWidth() / 2) * ratio,
            y = (y + player:GetHeight() / 2) * ratio }
    end
    if WV.RefreshQuestQueuePositionOptions then WV:RefreshQuestQueuePositionOptions(true) end
end

local function setOffset(value)
    offset = math.max(0, math.min(extent, value))
    updating = true
    bar:SetValue(offset)
    updating = false
    scroll:SetVerticalScroll(offset)
end

-- Keep the same visible entry under the reader's eyes while rows above move.
local function anchorScroll(previous)
    scrollAnchor = nil
    if not browsing then return end
    local firstY
    for _, collection in ipairs({ rows, headers }) do
        for _, frame in ipairs(collection) do
            local old = previous and previous[frame.layoutKey]
            local y = old and old.y or (not previous and frame.viewY)
            local height = old and old.height or frame:GetHeight()
            if frame:IsShown() and y and y + height > offset and (not firstY or y < firstY) then
                firstY = y
                scrollAnchor = { frame = frame, screenY = y - offset }
            end
        end
    end
end

local function updateScroll()
    if not browsing then
        setOffset(0)
    elseif scrollAnchor then
        setOffset(scrollAnchor.frame.viewY - scrollAnchor.screenY)
    else
        setOffset(offset)
    end
end

local function userScroll(value)
    setOffset(value)
    browsing = offset > 0
    anchorScroll()
    if refreshScrollLayout then refreshScrollLayout() end
end

local function position(frame, y)
    frame.viewY = y
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", content, "TOPLEFT", TILE_INSET, -y)
end

local function place(frame, identity, y, previous, mode)
    local old = previous[identity]
    frame.layoutKey, frame.motion = identity, nil
    if mode ~= "instant" and old then
        if old.motion and old.motion.target == y then
            frame.motion = old.motion
        elseif old.y ~= y and (mode == "advance" or old.motion) then
            frame.motion = { from = old.y, target = y, elapsed = 0 }
        end
    end
    position(frame, frame.motion and old.y or y)
end

local function text(parent, font, size)
    local value = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    local face, _, flags = value:GetFont()
    value:SetFont(face, size or 12, flags)
    value:SetShadowColor(0, 0, 0, 1)
    value:SetShadowOffset(1, -1)
    value:SetJustifyH("LEFT")
    value:SetWordWrap(true)
    value:SetNonSpaceWrap(true)
    return value
end

local function button(parent, label, width, callback)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 22)
    b.Label = text(b, "GameFontNormal", 11)
    b.Label:SetWordWrap(false)
    b.Label:SetText(label)
    b.Label:SetPoint("LEFT", b, "LEFT", 4, 0)
    b.Underline = b:CreateTexture(nil, "ARTWORK")
    b.Underline:SetPoint("TOPLEFT", b.Label, "BOTTOMLEFT", 0, -1)
    b.Underline:SetPoint("TOPRIGHT", b.Label, "BOTTOMRIGHT", 0, -1)
    b.Underline:SetHeight(1)
    local function appearance(hovered, pressed)
        local r, g, blue = 0.78, 0.68, 0.44
        if hovered then r, g, blue = 1, 0.85, 0.4 end
        if pressed then r, g, blue = 0.65, 0.55, 0.3 end
        if not b:IsEnabled() then r, g, blue = 0.39, 0.34, 0.22 end
        b.Label:SetTextColor(r, g, blue)
        b.Underline:SetColorTexture(r, g, blue, hovered and 0.85 or 0.5)
        for _, part in ipairs(b.ColorParts or {}) do part:SetVertexColor(r, g, blue, 1) end
    end
    b:SetScript("OnEnter", function(self) self.hovered = true; self:RefreshAppearance() end)
    b:SetScript("OnLeave", function(self) self.hovered = false; self:RefreshAppearance() end)
    b:SetScript("OnHide", function(self) self.hovered, self.pressed = false, false; self:RefreshAppearance() end)
    b:SetScript("OnMouseDown", function(self) self.pressed = true; self:RefreshAppearance() end)
    b:SetScript("OnMouseUp", function(self) self.pressed = false; self:RefreshAppearance() end)
    b:SetScript("OnClick", callback)
    b.RefreshAppearance = function(self) appearance(self.hovered or self.Check and self.Check.hovered, self.pressed) end
    appearance(false)
    return b
end

local function refreshControls(view, editing)
    local b = controls.Autoplay
    b.Check:SetChecked(not view.paused)
    b.Check.Mark:SetShown(not view.paused)
    b:SetEnabled(not editing)
    b.Check:SetEnabled(not editing)
    b:RefreshAppearance()
    controls.Next:SetEnabled(not editing and view:Waiting() ~= nil)
    controls.Clear:SetEnabled(not editing)
    controls.Next:RefreshAppearance()
    controls.Clear:RefreshAppearance()
end

local function fitTitle(label, value, availableWidth)
    L.ApplyContentFont(label, value)
    local measure = player.TextMeasure
    measure:SetFont(label:GetFont())
    measure:SetText(value)
    -- Measure independently of a pooled row's previous wrapping and width.
    local width = math.max(1, math.min(availableWidth, math.ceil(measure:GetStringWidth()) + 1))
    label:SetWidth(width)
    label:SetHeight(0)
    label:SetText(value)
    local height = math.ceil(label:GetStringHeight())
    label:SetHeight(height)
    return height
end

local function removeButton(parent, callback)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(20, 20)
    b.Icon = b:CreateTexture(nil, "ARTWORK")
    b.Icon:SetTexture("Interface\\AddOns\\WowVoiceTalkingHead\\Media\\QueueClose.png")
    b.Icon:SetSize(16, 16)
    b.Icon:SetPoint("CENTER")
    b.Icon:SetDesaturated(true)
    local function reset() b.Icon:SetVertexColor(0.7, 0.7, 0.7, 0.75) end
    b:SetScript("OnEnter", function() b.Icon:SetVertexColor(1, 0.4, 0.3, 1) end)
    b:SetScript("OnLeave", reset)
    b:SetScript("OnHide", function(self) self.target = nil; reset() end)
    b:SetScript("OnClick", callback)
    reset()
    return b
end

local function createBackground(owner)
    owner = owner or player
    -- Sample the visible panel bounds used by the head's edit outline.
    -- Including the sheet's transparent margins would inset the rendered tile
    -- from its frame and break visual alignment despite matching snap bounds.
    -- Nine slices keep the small corners fixed as the queue grows vertically.
    owner.BackgroundParts = {}
    local x, y = { 15, 80, 490, 557 }, { 15, 40, 115, 142 }
    for row = 1, 3 do
        for column = 1, 3 do
            local texture = owner:CreateTexture(nil, "BACKGROUND")
            texture:SetTexture("Interface\\AddOns\\WowVoiceTalkingHead\\Media\\TalkingHeads")
            texture:SetTexCoord(x[column]/1024, x[column + 1]/1024, y[row]/1024, y[row + 1]/1024)
            owner.BackgroundParts[#owner.BackgroundParts + 1] = { texture = texture, row = row, column = column }
        end
    end
end

local function layoutBackground(width, height, owner)
    owner = owner or player
    local edge = 8
    local x, y = { 0, edge, width - edge }, { 0, edge, height - edge }
    local w, h = { edge, width - 2 * edge, edge }, { edge, height - 2 * edge, edge }
    for _, part in ipairs(owner.BackgroundParts) do
        part.texture:ClearAllPoints()
        part.texture:SetPoint("TOPLEFT", owner, "TOPLEFT", x[part.column], -y[part.row])
        part.texture:SetSize(w[part.column], h[part.row])
    end
end

local function tile(index)
    if not tiles[index] then
        local frame = CreateFrame("Frame", nil, content)
        frame:SetFrameLevel(content:GetFrameLevel())
        frame:EnableMouse(false)
        createBackground(frame)
        tiles[index] = frame
    end
    return tiles[index]
end

local function updateTiles()
    for _, frame in ipairs(tiles) do
        if frame:IsShown() and frame.first and frame.last then
            local top = frame.first.viewY - TILE_PADDING
            local bottom = frame.last.viewY + frame.last:GetHeight() + TILE_PADDING
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -top)
            frame:SetSize(content:GetWidth(), math.max(16, bottom - top))
            layoutBackground(frame:GetWidth(), frame:GetHeight(), frame)
        end
    end
end

local function fadingHeight(fade)
    local t = math.min(1, fade.elapsed / SLIDE_DURATION)
    return fade.targetHeight + (fade.height - fade.targetHeight) * (1 - t)^3
end

local function visibleContentHeight()
    local height = player.contentHeight or 0
    for _, collection in ipairs({ headers, rows }) do
        for _, frame in ipairs(collection) do
            if frame:IsShown() and frame.viewY then
                height = math.max(height, frame.viewY + frame:GetHeight() + TILE_PADDING)
            end
        end
    end
    return height
end

local function layoutViewport(width, height, contentHeight)
    if player.preview then height = WV:GetQuestQueueHeight() - SCROLL_TOP end
    -- Controls stay at the fixed top edge while the scroll viewport adapts
    -- to tile boundaries and the remaining queue gets shorter.
    -- Trim small fragments at the bottom to the last complete giver tile.
    -- The configured maximum stays a ceiling; large tiles still scroll normally.
    if not player.preview and not player.fading and contentHeight > height then
        local viewOffset = browsing and scrollAnchor and scrollAnchor.frame.viewY - scrollAnchor.screenY or offset
        viewOffset = math.max(0, math.min(viewOffset, contentHeight - height))
        local boundary = viewOffset + height
        local lastBottom
        for _, card in ipairs(tiles) do
            if card:IsShown() and card.last then
                local bottom = card.last.viewY + card.last:GetHeight() + TILE_PADDING
                if bottom <= boundary and (not lastBottom or bottom > lastBottom) then lastBottom = bottom end
            end
        end
        if lastBottom and boundary - lastBottom <= MAX_EDGE_TRIM and lastBottom - viewOffset >= 60 then
            height = lastBottom - viewOffset
        end
    end
    -- The viewport's bottom is the visible panel bottom, including after trimming.
    player:SetHeight(height + SCROLL_TOP)
    scroll:SetSize(width - 36, height)
    content:SetSize(width - 36, contentHeight)
    updateTiles()
    controls:SetWidth(width - 36)
    controls.Autoplay:SetWidth(math.ceil(controls.Autoplay.Label:GetStringWidth()) + 28)
    controls.Next:SetWidth(math.ceil(controls.Next.Label:GetStringWidth()) + 24)
    controls.Clear:SetWidth(math.ceil(controls.Clear.Label:GetStringWidth()) + 8)
    -- Share the remaining space between both gaps, regardless of label language.
    local gap = math.max(0, (controls:GetWidth() - 16 - controls.Clear:GetWidth()
        - controls.Autoplay:GetWidth() - controls.Next:GetWidth()) / 2)
    controls.Autoplay:ClearAllPoints()
    controls.Autoplay:SetPoint("LEFT", controls.Clear, "RIGHT", gap, 0)
    extent = math.max(0, contentHeight - height)
    updating = true
    bar:SetHeight(math.max(1, height))
    bar.Thumb:SetHeight(math.min(height, math.max(28, height * height / math.max(1, contentHeight))))
    bar:SetMinMaxValues(0, extent)
    bar:SetShown(extent > 0)
    updating = false
    updateScroll()
end

refreshScrollLayout = function()
    if not player or not player:IsShown() or player.preview or player.fading then return end
    local height = visibleContentHeight()
    layoutViewport(player:GetWidth(), math.min(WV:GetQuestQueueHeight() - SCROLL_TOP, height), height)
end

local function header(index)
    if headers[index] then return headers[index] end
    local h = CreateFrame("Frame", nil, content)
    h:SetSize(400, 40)
    h.Portrait = h:CreateTexture(nil, "ARTWORK")
    h.Portrait:SetSize(32, 32)
    h.Portrait:SetPoint("LEFT", h, "LEFT", 2, 0)
    if h.Portrait.SetMask then h.Portrait:SetMask(MASK) end
    h.Name = text(h, "GameFontNormal", 12)
    h.Name:SetPoint("LEFT", h, "LEFT", 44, 0)
    h.Name:SetSize(340, 22)
    h:EnableMouse(false)
    headers[index] = h
    return h
end

local function setPortrait(h, speaker)
    local display = WV:GetQuestQueuePortraitDisplay(speaker)
    local identity = tostring(display) .. ":" .. tostring(speaker.icon)
    if h.identity == identity then return end
    h.identity = identity
    h.Portrait:SetTexture(speaker.icon or "Interface\\Icons\\INV_Misc_Note_01")
    if display and SetPortraitTextureFromCreatureDisplayID then
        SetPortraitTextureFromCreatureDisplayID(h.Portrait, display)
    end
end

local function captureRowPress(control, record)
    control.cancelledPress = player.preview ~= nil
    control.pressedRecord = not control.cancelledPress and record or nil
end

local function cancelRowPress(control)
    if control.pressedRecord then control.cancelledPress = true end
    control.pressedRecord = nil
end

local function takeRowPress(control, currentRecord)
    local cancelled, record = control.cancelledPress, control.pressedRecord or currentRecord
    control.cancelledPress, control.pressedRecord = nil, nil
    if cancelled or player.preview or not record or record.context.queueOwner == "preview" then return end
    return record
end

local function row(index)
    if rows[index] then return rows[index] end
    local r = CreateFrame("Button", nil, content)
    r:SetSize(400, 26)
    r.Icon = r:CreateTexture(nil, "ARTWORK")
    r.Icon:SetSize(16, 16)
    r.Icon:SetPoint("LEFT", r, "LEFT", 44, 0)
    r.Title = text(r)
    r.Title:SetPoint("LEFT", r, "LEFT", 64, 0)
    r.Remove = removeButton(r, function(self)
        local record = takeRowPress(self, r.record)
        if record then Q:DeleteQuest(record) end
    end)
    r.Remove:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.Remove:SetScript("OnMouseDown", function(self) captureRowPress(self, r.record) end)
    r.Remove:HookScript("OnHide", cancelRowPress)
    r.Bars = {}
    for i = 1, 3 do
        local t = r:CreateTexture(nil, "OVERLAY")
        t:SetTexture(WHITE)
        t:SetVertexColor(1, 0.8, 0.15, 1)
        t:SetSize(3, 6)
        t:SetPoint("BOTTOMLEFT", r.Title, "BOTTOMRIGHT", 6 + (i - 1) * 5, 0)
        r.Bars[i] = t
    end
    r.Next = button(r, L["Следующим"], 84, function(self)
        local record = takeRowPress(self, r.record)
        if Q:CanPlayNext(record) then Q:PlayNext(record) end
    end)
    r.Next:SetPoint("LEFT", r.Title, "RIGHT", 6, 0)
    r.Next:HookScript("OnMouseDown", function(self) captureRowPress(self, r.record) end)
    r.Next:HookScript("OnHide", cancelRowPress)
    r.Play = CreateFrame("Button", nil, r)
    r.Play:SetSize(22, 22)
    r.Play:SetPoint("LEFT", r, "LEFT", 20, 0)
    r.Play.Icon = r.Play:CreateTexture(nil, "ARTWORK")
    r.Play.Icon:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    r.Play.Icon:SetSize(20, 20)
    r.Play.Icon:SetPoint("CENTER")
    r.Play:SetAlpha(0.7)
    r.Play:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
    r.Play:SetScript("OnLeave", function(self) self:SetAlpha(0.7) end)
    r.Play:SetScript("OnHide", function(self) cancelRowPress(self); self:SetAlpha(0.7) end)
    r.Play:SetScript("OnMouseDown", function(self) captureRowPress(self, r.record) end)
    r.Play:SetScript("OnClick", function(self)
        local record = takeRowPress(self, r.record)
        if Q:CanSelect(record) then Q:Start(record, true) end
    end)
    r:SetScript("OnMouseDown", function(self) captureRowPress(self, self.record) end)
    r:SetScript("OnHide", cancelRowPress)
    r:SetScript("OnClick", function(self)
        local record = takeRowPress(self, self.record)
        if Q:CanSelect(record) then Q:Start(record, true) end
    end)
    rows[index] = r
    return r
end

local function create()
    if player then return end
    -- Match UIParent's coordinate scale without inheriting its visibility or
    -- alpha (DialogueUI hides/fades it while the quest dialogue is open).
    root = CreateFrame("Frame", "WowVoiceQuestQueueRoot")
    root:SetScale(UIParent:GetEffectiveScale())
    root:RegisterEvent("UI_SCALE_CHANGED")
    root:RegisterEvent("DISPLAY_SIZE_CHANGED")
    root:SetScript("OnEvent", function()
        root:SetScale(UIParent:GetEffectiveScale())
        if player and player.EditOverlay then WV:UpdateFrameEditBorder(player.EditOverlay) end
    end)
    player = CreateFrame("Frame", "WowVoiceQuestQueuePlayer", root)
    player:SetFrameStrata("FULLSCREEN_DIALOG")
    player:SetFrameLevel(WowVoiceTalkingHead:GetFrameLevel())
    player:SetClampedToScreen(true)
    -- Clamp to the tiles/edit outline, excluding the empty right margin.
    player:SetClampRectInsets(0, -PANEL_RIGHT, 0, 0)
    player:SetMovable(true)
    local guide = CreateFrame("Frame", nil, root)
    player.AlignmentGuide = guide
    guide:SetFrameStrata("FULLSCREEN_DIALOG")
    guide:SetFrameLevel(player:GetFrameLevel() + 30)
    guide:EnableMouse(false)
    guide.Line = guide:CreateTexture(nil, "OVERLAY")
    guide.Line:SetAllPoints()
    guide.Line:SetColorTexture(1, 0.82, 0.25, 0.95)
    guide:Hide()
    player.TextMeasure = text(player)
    player.TextMeasure:SetWordWrap(false)
    player.TextMeasure:SetNonSpaceWrap(false)
    player.TextMeasure:Hide()
    createBackground()
    scroll = CreateFrame("ScrollFrame", nil, player)
    scroll:SetPoint("TOPLEFT", player, "TOPLEFT", 24, -SCROLL_TOP)
    content = CreateFrame("Frame", nil, scroll)
    scroll:SetScrollChild(content)
    bar = CreateFrame("Slider", "WowVoiceQuestQueueScroll", player)
    bar:SetPoint("TOPLEFT", player, "TOPLEFT", 0, -SCROLL_TOP)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(16)
    bar.Track = bar:CreateTexture(nil, "BACKGROUND")
    bar.Track:SetColorTexture(0, 0, 0, 0.5)
    bar.Track:SetPoint("TOP", bar, "TOP", 0, 0)
    bar.Track:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    bar.Track:SetWidth(2)
    bar.Thumb = bar:CreateTexture(nil, "ARTWORK")
    bar.Thumb:SetColorTexture(0.8, 0.67, 0.4, 0.9)
    bar.Thumb:SetSize(3, 28)
    bar:SetThumbTexture(bar.Thumb)
    bar:SetScript("OnEnter", function() bar.Thumb:SetColorTexture(1, 0.82, 0.45, 1) end)
    bar:SetScript("OnLeave", function() bar.Thumb:SetColorTexture(0.8, 0.67, 0.4, 0.9) end)
    bar:SetValueStep(1)
    bar:SetObeyStepOnDrag(true)
    bar:SetScript("OnValueChanged", function(_, value)
        if updating then return end
        userScroll(value)
    end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta) userScroll(offset - delta * 26) end)
    bar:EnableMouseWheel(true)
    bar:SetScript("OnMouseWheel", function(_, delta) userScroll(offset - delta * 26) end)
    controls = CreateFrame("Frame", nil, player)
    -- The visible toolbar top is also the edit outline and alignment edge.
    controls:SetPoint("TOPLEFT", player, "TOPLEFT", 24, 0)
    controls:SetSize(400, 24)
    controls.Background = controls:CreateTexture(nil, "BACKGROUND")
    controls.Background:SetAllPoints(controls)
    -- A solid cool tint separates the toolbar from translucent black quest tiles.
    controls.Background:SetColorTexture(0.10, 0.13, 0.16, 1)
    local function toggleAutoplay()
        if not player.preview then WV:SetQueueAutoPlay(Q.paused) end
    end
    local autoplay = button(controls, L["Автовоспроизведение"], 160, toggleAutoplay)
    controls.Autoplay, player.Autoplay = autoplay, autoplay
    autoplay.Underline:Hide()
    autoplay.Label:ClearAllPoints()
    autoplay.Label:SetPoint("LEFT", autoplay, "LEFT", 24, 0)
    autoplay.Check = CreateFrame("CheckButton", nil, autoplay)
    autoplay.Check:SetSize(22, 22)
    autoplay.Check:SetPoint("LEFT", autoplay, "LEFT")
    autoplay.ColorParts = {}
    for _, edge in ipairs({ { 14, 1, 4, 7 }, { 14, 1, 4, -6 }, { 1, 14, 4, 7 }, { 1, 14, 17, 7 } }) do
        local part = autoplay.Check:CreateTexture(nil, "ARTWORK")
        part:SetColorTexture(1, 1, 1, 1)
        part:SetSize(edge[1], edge[2])
        part:SetPoint("TOPLEFT", autoplay.Check, "LEFT", edge[3], edge[4])
        autoplay.ColorParts[#autoplay.ColorParts + 1] = part
    end
    local mark = autoplay.Check:CreateTexture(nil, "ARTWORK")
    mark:SetTexture("Interface\\AddOns\\WowVoiceTalkingHead\\Media\\QueueCheck")
    mark:SetSize(12, 12)
    mark:SetPoint("CENTER")
    autoplay.Check.Mark = mark
    autoplay.ColorParts[#autoplay.ColorParts + 1] = mark
    autoplay.Check:SetScript("OnClick", toggleAutoplay)
    autoplay.Check:SetScript("OnEnter", function(self)
        self.hovered = true
        autoplay:RefreshAppearance()
    end)
    local function clearCheckHover(self)
        self.hovered = false
        autoplay:RefreshAppearance()
    end
    autoplay.Check:SetScript("OnLeave", clearCheckHover)
    autoplay.Check:SetScript("OnHide", clearCheckHover)
    autoplay.Check:SetScript("OnMouseDown", function() autoplay.pressed = true; autoplay:RefreshAppearance() end)
    autoplay.Check:SetScript("OnMouseUp", function() autoplay.pressed = false; autoplay:RefreshAppearance() end)
    local nextButton = button(controls, L["Далее"], 60, function()
        if not player.preview then Q:Start(Q:Waiting(), true) end
    end)
    controls.Next, player.Next = nextButton, nextButton
    nextButton.Underline:Hide()
    nextButton:SetPoint("RIGHT", controls, "RIGHT", -8, 0)
    nextButton.Label:ClearAllPoints()
    nextButton.Label:SetPoint("RIGHT", nextButton, "RIGHT", 0, 0)
    nextButton.Icon = nextButton:CreateTexture(nil, "ARTWORK")
    nextButton.Icon:SetTexture("Interface\\AddOns\\WowVoiceTalkingHead\\Media\\QueueNext")
    nextButton.Icon:SetSize(14, 14)
    nextButton.Icon:SetPoint("RIGHT", nextButton.Label, "LEFT", -6, 0)
    nextButton.ColorParts = { nextButton.Icon }
    controls.Clear = button(controls, L["Очистить всё"], 90, function() if not player.preview then Q:Clear() end end)
    controls.Clear.Underline:Hide()
    controls.Clear:SetPoint("LEFT", controls, "LEFT", 8, 0)
    controls.Clear.Label:ClearAllPoints()
    controls.Clear.Label:SetPoint("LEFT", controls.Clear, "LEFT", 0, 0)
    local edit = CreateFrame("Frame", nil, player, "BackdropTemplate")
    player.EditOverlay = edit
    edit:SetPoint("TOPLEFT", player, "TOPLEFT")
    -- Tiles start at x=24 and span width-36, ending 12 units before the frame.
    edit:SetPoint("BOTTOMRIGHT", player, "BOTTOMRIGHT", -PANEL_RIGHT, 0)
    edit:SetFrameLevel(player:GetFrameLevel() + 20)
    WV:UpdateFrameEditBorder(edit)
    edit:EnableMouse(true)
    edit:RegisterForDrag("LeftButton")
    edit:SetScript("OnDragStart", function()
        if not player.editing then return end
        local x, y = player:GetCenter()
        if GetCursorPosition and x and y then
            local cursorX, cursorY = GetCursorPosition()
            local ratio = player:GetEffectiveScale() / UIParent:GetEffectiveScale()
            player.dragging = { x = (x - player:GetWidth()/2) * ratio,
                y = (y + player:GetHeight()/2) * ratio, cursorX = cursorX, cursorY = cursorY }
        else player.dragging = true; player:StartMoving() end
    end)
    edit:SetScript("OnDragStop", function() finishDrag(); WV:RefreshQuestQueuePlayer() end)
    edit:Hide()
    player:SetScript("OnHide", function()
        finishDrag()
        player.pendingLayoutMode = nil
        player.fading = nil
        browsing, scrollAnchor, offset = false, nil, 0
        player:SetAlpha(1)
        for _, collection in ipairs({ headers, rows }) do
            for _, frame in ipairs(collection) do frame.motion, frame.layoutKey, frame.viewY = nil, nil, nil end
        end
        for _, frame in ipairs(rows) do
            for _, control in ipairs({ frame, frame.Play, frame.Next, frame.Remove }) do cancelRowPress(control) end
        end
    end)
    player:SetScript("OnUpdate", function(_, dt)
        if player.autoPreview and player.autoHideAt and GetTime() >= player.autoHideAt then
            local t = math.min(1, (GetTime() - player.autoHideAt) / AUTO_PREVIEW_FADE)
            if t == 1 then WV:HideAutoQuestQueuePreview(); return end
            player:SetAlpha(1 - t * t)
        end
        updateDrag()
        if player.editing and WV.RefreshQuestQueuePositionOptions then WV:RefreshQuestQueuePositionOptions() end
        local view = player.preview or Q
        local moved = false
        for _, collection in ipairs({ headers, rows }) do
            for _, frame in ipairs(collection) do
                local motion = frame.motion
                if motion then
                    moved = true
                    motion.elapsed = math.min(SLIDE_DURATION, motion.elapsed + dt)
                    local t = motion.elapsed / SLIDE_DURATION
                    position(frame, motion.from + (motion.target - motion.from) * (1 - (1 - t)^3))
                    if t == 1 then frame.motion = nil end
                end
            end
        end
        if moved and not player.fading then
            local height = visibleContentHeight()
            layoutViewport(player:GetWidth(), math.min(WV:GetQuestQueueHeight() - SCROLL_TOP, height), height)
        end
        if player.fading then
            player.fading.elapsed = math.min(HIDE_DURATION, player.fading.elapsed + dt)
            local height = fadingHeight(player.fading)
            layoutViewport(player.fading.width, height - SCROLL_TOP, visibleContentHeight())
            local t = player.fading.elapsed / HIDE_DURATION
            player:SetAlpha(1 - t * t)
            if t == 1 then player:Hide(); return end
        end
        elapsed = elapsed + dt
        local phase = math.floor(GetTime() * 5)
        for _, r in ipairs(rows) do
            if r.record and r.record == view.current and r.record.status == "playing" then
                for i, t in ipairs(r.Bars) do t:SetHeight(4 + ((phase + i * 2) % 4) * 3) end
            end
        end
        if elapsed >= 0.25 then
            elapsed = 0
            WV:RefreshQuestQueuePlayer()
        end
        -- Start the sample transition after advancing existing animations.
        -- This frame's dt predates the new motion and must not consume its start.
        if player.editing and not player.dragging then
            view.elapsed = view.elapsed + dt
            if view.elapsed >= PREVIEW_INTERVAL then
                view.elapsed = 0
                local group = view.groups[1]
                if group then
                    table.remove(group.records, 1)
                    if #group.records == 0 then table.remove(view.groups, 1) end
                end
                fillPreview(view)
                browsing, scrollAnchor, offset = false, nil, 0
                WV:RefreshQuestQueuePlayer("advance")
            end
        end
    end)
end

function WV:RefreshQuestQueuePlayer(layoutMode)
    local head = WowVoiceTalkingHead
    local editing = player and player.editing
    local previewing = player and player.preview ~= nil
    local view = previewing and player.preview or Q
    local count = view:Count()
    if not view.enabled or not head or (count == 0 and not previewing) then
        if player then player:Hide() end
        return
    end
    local startingFade = false
    -- A sole playing line is represented by the head; an idle waiting line needs controls.
    if count == 1 and view.current and view.current.status == "playing" and not previewing then
        if not player or not player:IsShown() then return end
        if not player.fading then
            player.fading = { elapsed = 0, height = player:GetHeight() }
            startingFade = true
            layoutMode = "advance"
        end
    elseif player and player.fading then
        player.fading = nil
        player:SetAlpha(1)
    end
    create()
    for _, part in ipairs(player.BackgroundParts) do part.texture:Hide() end
    player.EditOverlay:SetShown(editing == true)
    scroll:Show(); controls:Show()
    refreshControls(view, previewing)
    if previewing then
        if editing then self:RefreshPlaylistHeadPreview() end
        local portraitGroups = {}
        for _, group in ipairs(Q.groups) do portraitGroups[#portraitGroups + 1] = group end
        for _, group in ipairs(view.groups) do portraitGroups[#portraitGroups + 1] = group end
        self:PrepareQuestQueuePortraits(portraitGroups)
    end
    if layoutMode then player.pendingLayoutMode = layoutMode end
    local questFontSize = 11
    local width = 380
    positionPlayer(head)
    player:SetWidth(width)
    player:Show()
    local pauseChanged = player.wasPaused ~= view.paused
    player.wasPaused = view.paused
    -- Avoid recycling a row underneath the pointer while a recording ends.
    if not previewing and MouseIsOver and MouseIsOver(scroll) and not Q.forceRefresh and not pauseChanged and not startingFade then return end
    layoutMode = player.pendingLayoutMode
    player.pendingLayoutMode = nil
    local previous, headerOccurrences = {}, {}
    for _, collection in ipairs({ headers, rows }) do
        for _, frame in ipairs(collection) do
            if frame.layoutKey and frame.viewY and frame:IsShown() then
                previous[frame.layoutKey] = { y = frame.viewY, height = frame:GetHeight(), motion = frame.motion }
            end
        end
    end
    local questCounts, shownQuests = {}, {}
    for _, group in ipairs(view.groups) do
        for _, record in ipairs(group.records) do
            local id = record.context.questId
            local identity = tostring(record.context.queueOwner or "game") .. ":" .. id
            questCounts[identity] = (questCounts[identity] or 0) + 1
        end
    end
    local y, used = 0, 0
    for i, group in ipairs(view.groups) do
        if i > 1 then y = y + TILE_GAP end
        y = y + TILE_PADDING
        local h = header(i)
        local card = tile(i)
        card.first, card.giverKey = h, group.key
        card:Show()
        h.groupKey = group.key
        headerOccurrences[group.key] = (headerOccurrences[group.key] or 0) + 1
        place(h, group.key .. ":" .. headerOccurrences[group.key], y, previous, layoutMode)
        h:SetWidth(width - 44 - 2 * TILE_INSET)
        h.Name:SetWidth(width - 90 - 2 * TILE_INSET)
        local name = group.speaker.name or L["Неизвестный NPC"]
        L.SetContentText(h.Name, name:match("^%[([^%[%]]+)%]$") or name)
        h.Name:SetHeight(0)
        local nameHeight = math.ceil(h.Name:GetStringHeight())
        h.Name:SetHeight(nameHeight)
        local headerHeight = math.max(40, nameHeight + 10)
        h:SetHeight(headerHeight)
        setPortrait(h, group.speaker)
        h:Show()
        y = y + headerHeight
        for _, record in ipairs(group.records) do
            used = used + 1
            local r = row(used)
            card.last = r
            r.record = record
            local font, _, flags = r.Title:GetFont()
            r.Title:SetFont(font, questFontSize, flags)
            local linkFont, _, linkFlags = r.Next.Label:GetFont()
            r.Next.Label:SetFont(linkFont, questFontSize, linkFlags)
            local questKey = tostring(record.context.queueOwner or "game") .. ":" .. record.context.questId
            r.Remove:ClearAllPoints()
            if record == view.current then
                r.Remove:SetPoint("CENTER", r.Play, "CENTER")
            else
                r.Remove:SetPoint("LEFT", r, "LEFT", 0, 0)
            end
            r.Remove:SetShown(not shownQuests[questKey] and (record ~= view.current or questCounts[questKey] > 1))
            shownQuests[questKey] = true
            place(r, record, y, previous, layoutMode)
            r:SetWidth(width - 36 - 2 * TILE_INSET)
            local title = record.context.title or (L["Задание "] .. record.context.questId)
            local blocked = record ~= view.current and not view:CanSelect(record)
            local canPlayNext = view:CanPlayNext(record)
            local titleWidth = width - 36 - 2 * TILE_INSET - 64 - (record == view.current and 24 or canPlayNext and 90 or 0)
            local titleHeight = fitTitle(r.Title, (record.context.section ~= "a" and L["Сдача: "] or "") .. title, titleWidth)
            local rowHeight = math.max(26, titleHeight + 8)
            r:SetHeight(rowHeight)
            r.Icon:SetTexture(record.context.section == "a" and "Interface\\GossipFrame\\AvailableQuestIcon"
                or "Interface\\GossipFrame\\ActiveQuestIcon")
            local shade = blocked and 0.6 or 1
            r.Title:SetTextColor(record == view.current and 1 or shade, record == view.current and 0.82 or shade,
                record == view.current and 0.3 or shade)
            r.Icon:SetDesaturated(blocked)
            for _, t in ipairs(r.Bars) do t:SetShown(record == view.current and record.status == "playing") end
            r.Play:SetShown(record ~= view.current and not blocked)
            r.Next:SetShown(canPlayNext)
            r:SetEnabled(not previewing)
            r.Play:SetEnabled(not previewing)
            r.Remove:SetEnabled(not previewing)
            r.Next:SetEnabled(not previewing and canPlayNext)
            r:Show()
            y = y + rowHeight
        end
        y = y + TILE_PADDING
    end
    for i = #view.groups + 1, #tiles do tiles[i]:Hide(); tiles[i].first, tiles[i].last = nil, nil end
    for i = #view.groups + 1, #headers do headers[i].motion = nil; headers[i]:Hide() end
    for i = used + 1, #rows do rows[i].record = nil; rows[i].motion = nil; rows[i]:Hide() end
    player.contentHeight = y
    local contentHeight = visibleContentHeight()
    local height = math.min(self:GetQuestQueueHeight() - SCROLL_TOP, contentHeight)
    -- Shrink the viewport and background alongside the last row's upward motion.
    if player.fading then
        player.fading.targetHeight, player.fading.width = math.min(self:GetQuestQueueHeight() - SCROLL_TOP, y) + SCROLL_TOP, width
        height = fadingHeight(player.fading) - SCROLL_TOP
    end
    anchorScroll(previous)
    layoutViewport(width, height, contentHeight)
end

function WV:GetQuestQueuePosition()
    local settings = self:GetHeadSettings()
    if not player then
        -- Reading options must not create or show an empty playlist.
        local saved = WowVoiceDB.queuePosition
        local ratio = settings.scale * self:GetQuestQueueScale()
        local x, y = 20, self:GetQuestQueueHeight()*ratio + 240
        if type(saved) == "table" and type(saved.x) == "number" and type(saved.y) == "number"
            and saved.x == saved.x and saved.y == saved.y and math.abs(saved.x) < 100000 and math.abs(saved.y) < 100000 then
            x, y = saved.x, saved.y
        elseif ChatFrame1 and ChatFrame1.GetCenter then
            local cx, cy = ChatFrame1:GetCenter()
            if cx and cy then
                local chatScale = ChatFrame1:GetEffectiveScale()/UIParent:GetEffectiveScale()
                x = (cx-ChatFrame1:GetWidth()/2)*chatScale
                y = (cy+ChatFrame1:GetHeight()/2)*chatScale + self:GetQuestQueueHeight()*ratio + 24
            end
        end
        return x-UIParent:GetWidth()/2, y-UIParent:GetHeight()/2
    end
    if not player:IsShown() then
        player:SetWidth(380)
        player:SetHeight(self:GetQuestQueueHeight())
        positionPlayer(WowVoiceTalkingHead)
    end
    local drag = player.dragging
    if type(drag) == "table" and drag.finalX then
        return drag.finalX - UIParent:GetWidth()/2, drag.finalY - UIParent:GetHeight()/2
    end
    local x, y = player:GetCenter()
    local ratio = player:GetEffectiveScale()/UIParent:GetEffectiveScale()
    return (x - player:GetWidth()/2)*ratio - UIParent:GetWidth()/2,
        (y + player:GetHeight()/2)*ratio - UIParent:GetHeight()/2
end

function WV:SetQuestQueuePosition(x, y)
    if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y
        or math.abs(x) == math.huge or math.abs(y) == math.huge then
        return false, "Введите числа в поля X и Y. Допускаются минус и дробная часть."
    end
    if WowVoiceDB.autoPlay == false then return false, "Включите автозапуск озвучки." end
    self:GetQuestQueuePosition()
    if not player then
        create()
        player:Hide()
        self:GetQuestQueuePosition()
    end
    finishDrag()
    local ratio = player:GetEffectiveScale()/UIParent:GetEffectiveScale()
    x = math.max(0, math.min(UIParent:GetWidth() - (player:GetWidth()-PANEL_RIGHT)*ratio,
        x + UIParent:GetWidth()/2))
    y = math.max(player:GetHeight()*ratio, math.min(UIParent:GetHeight(), y + UIParent:GetHeight()/2))
    WowVoiceDB.queuePosition = { x = x, y = y }
    positionPlayer(WowVoiceTalkingHead)
    if self.RefreshQuestQueuePositionOptions then self:RefreshQuestQueuePositionOptions(true) end
    return true
end

function WV:SetQuestQueueHeight(height)
    if type(height) ~= "number" or height ~= height or height < MIN_HEIGHT or height > MAX_HEIGHT then
        return false, "Введите высоту от 280 до 600."
    end
    WowVoiceDB.queueHeight = math.floor(height + 0.5)
    self:RefreshQuestQueuePlayer("instant")
    return true
end

function WV:PreviewQuestQueue(show, allowDisabled)
    if show then
        if not allowDisabled and WowVoiceDB and WowVoiceDB.autoPlay == false then return end
        self:GetHeadSettings()
        create()
        if not player.preview then
            player:Hide()
            player.preview = newPreview()
        end
        player.autoPreview, player.autoHideAt = nil, nil
        player:SetAlpha(1)
        player.editing = true
        self:SetPlaylistHeadEditing(true)
    elseif player and (player.editing or player.autoPreview) then
        finishDrag()
        local wasEditing = player.editing
        player.editing = nil
        player.autoPreview, player.autoHideAt = nil, nil
        if wasEditing then self:SetPlaylistHeadEditing(false) end
        player.preview = nil
        player:Hide()
        self:PrepareQuestQueuePortraits(Q.groups)
    else return end
    self:RefreshQuestQueuePlayer("instant")
end

-- Geometry previews share the samples, but never enable frame movement.
function WV:EnsureQuestQueuePreview()
    self:GetHeadSettings()
    create()
    if player.editing then return end
    if not player.autoPreview then
        player:Hide()
        player.preview = newPreview()
    end
    player.autoPreview, player.autoHideAt = true, nil
    player:SetAlpha(1)
    self:RefreshQuestQueuePlayer("instant")
end

function WV:FinishAutoQuestQueuePreview(delay)
    if player and player.autoPreview then player.autoHideAt = GetTime() + delay end
end

function WV:HideAutoQuestQueuePreview()
    if not (player and player.autoPreview) then return end
    player.autoPreview, player.autoHideAt, player.preview = nil, nil, nil
    player:Hide()
    self:PrepareQuestQueuePortraits(Q.groups)
    self:RefreshQuestQueuePlayer("instant")
end

function WV:SetQuestQueueScale(scale)
    if type(scale) ~= "number" or scale ~= scale or scale < 0.8 or scale > 1.2 then
        return false, "Введите масштаб от 80 до 120%."
    end
    finishDrag()
    if scale ~= self:GetQuestQueueScale() then
        -- Freeze the visible top-left corner before changing scale, including
        -- the automatic placement above chat that has no saved position yet.
        local x, y = self:GetQuestQueuePosition()
        WowVoiceDB.queuePosition = { x = x + UIParent:GetWidth()/2, y = y + UIParent:GetHeight()/2 }
    end
    WowVoiceDB.queueScale = scale
    self:RefreshQuestQueuePlayer("instant")
    return true
end

function WV:IsQuestQueuePreview()
    return player and player.editing == true or false
end

function WV:ResetQuestQueueLayout()
    finishDrag()
    WowVoiceDB.queuePosition, WowVoiceDB.queueHeight, WowVoiceDB.queueScale = nil, nil, nil
    self:RefreshQuestQueuePlayer("instant")
end

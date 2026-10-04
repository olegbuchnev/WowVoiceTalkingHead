local L = WowVoiceLocale
-- Quest giver appearance capture and WowVoice's talking-head panel.
-- SavedVariables stores data only, never frames or unit references.
local WV = _G.WowVoice
local pending, probe, request, head, anchor, active, transition
local scalePreview
local playlistHeadEditing
local function refreshEditBorder()
    if head and head.EditBorder then
        WV:UpdateFrameEditBorder(head.EditBorder)
        if playlistHeadEditing or (active and active.preview and not active.autoPreview) then head.EditBorder:Show()
        else head.EditBorder:Hide() end
    end
end
local scaleCapture, scaleSnapshot
local scaleSnapshotStatus = "not requested"
local textScalePreviewStatus = "not requested"
local updateScalePreviewVisual
local scaleTraces = {}
local function traceScaleEvent(key)
    local trace = scalePreview and scalePreview.trace
    if trace then trace[key] = (trace[key] or 0) + 1 end
end

local function sampleScaleModel()
    local trace = scalePreview and scalePreview.trace
    if not trace then return end
    local model = head.Model
    traceScaleEvent("frames")
    if not head:IsVisible() or not model:IsVisible() then traceScaleEvent("hidden") end
    if not model.portraitReady then traceScaleEvent("unready") end
    if model.GetPaused and not model:GetPaused() then traceScaleEvent("unpaused") end
    if model.GetDoBlend and model:GetDoBlend() then traceScaleEvent("blending") end
    local display = model:GetDisplayInfo()
    if display ~= trace.lastDisplay then traceScaleEvent("identity"); trace.lastDisplay = display end
end
-- PlayerModel geometry must follow our own panel's visibility and fade.
-- The panel is independent of UIParent and other addons' interface fades.
local function syncModelOpacity()
    if not head then return end
    if scalePreview and scalePreview.reparented then return end
    local model = head.Model
    local alpha = head.visualAlpha or 1
    if transition then alpha = math.max(0, 1 - math.max(0, GetTime() - transition.startedAt) / transition.duration) end
    if not active or not model.portraitReady or not head:IsVisible() then
        alpha = 0
    elseif model.SetModelAlpha then
        alpha = alpha * head.Portrait:GetEffectiveAlpha()
    end
    if alpha <= 0 then traceScaleEvent("alphaZero") end
    if model.SetModelAlpha then model:SetModelAlpha(alpha)
    else model:SetAlpha(alpha) end
end

local SECTION = { a = L["Описание задания"], p = L["Выполнение задания"], c = L["Завершение задания"] }
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_Note_01"
local DEFAULT_WIDTH, DEFAULT_HEIGHT = 570, 155
local PANEL_LEFT, PANEL_RIGHT = 15, 13
local PANEL_TOP, PANEL_BOTTOM = 15, 13
-- Retail TalkingHeadUI.xml fallback; managed layouts place it above action bars.
local DEFAULT_BOTTOM_OFFSET = 96
local TALKING_HEAD_TEXTURE = "Interface\\AddOns\\WowVoiceTalkingHead\\Media\\TalkingHeads"
local CLOSE_UP = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up"
local function createCloseArtwork(close)
    -- Native close-button fill and bevel.
    -- Keep the glyph separate so its texture cannot alter the panel shading.
    local art = CreateFrame("Frame", nil, close)
    art:SetAllPoints(close)
    art:EnableMouse(false)
    close.Stock = art
    local parts = {}
    local function piece(x, y, w, h, left, right, top, bottom, center)
        local texture = art:CreateTexture(nil, "BACKGROUND")
        texture:SetPoint("TOPLEFT", close, "TOPLEFT", 6 + x, -(7 + y - 2))
        texture:SetSize(w, h)
        texture:SetTexCoord(left, right, top, bottom)
        parts[#parts + 1] = { texture = texture, center = center }
    end
    piece(4, 6, 11, 10, 12/128, 68/128, 5/32, 17/32, true)
    piece(0, 2, 4, 4, 6/32, 10/32, 7/32, 11/32)
    piece(15, 2, 4, 4, 21/32, 25/32, 7/32, 11/32)
    piece(0, 16, 4, 4, 6/32, 10/32, 21/32, 25/32)
    piece(15, 16, 4, 4, 21/32, 25/32, 21/32, 25/32)
    piece(4, 2, 11, 4, 10/32, 21/32, 7/32, 11/32)
    piece(4, 16, 11, 4, 10/32, 21/32, 21/32, 25/32)
    piece(0, 6, 4, 10, 6/32, 10/32, 11/32, 21/32)
    piece(15, 6, 4, 10, 21/32, 25/32, 11/32, 21/32)
    art.Glyph = art:CreateTexture(nil, "ARTWORK")
    art.Glyph:SetTexture("Interface\\AddOns\\WowVoiceTalkingHead\\Media\\CloseGlyph")
    art.Glyph:SetTexCoord(2/512, 270/512, 2/512, 247/512)
    art.Glyph:SetSize(19 * 268/416, 18 * 245/398)
    close.Highlight = art:CreateTexture(nil, "OVERLAY")
    close.Highlight:SetTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    close.Highlight:SetBlendMode("ADD")
    close.Highlight:SetAllPoints(close)
    local function pressed(value)
        for _, part in ipairs(parts) do
            part.texture:SetTexture(part.center and
                ("Interface\\Buttons\\UI-Panel-Button-" .. (value and "Down" or "Up")) or CLOSE_UP)
            local shade = value and not part.center and 0.72 or 1
            part.texture:SetVertexColor(shade, shade, shade)
        end
        local shade = value and 0.72 or 1
        art.Glyph:SetVertexColor(shade, shade, shade)
        art.Glyph:ClearAllPoints()
        art.Glyph:SetPoint("TOPLEFT", close, "TOPLEFT",
            6 + 73 * 19/416 + (value and 1 or 0),
            -7 - 77 * 18/398 - (value and 1 or 0))
    end
    function close:ResetAppearance()
        self.Highlight:Hide()
        pressed(false)
    end
    close:SetScript("OnEnter", function() close.Highlight:Show() end)
    close:SetScript("OnLeave", function() close:ResetAppearance() end)
    close:SetScript("OnHide", function() close:ResetAppearance() end)
    close:SetScript("OnMouseDown", function() pressed(true) end)
    close:SetScript("OnMouseUp", function() pressed(false) end)
    close:ResetAppearance()
end

local function applyHeadAppearance()
    local close = head.Close
    close:SetSize(32, 32)
    close:SetPoint("TOPRIGHT", head, "TOPRIGHT", -12, -12)
    close:ResetAppearance()
    head.Name:SetTextColor(1, 0.82, 0.02, 1)
    head.Body:SetTextColor(1, 1, 1, 1)
    head.IconBorder:SetColorTexture(0.65, 0.53, 0.25, 1)
    head.Progress.Fill:SetColorTexture(0.85, 0.68, 0.3, 1)
end

local function message(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff" .. WV.displayName .. "|r: " .. text)
end

local function debugLog(text)
    if WowVoiceDB and WowVoiceDB.debug then message("[Portrait] " .. text) end
end

local function characterQuests()
    local guid = UnitGUID("player")
    if not (WowVoiceDB and guid) then return end
    WowVoiceDB.questSpeakers = WowVoiceDB.questSpeakers or {}
    WowVoiceDB.questSpeakers[guid] = WowVoiceDB.questSpeakers[guid] or {}
    return WowVoiceDB.questSpeakers[guid]
end

local function positive(value)
    return type(value) == "number" and value > 0
end

local function liveSpeaker()
    -- The target may be unrelated, especially for a quest started by an item.
    for _, unit in ipairs({ "npc", "questnpc" }) do
        local guid = UnitGUID(unit)
        if guid then
            local kind, _, _, _, _, id = strsplit("-", guid)
            if kind == "Creature" or kind == "Vehicle" then
                return unit, guid, tonumber(id), UnitName(unit)
            end
        end
    end
end

local function questStarterItem(questId)
    -- Require an exact questID match. Being a quest item does not by itself
    -- mean the item starts the currently displayed quest.
    local bags = C_Container
    if not (bags and type(bags.GetContainerItemQuestInfo) == "function"
        and type(bags.GetContainerItemInfo) == "function"
        and type(bags.GetContainerNumSlots) == "function") then
        debugLog("item quest=" .. questId .. ": API сумок недоступен")
        return
    end
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = 0, lastBag do
        for slot = 1, bags.GetContainerNumSlots(bag) do
            local quest = bags.GetContainerItemQuestInfo(bag, slot)
            if quest and quest.questID == questId then
                local item = bags.GetContainerItemInfo(bag, slot)
                if item and positive(item.itemID) then
                    debugLog("item quest=" .. questId .. " item=" .. item.itemID
                        .. " icon=" .. tostring(item.iconFileID) .. " name=" .. tostring(item.itemName))
                    return item
                end
            end
        end
    end
    debugLog("item quest=" .. questId .. ": совпадение в сумках не найдено")
end

local indexedSource, indexedSpeakers
local function addIndexedSpeaker(index, title, entry)
    if not positive(entry.q) then return end
    local previous = index[entry.q]
    local npcID = positive(entry.i) and entry.i or nil
    if previous == nil then
        index[entry.q] = { questId = entry.q, title = title,
            npcID = npcID, name = npcID and entry.n or nil }
    elseif previous and previous.npcID ~= npcID then index[entry.q] = false end
end
local function prepareSpeakerIndex()
    local source = _G.WowVoiceIndex
    if type(source) ~= "table" or source == indexedSource then return end
    local index = {}
    for title, entries in pairs(source) do
        for _, entry in ipairs(entries) do
            addIndexedSpeaker(index, title, entry)
            coroutine.yield()
        end
    end
    if source == _G.WowVoiceIndex then indexedSource, indexedSpeakers = source, index end
end
local function indexedSpeaker(questId)
    local source = _G.WowVoiceIndex
    if type(source) ~= "table" then return end
    if source == indexedSource then return indexedSpeakers[questId] or nil end
    -- A click before preparation completes still resolves immediately. Look up
    -- only this ID without allocating the full reverse index on the click path.
    local found = {}
    for title, entries in pairs(source) do
        for _, entry in ipairs(entries) do
            if entry.q == questId then addIndexedSpeaker(found, title, entry) end
        end
    end
    return found[questId] or nil
end

local function knownDisplay(quests, npcID)
    if not (quests and positive(npcID)) then return end
    local displayID
    for _, speaker in pairs(quests) do
        if speaker.npcID == npcID and not speaker.itemID and positive(speaker.displayID) then
            -- Some NPCs have multiple appearances. Reuse only an unambiguous one.
            if displayID and displayID ~= speaker.displayID then return end
            displayID = speaker.displayID
        end
    end
    return displayID
end

local function recoverQuestNPC(questId, record, quests, snapshot)
    if record and (positive(record.displayID) or positive(record.npcID)
        or positive(record.itemID) or positive(record.objectID)) then return record end
    local forever = _G.WowVoiceForeverSpeakers
    local indexed
    if type(forever) == "table" then indexed = forever[questId] end
    -- Explicit non-NPC or multiple starters must not fall back to a possibly
    -- different/partial Classic giver. Captured identity and exact items win.
    if indexed == false then return record end
    indexed = indexed or indexedSpeaker(questId)
    local database = _G.WowVoiceCatQuestSpeakers
    local catID = database and database.schemaVersion == 1 and database.givers[questId]
    local npc = catID and database.npcs[catID]
    local cat = positive(catID) and { npcID = catID,
        name = npc and type(npc[4]) == "string" and npc[4] or nil,
        displayID = npc and npc[3] } or nil
    if not (indexed and positive(indexed.npcID)) then indexed = cat end
    if not (indexed and positive(indexed.npcID)) then return record end
    local recovered = {}
    if record then for key, value in pairs(record) do recovered[key] = value end end
    recovered.questId = questId
    recovered.npcID, recovered.name = indexed.npcID, indexed.name
    recovered.title = recovered.title or indexed.title
    if snapshot then recovered.displayID = snapshot.displays[indexed.npcID] or nil
    else recovered.displayID = knownDisplay(quests, indexed.npcID) end
    if indexed == cat then
        recovered.name = recovered.name or cat.name
        recovered.displayID = recovered.displayID or (positive(cat.displayID) and cat.displayID or nil)
    end
    -- Inferred identity stays transient, so updated metadata can correct it.
    debugLog("recovered quest=" .. questId .. " npc=" .. indexed.npcID)
    return recovered
end

local function replaySpeaker(questId, record, quests, snapshot)
    if record and (positive(record.displayID) or positive(record.npcID)
        or positive(record.itemID) or positive(record.objectID)) then return record end
    local item
    if snapshot then item = snapshot.items[questId] else item = questStarterItem(questId) end
    if item then
        local recovered = {}
        if record then for key, value in pairs(record) do recovered[key] = value end end
        recovered.questId = questId
        recovered.itemID = item.itemID
        recovered.icon = positive(item.iconFileID) and item.iconFileID or nil
        recovered.name = item.itemName ~= "" and item.itemName or nil
        -- Keep an identified item after it is consumed or removed from the bags.
        if quests then quests[questId] = recovered end
        return recovered
    end
    return recoverQuestNPC(questId, record, quests, snapshot)
end

local warmModels, warmList, warmRevision = {}, {}, 0
local queuePortraitSpeakers, queuePortraitSignature = {}, ""
local function portraitKey(speaker)
    if not speaker or speaker.itemID or speaker.objectID then return end
    if positive(speaker.displayID) then return "Display" .. speaker.displayID end
    if positive(speaker.npcID) then return "NPC" .. speaker.npcID end
end
local function cachedPortraitDisplay(speaker)
    local job = warmModels[portraitKey(speaker)]
    return job and job.displayID
end

function WV:GetQuestQueuePortraitDisplay(speaker)
    if not speaker then return end
    if positive(speaker.displayID) then return speaker.displayID end
    local cached = cachedPortraitDisplay(speaker)
    if positive(cached) then return cached end
    -- The visible head may already have resolved an uncached NPC itself.
    if head and active and not active.preview and head.Model.portraitReady
        and portraitKey(speaker) and portraitKey(speaker) == portraitKey(active.context.speaker) then
        local display = head.Model:GetDisplayInfo()
        if positive(display) then return display end
    end
end
local function createWarmModel(key, job)
    -- Lifetime ownership prevents late callbacks from impersonating another NPC.
    local model = CreateFrame("PlayerModel", "WowVoiceWarmPortrait" .. key, UIParent)
    job.model = model
    model:Hide()
    model:SetSize(1, 1)
    model:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT")
    model:SetAlpha(0)
    if model.SetModelAlpha then model:SetModelAlpha(0) end
    model:EnableMouse(false)
    model:SetScript("OnModelLoaded", function()
        if not job.wanted then return end
        local display = model:GetDisplayInfo()
        if not positive(display) then return end
        job.displayID, job.loadingUntil = display, nil
        model:Hide()
        if head and active and not active.preview and not head.Model.portraitReady
            and portraitKey(active.context.speaker) == key then
            WV:RefreshTalkingHeadModel()
        end
    end)
end
local function warmPortraits()
    while true do
        local now, loading, candidate, pendingWork = GetTime(), 0, nil, false
        for _, job in ipairs(warmList) do
            if job.wanted and not job.displayID and not job.exhausted then
                if job.loadingUntil and now >= job.loadingUntil then
                    job.loadingUntil = nil
                    if job.model then job.model:Hide() end
                end
                if job.expires and now >= job.expires then
                    job.exhausted, job.retryAfter, job.loadingUntil = true, now + 60, nil
                    if job.model then job.model:Hide() end
                else
                    pendingWork = true
                    if job.loadingUntil then loading = loading + 1 end
                    if not job.loadingUntil and now >= (job.nextTry or 0) and (job.attempts or 0) < 8
                        and (not candidate or (job.nextTry or 0) < (candidate.nextTry or 0)) then
                        candidate = job
                    end
                end
            end
            coroutine.yield()
        end
        if not pendingWork then return end
        if candidate and loading < 2 and candidate.wanted and not candidate.displayID then
            local job = candidate
            if not job.model then createWarmModel(job.key, job); coroutine.yield() end
            if job.wanted and not job.displayID then
                local current = GetTime()
                job.expires = job.expires or (current + 20)
                job.attempts = (job.attempts or 0) + 1
                job.nextTry, job.loadingUntil = current + 2, current + 2
                job.model:Show()
                if positive(job.requestedDisplay) then
                    pcall(job.model.SetDisplayInfo, job.model, job.requestedDisplay)
                else pcall(job.model.SetCreature, job.model, job.npcID) end
                -- Only OnModelLoaded confirms readiness, never early metadata.
            end
        end
        coroutine.yield(0.25)
    end
end
local function scanQuestPortraits()
    local log = C_QuestLog or {}
    prepareSpeakerIndex()
    local revision = warmRevision
    local snapshot = { items = {}, displays = {} }
    local quests = characterQuests() or {}
    -- One incremental inventory pass for the entire journal, not one per quest.
    local bags = C_Container
    if bags and bags.GetContainerItemQuestInfo and bags.GetContainerItemInfo and bags.GetContainerNumSlots then
        for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
            for slot = 1, bags.GetContainerNumSlots(bag) do
                local quest = bags.GetContainerItemQuestInfo(bag, slot)
                if quest and positive(quest.questID) then
                    local item = bags.GetContainerItemInfo(bag, slot)
                    if item and positive(item.itemID) and not snapshot.items[quest.questID] then
                        snapshot.items[quest.questID] = item
                    end
                end
                coroutine.yield()
                if revision ~= warmRevision then return end
            end
        end
    end
    -- Build the unambiguous display cache once, including old saved quests.
    for _, speaker in pairs(quests) do
        if positive(speaker.npcID) and not speaker.itemID and positive(speaker.displayID) then
            local old = snapshot.displays[speaker.npcID]
            if old == nil then snapshot.displays[speaker.npcID] = speaker.displayID
            elseif old ~= speaker.displayID then snapshot.displays[speaker.npcID] = false end
        end
        coroutine.yield()
        if revision ~= warmRevision then return end
    end
    local wanted = {}
    local count = log.GetNumQuestLogEntries and log.GetInfo and log.GetNumQuestLogEntries() or 0
    for index = 1, count do
        if revision ~= warmRevision then return end
        local info = log.GetInfo(index)
        if info and not info.isHeader and WV:CanPresentQuest(info.questID) then
            local speaker = replaySpeaker(info.questID, quests[info.questID], quests, snapshot)
            local key = portraitKey(speaker)
            if key then wanted[key] = speaker end
        end
        coroutine.yield()
    end
    if revision ~= warmRevision then return end
    -- Queue speakers include simulated quests and completed quests no longer
    -- present in the real journal. Resolve them through the same bounded worker.
    for key, speaker in pairs(queuePortraitSpeakers) do wanted[key] = speaker end
    -- Commit only a complete, current snapshot; live playback has priority.
    for _, job in ipairs(warmList) do
        job.wanted = wanted[job.key] ~= nil
        if not job.wanted then
            job.loadingUntil, job.expires = nil, nil
            if job.model then job.model:Hide() end
        end
    end
    warmList = {}
    for key, speaker in pairs(wanted) do
        local job = warmModels[key]
        if not job then
            job = { key = key, npcID = speaker.npcID, requestedDisplay = speaker.displayID }
            warmModels[key] = job
        end
        job.wanted = true
        if job.exhausted and GetTime() >= job.retryAfter then
            job.exhausted, job.expires, job.attempts = nil, nil, nil
        end
        warmList[#warmList + 1] = job
    end
    table.sort(warmList, function(a, b) return a.key < b.key end)
    -- Also request one rerun if the old worker is about to finish a stale list.
    WV.Work:Queue("portrait-models", warmPortraits, 0, true)
end
local function queueQuestPortraits()
    warmRevision = warmRevision + 1
    WV.Work:Queue("portrait-scan", scanQuestPortraits, 0.5, true)
end

function WV:PrepareQuestQueuePortraits(groups)
    local wanted, keys = {}, {}
    for _, group in ipairs(groups) do
        local speaker = group.speaker
        local key = portraitKey(speaker)
        if key and not wanted[key] then wanted[key] = speaker; keys[#keys + 1] = key end
    end
    table.sort(keys)
    local signature = table.concat(keys, ":")
    if signature == queuePortraitSignature then return end
    queuePortraitSpeakers, queuePortraitSignature = wanted, signature
    queueQuestPortraits()
end

local function resetProbe()
    request = nil
    if probe then probe:ClearModel(); probe:Hide() end
end

local function finishCapture()
    if not request then return end
    local displayID = probe:GetDisplayInfo()
    if not positive(displayID) then return end
    -- Each request owns a separate record. A late load updates that record
    -- without restoring a removed or completed quest to SavedVariables.
    local record = request.record
    record.displayID = displayID
    debugLog("captured quest=" .. record.questId .. " npc=" .. tostring(record.npcID)
        .. " display=" .. displayID)
    resetProbe()
    if active and active.context.speaker == record then WV:RefreshTalkingHeadModel() end
end

local function captureModel(record, unit)
    if not probe then
        probe = CreateFrame("PlayerModel", "WowVoicePortraitProbe", UIParent)
        probe:SetSize(1, 1)
        probe:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT")
        probe:SetAlpha(0)
        if probe.SetModelAlpha then probe:SetModelAlpha(0) end
        probe:EnableMouse(false)
        probe:SetScript("OnModelLoaded", finishCapture)
        probe:SetScript("OnUpdate", function()
            if request and GetTime() >= request.expires then
                debugLog("displayID ещё не загружен; сохранён NPC ID для quest=" .. request.record.questId)
                resetProbe()
            end
        end)
    end
    resetProbe()
    request = { record = record, expires = GetTime() + 5 }
    probe:Show()
    probe:SetUnit(unit)
    finishCapture() -- The model may already be cached by the client.
end

function WV:CaptureQuestSpeaker(questId, section, title, text)
    local unit, guid, npcID, name = liveSpeaker()
    local record = { questId = questId, title = title, npcID = npcID, name = name }
    if not unit then
        for _, token in ipairs({ "npc", "questnpc" }) do
            local objectGUID = UnitGUID(token)
            if objectGUID then
                local kind, _, _, _, _, id = strsplit("-", objectGUID)
                if kind == "GameObject" then
                    record.objectID = tonumber(id)
                    break
                end
            end
        end
    end
    if section == "a" then
        if not unit and not record.objectID then
            local item = questStarterItem(questId)
            if item then
                record.itemID = item.itemID
                record.icon = positive(item.iconFileID) and item.iconFileID or nil
                record.name = item.itemName ~= "" and item.itemName or nil
            end
        end
        record.description = text
        pending = record
    end
    -- Do not carry an unfinished capture from the previous NPC to the next.
    resetProbe()
    if unit then captureModel(record, unit) end
    debugLog("view quest=" .. questId .. " section=" .. section .. " guid=" .. tostring(guid))
    -- Gossip-triggered quest details can arrive without npc/questnpc. Resolve
    -- the description's giver just as journal replay does. Keep pending as the
    -- original capture: inferred metadata must not become a permanent identity.
    -- Progress/completion belong to the receiver, so never infer their giver.
    local speaker = section == "a" and recoverQuestNPC(questId, record, characterQuests()) or record
    return { questId = questId, section = section, title = title, text = text, speaker = speaker }
end

function WV:GetReplaySpeaker(questId)
    local quests = characterQuests()
    local record = replaySpeaker(questId, quests and quests[questId], quests)
    local title = record and record.title
    if not title and C_QuestLog and C_QuestLog.GetTitleForQuestID then
        title = C_QuestLog.GetTitleForQuestID(questId)
    end
    local text = record and record.description
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID
        and type(GetQuestLogQuestText) == "function" then
        local index = C_QuestLog.GetLogIndexForQuestID(questId)
        -- nil means the selected quest, whose text may belong to another ID.
        if positive(index) then
            local current = GetQuestLogQuestText(index)
            if type(current) == "string" and current:find("%S") then text = current end
        end
    end
    return { questId = questId, section = "a", title = title, text = text, speaker = record }
end

local headAnchorPoints = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true,
    CENTER = true, RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }

local function pointOffset(point, width, height)
    return (point:find("LEFT") and -width / 2 or point:find("RIGHT") and width / 2 or 0),
        (point:find("BOTTOM") and -height / 2 or point:find("TOP") and height / 2 or 0)
end

function WV:GetHeadAnchor()
    local point = WowVoiceDB and WowVoiceDB.headAnchor
    if headAnchorPoints[point] then return point end
    local p = WowVoiceDB and WowVoiceDB.headPosition
    return p and headAnchorPoints[p[1]] and p[1] or "BOTTOM"
end

local function restorePosition()
    if not anchor then return end
    local p = WowVoiceDB and WowVoiceDB.headPosition
    anchor:ClearAllPoints()
    if p and p[1] and p[2] and p[3] and p[4] then
        anchor:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        -- Follow Blizzard's bottom action-bar boundary without joining its alert stack.
        local bottomContainer = _G.BottomManagedFrameContainer
        local bx, by
        if bottomContainer then bx, by = bottomContainer:GetCenter() end
        -- Some clients expose this container before it has a screen rectangle.
        -- Anchoring to it then leaves our entire panel without coordinates.
        if type(bx) == "number" and type(by) == "number" then
            anchor:SetPoint("BOTTOM", bottomContainer, "BOTTOM", 0, 0)
        else
            anchor:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, DEFAULT_BOTTOM_OFFSET)
        end
    end
end

local function centerPosition()
    local x, y = anchor:GetCenter()
    local cx, cy = UIParent:GetCenter()
    if x and y and cx and cy then return x - cx, y - cy end
    restorePosition()
    x, y = anchor:GetCenter()
    if x and y and cx and cy then return x - cx, y - cy end
    -- Layout may still be pending while the options page is opening. Derive
    -- the saved position without overwriting it with an arbitrary center.
    local p = WowVoiceDB and WowVoiceDB.headPosition
    if p and p[1] and p[2] and p[3] and p[4] then
        local rx, ry = pointOffset(p[2], UIParent:GetWidth(), UIParent:GetHeight())
        local ax, ay = pointOffset(p[1], anchor:GetWidth(), anchor:GetHeight())
        return rx - ax + p[3], ry - ay + p[4]
    end
    return 0, -UIParent:GetHeight() / 2 + DEFAULT_BOTTOM_OFFSET + anchor:GetHeight() / 2
end

local function sizeHeadAnchor(width, height, scale)
    -- Transparent margins may leave the screen; the visible panel may not.
    anchor.headClampLeft = PANEL_LEFT * scale
    anchor.headClampRight = PANEL_RIGHT * scale
    anchor.headClampTop = PANEL_TOP * scale
    anchor:SetClampRectInsets(anchor.headClampLeft, -anchor.headClampRight, -anchor.headClampTop, 0)
    anchor:SetSize(width * scale, height * scale)
end

local function clampCenterPosition(x, y)
    local maxX = math.max(0, (UIParent:GetWidth() - anchor:GetWidth()) / 2)
    local maxY = math.max(0, (UIParent:GetHeight() - anchor:GetHeight()) / 2)
    return math.max(-maxX - (anchor.headClampLeft or 0), math.min(maxX + (anchor.headClampRight or 0), x)),
        math.max(-maxY, math.min(maxY + (anchor.headClampTop or 0), y))
end

local function panelPointOffset(point)
    -- UI coordinates and scale pivots follow the yellow outline. Saved frame
    -- anchors retain their original geometry so existing placements do not move.
    local scale = (anchor.headClampTop or 0) / PANEL_TOP
    local left, right = PANEL_LEFT * scale, PANEL_RIGHT * scale
    local top, bottom = PANEL_TOP * scale, PANEL_BOTTOM * scale
    local x, y = pointOffset(point, anchor:GetWidth() - left - right, anchor:GetHeight() - top - bottom)
    return x + (left - right)/2, y + (bottom - top)/2
end

function WV:GetTalkingHeadPanelBounds()
    if not head or not head:IsShown() then return end
    local x, y = anchor:GetCenter()
    if not x or not y then return end
    local ratio = anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local scale = head:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return x * ratio - head:GetWidth() * scale / 2 + PANEL_LEFT * scale,
        y * ratio + head:GetHeight() * scale / 2 - PANEL_TOP * scale,
        x * ratio + head:GetWidth() * scale / 2 - PANEL_RIGHT * scale,
        y * ratio - head:GetHeight() * scale / 2 + PANEL_BOTTOM * scale
end

local function setPosition(x, y, temporary)
    -- Coordinates in UI units relative to the center of the screen.
    x, y = clampCenterPosition(x, y)
    -- Retain legacy center coordinates until a point has been explicitly chosen.
    local point = headAnchorPoints[WowVoiceDB.headAnchor] and WowVoiceDB.headAnchor or "CENTER"
    local ax, ay = pointOffset(point, anchor:GetWidth(), anchor:GetHeight())
    local rx, ry = pointOffset(point, UIParent:GetWidth(), UIParent:GetHeight())
    x, y = x + ax - rx, y + ay - ry
    if not temporary then WowVoiceDB.headPosition = { point, point, x, y } end
    anchor:ClearAllPoints()
    anchor:SetPoint(point, UIParent, point, x, y)
end

-- Approximate speech cost: count UTF-8 characters, not individual bytes.
-- Punctuation adds pauses. These are not phoneme-level timestamps.
local function speechWeight(word)
    word = word:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local _, letters = word:gsub("[^\128-\191]", "")
    local pause = 0
    if word:find("[.!?]") or word:find("…", 1, true) then pause = 6
    elseif word:find("[,;:]") then pause = 3 end
    return math.max(1, letters) + 1 + pause
end

local function buildScrollPlan(lineHeight, visibleLines)
    head.scrollPlan = {}
    if head.textRange <= 0 or not (active and positive(active.duration)) then return end
    local text = head.Body:GetText() or ""
    local words, total, previousEnd = {}, 0, 1
    for start, word, finish in text:gmatch("()(%S+)()") do
        local _, breaks = text:sub(previousEnd, start - 1):gsub("\n", "")
        total = total + math.min(2, breaks) * 4
        local weight = speechWeight(word)
        words[#words + 1] = { finish = finish - 1, before = total, weight = weight }
        total, previousEnd = total + weight, finish
    end
    if total == 0 then return end

    local measure = head.TextMeasure
    -- Binary search over prefix heights accounts for actual font wrapping.
    -- Measure only on start or resize, not on every frame.
    local function prefixHeight(index)
        local word = words[index]
        if not word.height then
            measure:SetText(text:sub(1, word.finish))
            word.height = measure:GetStringHeight()
        end
        return word.height
    end
    local function weightAt(offset)
        local low, high = 1, #words
        while low < high do
            local mid = math.floor((low + high) / 2)
            if prefixHeight(mid) <= offset + 0.01 then low = mid + 1
            else high = mid end
        end
        local word = words[low]
        local previousHeight = low > 1 and prefixHeight(low - 1) or 0
        local span = prefixHeight(low) - previousHeight
        -- A very long word can wrap across multiple lines without spaces.
        local within = span > lineHeight * 1.5
            and math.max(0, math.min(1, (offset - previousHeight) / span)) or 0
        return word.before + word.weight * within
    end

    local overlap = math.min(2, math.max(0, visibleLines - 1))
    local step = math.max(1, visibleLines - overlap) * lineHeight
    local offset, previousFinish = 0, 0
    while offset < head.textRange - 0.01 do
        local nextOffset = math.min(head.textRange, offset + step)
        -- Finish the transition before reading the bottom two visible lines.
        -- The final shift may be shorter than a full step. Do not start it early
        -- just because little text remains outside the viewport. After this
        -- transition, keep the final unread lines stationary.
        local finish = math.max(previousFinish, active.duration * weightAt(offset + step) / total)
        local movement = math.min(0.65, (finish - previousFinish) * 0.25)
        head.scrollPlan[#head.scrollPlan + 1] = {
            from = offset, to = nextOffset, start = finish - movement, finish = finish,
        }
        offset, previousFinish = nextOffset, finish
    end
    measure:SetText("")
end

local function updatePlaybackText()
    if not (head and active) or scalePreview then return end
    local elapsed = math.max(0, WV.PlaybackTime() - active.startedAt)
    if active.preview and elapsed >= active.duration then
        active.startedAt = WV.PlaybackTime()
        active.endsAt = active.startedAt + active.duration
        elapsed = 0
    end
    local length = active.endsAt - active.startedAt
    local progress = length > 0 and math.min(1, elapsed / length) or 1
    head.Progress:SetValue(progress)
    local offset = 0
    for _, move in ipairs(head.scrollPlan or {}) do
        if elapsed < move.start then break end
        if elapsed >= move.finish then
            offset = move.to
        else
            local t = (elapsed - move.start) / (move.finish - move.start)
            t = t * t * (3 - 2 * t) -- Ease in and out of the short scroll transition
            offset = move.from + (move.to - move.from) * t
            break
        end
    end
    head.TextScroll:SetVerticalScroll(offset)
end

local function disablePortraitBlend(model)
    -- SetUnit/SetDisplayInfo reuse the same native PlayerModel. Do not carry
    -- implicit model transitions from an NPC into the next player preview.
    if model.SetDoBlend then model:SetDoBlend(false) end
end

local function updatePortraitCamera(model)
    traceScaleEvent("fullCamera")
    -- Let PlayerModel compute its portrait camera. Selecting an embedded M2
    -- camera with SetCamera(0) can leave a model in its authored full-body view.
    disablePortraitBlend(model)
    local profile, key, fileID = WV:GetPortraitCameraProfile(model)
    model.cameraProfile, model.cameraFileID = key, fileID
    model:SetPortraitZoom(1)
    model:SetCamDistanceScale(profile.distance)
    model:SetPosition(0, profile.y, profile.z)
    model:SetRotation(0)
    model:RefreshCamera()
end

local function startTalkingAnimation(model)
    if model.SetPaused then model:SetPaused(false) end
    model.talkAnimation = model:HasAnimation(60) and 60 or 0
    model:SetAnimation(model.talkAnimation)
    model.animationNextCheck = GetTime() + 0.5
end

local function updateTalkingAnimation()
    if not (head and active) or active.closing or scalePreview then return end
    local model = head.Model
    if not model.portraitReady then return end
    -- Native model loading can overwrite SetAnimation from OnModelLoaded.
    -- Reapply once outside the callback, including for a restored playlist.
    if model.animationPending then
        model.animationPending = nil
        startTalkingAnimation(model)
    elseif model.talkAnimation ~= 60 and GetTime() >= (model.animationNextCheck or 0) then
        -- Animation data may arrive after the visible model. Do not keep the
        -- initial idle fallback forever, or restart an already talking model.
        model.animationNextCheck = GetTime() + 0.5
        if model:HasAnimation(60) then startTalkingAnimation(model) end
    end
    if model.GetPaused and model.SetPaused and model:GetPaused() then model:SetPaused(false) end
end

local function finishTalkingModel(model)
    traceScaleEvent("loaded")
    if not active or active.closing then return end
    disablePortraitBlend(model)
    if scalePreview then scalePreview.modelLoaded = true; return end
    local speaker = active.context.speaker
    -- Late notifications must not cover an item or unknown speaker's icon.
    if not active.preview and (not portraitKey(speaker)
        or not positive(model:GetDisplayInfo())) then return end
    -- A later load can reset the camera even if a previous model was ready.
    -- Reapply it for every real OnModelLoaded notification.
    model.portraitReady = true
    updatePortraitCamera(model)
    startTalkingAnimation(model)
    model.animationPending = true
    model:SetAlpha(1)
    syncModelOpacity()
    head.Icon:Hide()
    head.IconBorder:Hide()
end

local function tryTalkingModel()
    if not (head and active) or active.closing or active.preview or head.Model.portraitReady then return end
    local model, speaker = head.Model, active.context.speaker
    if not portraitKey(speaker) then return end
    local now = GetTime()
    if now < (active.modelNextTry or 0) or now > (active.modelDeadline or 0) then return end
    active.modelNextTry = now + 1
    disablePortraitBlend(model)
    local display = speaker.displayID or cachedPortraitDisplay(speaker)
    if positive(display) then
        local ok, loaded = pcall(model.SetDisplayInfo, model, display)
        if (not ok or loaded == false) and positive(speaker.npcID) then
            pcall(model.SetCreature, model, speaker.npcID)
        end
    elseif positive(speaker.npcID) then
        pcall(model.SetCreature, model, speaker.npcID)
    end
    disablePortraitBlend(model)
    -- A numeric display ID is not proof that render resources are ready.
    -- Keep the placeholder until OnModelLoaded configures the camera.
end

function WV:GetHeadScale()
    local scale = tonumber(WowVoiceDB and WowVoiceDB.headScale) or 1
    if scale ~= scale or math.abs(scale) == math.huge then scale = 1 end
    return math.floor(math.max(0.5, math.min(1.5, scale)) * 100 + 0.5) / 100
end

local function refreshHeadTextFonts()
    -- Return to native glyph rendering at the final effective scale, preserving
    -- the client's font files, logical sizes and outline flags.
    for _, text in ipairs({ head.Name, head.Body, head.TextMeasure }) do
        text:SetFont(text:GetFont())
    end
end

local function layoutHead()
    local width = (WowVoiceDB and WowVoiceDB.headWidth) or DEFAULT_WIDTH
    local height = (WowVoiceDB and WowVoiceDB.headHeight) or DEFAULT_HEIGHT
    local scale = WV:GetHeadScale()
    head:SetScale(scale)
    if head.EditBorder then WV:UpdateFrameEditBorder(head.EditBorder) end
    refreshHeadTextFonts()
    local textLeft, textRight = 152, 42
    -- Retail composition: portrait on the left, name above
    -- the text on the right, and space reserved for the close button.
    head.Name:SetWidth(math.max(1, width - textLeft - textRight))
    head.Name:SetHeight(0)
    local _, titleSize = head.Name:GetFont()
    local nameHeight = math.max(titleSize, head.Name:GetStringHeight())
    local contentTop = 25 + nameHeight + 3
    height = math.max(height, contentTop + 42)
    local size = math.min(115, height - 40)
    local portraitLeft, portraitTop = 21, 21
    head.Name:ClearAllPoints()
    head.Name:SetPoint("TOPLEFT", head, "TOPLEFT", textLeft, -25)
    head.Name:SetHeight(nameHeight)
    head:SetSize(width, height)
    -- Only the panel receives the saved scale; the anchor uses UIParent units.
    sizeHeadAnchor(width, height, scale)
    local textWidth = width - textLeft - textRight
    -- The portrait camera expects a roughly square viewport. Panel height
    -- must not turn it into a narrow vertical strip or crop the head.
    local top = portraitTop
    local model = head.Model
    local resized = model:GetWidth() ~= size or model:GetHeight() ~= size
    model:ClearAllPoints()
    model:SetPoint("TOPLEFT", head, "TOPLEFT", portraitLeft, -top)
    model:SetSize(size, size)
    head.PortraitBackground:ClearAllPoints()
    head.PortraitBackground:SetPoint("TOPLEFT", model, "TOPLEFT")
    head.PortraitBackground:SetSize(size, size)
    head.PortraitOverlay:ClearAllPoints()
    head.PortraitOverlay:SetPoint("CENTER", model, "CENTER")
    head.PortraitOverlay:SetSize(size * 145 / 115, size * 145 / 115)
    if resized and model.portraitReady then updatePortraitCamera(model) end
    head.Icon:ClearAllPoints()
    head.Icon:SetPoint("CENTER", head.Model, "CENTER")
    local iconSize = math.min(64, math.max(1, size - 8))
    head.Icon:SetSize(iconSize, iconSize)
    head.IconBorder:SetSize(iconSize + 2, iconSize + 2)
    head.Progress:SetWidth(width - PANEL_LEFT - PANEL_RIGHT)
    head.Progress:SetValue(head.Progress:GetValue())
    head.TextContent:SetWidth(textWidth)
    head.Body:SetWidth(textWidth)
    local measure = head.TextMeasure
    measure:SetFont(head.Body:GetFont())
    measure:SetSpacing(head.Body:GetSpacing())
    measure:SetWidth(textWidth)
    measure:SetText(L["А"])
    local singleHeight = measure:GetStringHeight()
    measure:SetText(L["А\nА"])
    local lineHeight = math.max(1, measure:GetStringHeight() - singleHeight)
    local textSpace = height - contentTop - 14
    local visibleLines = math.max(1, math.floor((textSpace - singleHeight) / lineHeight + 0.001) + 1)
    -- Avoid clipping the bottom line, including in the final text block.
    head.TextScroll:ClearAllPoints()
    head.TextScroll:SetPoint("TOPLEFT", head, "TOPLEFT", textLeft, -contentTop)
    head.TextScroll:SetSize(textWidth, singleHeight + (visibleLines - 1) * lineHeight)
    measure:SetText("")
    local textHeight = math.max(head.TextScroll:GetHeight(), head.Body:GetStringHeight())
    head.TextContent:SetHeight(textHeight)
    head.TextScroll:UpdateScrollChildRect()
    head.textRange = math.max(0, textHeight - head.TextScroll:GetHeight())
    buildScrollPlan(lineHeight, visibleLines)
    updatePlaybackText()
end

-- Keep model ancestors opaque: PlayerModel's rendered geometry needs its own
-- opacity, rather than relying on a parent frame fade. Apply the same value to
-- every visible component, without multiplying it again through its parents.
local function setHeadOpacity(alpha)
    head.visualAlpha = alpha
    if scalePreview and scalePreview.snapshot then
        scaleSnapshot:SetAlpha(alpha / scalePreview.alpha)
    end
    head.Background:SetAlpha(alpha)
    head.PortraitBackground:SetAlpha(alpha)
    head.PortraitOverlay:SetAlpha(alpha)
    head.Icon:SetAlpha(alpha)
    head.IconBorder:SetAlpha(alpha)
    head.Name:SetAlpha(alpha)
    head.TextScroll:SetAlpha(alpha)
    head.Progress:SetAlpha(alpha)
    head.Close:SetAlpha(alpha)
    syncModelOpacity()
end

-- Only the end of playback fades. A frame-driven deadline cannot close a newer
-- line or preview after the current line has been replaced.
local function updateHeadTransition()
    if not (head and transition) then return end
    local elapsed = math.max(0, GetTime() - transition.startedAt)
    setHeadOpacity(math.max(0, 1 - elapsed / transition.duration))
    if GetTime() >= transition.startedAt + transition.duration then WV:StopTalkingHead() end
end

-- Match the normal UI's coordinate scale without inheriting its visibility.
local function refreshHeadScale()
    if not anchor then return end
    anchor:SetScale(UIParent:GetEffectiveScale())
    if head and head.EditBorder then WV:UpdateFrameEditBorder(head.EditBorder) end
    if head and head.Model.portraitReady then updatePortraitCamera(head.Model) end
end

local scaleEvents = CreateFrame("Frame", "WowVoiceHeadScaleEvents")
scaleEvents:RegisterEvent("PLAYER_LOGIN")
scaleEvents:RegisterEvent("UI_SCALE_CHANGED")
scaleEvents:RegisterEvent("DISPLAY_SIZE_CHANGED")
scaleEvents:SetScript("OnEvent", refreshHeadScale)

local function updateHead()
    sampleScaleModel()
    if scalePreview and scalePreview.visualDirty then updateScalePreviewVisual() end
    if not anchor:GetCenter() then restorePosition() end
    if head.draggingPosition and WV.RefreshHeadPositionOptions then WV:RefreshHeadPositionOptions() end
    if active and active.autoPreview and active.autoHideAt and GetTime() >= active.autoHideAt
        and not scalePreview and not head.draggingPosition then
        active.autoHideAt = nil
        WV:FinishTalkingHead()
    end
    if not scalePreview then tryTalkingModel(); updateTalkingAnimation() end
    if active and not active.closing then updatePlaybackText() end
    updateHeadTransition()
    syncModelOpacity()
end

local function createHead()
    if head then return end
    anchor = CreateFrame("Frame", "WowVoiceTalkingHeadAnchor")
    anchor:SetScale(UIParent:GetEffectiveScale())
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    head = CreateFrame("Button", "WowVoiceTalkingHead", anchor)
    head:SetPoint("CENTER", anchor, "CENTER")
    head:SetSize(DEFAULT_WIDTH, DEFAULT_HEIGHT)
    -- Keep the entire panel above dialogue/tutorial banners, including after reload.
    head:SetFrameStrata("FULLSCREEN_DIALOG")
    head:SetFrameLevel(200)
    head:EnableMouse(false)
    head:RegisterForDrag("LeftButton")
    head:RegisterForClicks("RightButtonUp")
    head:SetScript("OnDragStart", function()
        if playlistHeadEditing or (active and active.preview and not active.autoPreview) then
            if active and active.autoPreview then WV:EnsureHeadPreview() end
            local x, y = centerPosition()
            local movement = { x = x, y = y, scale = anchor:GetEffectiveScale() }
            if GetCursorPosition then movement.cursorX, movement.cursorY = GetCursorPosition() end
            head.draggingPosition = movement
            anchor:StartMoving()
            if WV.RefreshHeadPositionOptions then WV:RefreshHeadPositionOptions() end
        end
    end)
    head:SetScript("OnDragStop", function()
        head.draggingPosition = nil
        anchor:StopMovingOrSizing()
        if playlistHeadEditing or (active and active.preview and not active.autoPreview) then
            setPosition(centerPosition())
            if WV.RefreshHeadOptions then WV:RefreshHeadOptions() end
            WV:FinishAutoHeadPreview(2)
        end
    end)

    -- Use the original TalkingHeads sheet, bundled for clients without its
    -- atlas entries. Keep the transparent margins and soft background intact.
    local function retailTexture(parent, layer, left, top, width, height)
        local texture = parent:CreateTexture(nil, layer)
        texture:SetTexture(TALKING_HEAD_TEXTURE)
        texture:SetTexCoord(left / 1024, (left + width) / 1024, top / 1024, (top + height) / 1024)
        return texture
    end
    -- Separate visual layers preserve theme opacity and model readiness while
    -- their contents fade together at the end of playback.
    head.Background = CreateFrame("Frame", nil, head)
    head.Background:SetAllPoints(head)
    head.Background:SetFrameLevel(head:GetFrameLevel())
    head.Background:EnableMouse(false)
    head.Portrait = CreateFrame("Frame", nil, head)
    head.Portrait:SetAllPoints(head)
    head.Portrait:EnableMouse(false)
    head.RetailBackground = retailTexture(head.Background, "BACKGROUND", 0, 0, 570, 155)
    head.RetailBackground:SetAllPoints(head)
    head.PortraitBackground = retailTexture(head.Portrait, "BACKGROUND", 572, 314, 117, 117)

    local border = head.Portrait:CreateTexture(nil, "BACKGROUND")
    head.IconBorder = border
    local icon = head.Portrait:CreateTexture(nil, "ARTWORK")
    icon:SetSize(64, 64)
    icon:SetPoint("LEFT", head, "LEFT", 30, 0)
    icon:SetTexture(FALLBACK_ICON)
    head.Icon = icon
    border:SetPoint("CENTER", icon, "CENTER")

    local model = CreateFrame("PlayerModel", nil, head.Portrait)
    model:SetSize(120, 124)
    model:SetPoint("TOPLEFT", head, "TOPLEFT", 6, -8)
    model:EnableMouse(false)
    head.Model = model
    -- A sibling above PlayerModel keeps the ornament visible for both NPCs
    -- and item icons, including while the model is loading or transparent.
    head.PortraitOverlay = CreateFrame("Frame", nil, head.Portrait)
    head.PortraitOverlay:SetFrameLevel(model:GetFrameLevel() + 1)
    head.PortraitOverlay:EnableMouse(false)
    local portraitFrame = retailTexture(head.PortraitOverlay, "OVERLAY", 572, 0, 145, 145)
    portraitFrame:SetAllPoints(head.PortraitOverlay)
    model:SetScript("OnShow", function(self)
        traceScaleEvent("shown")
        -- PlayerModel can reset its camera when a hidden parent is shown again.
        if not scalePreview and active and self.portraitReady then
            updatePortraitCamera(self)
            if not active.closing then self.animationPending = true end
        end
        syncModelOpacity()
    end)
    model:SetScript("OnHide", function() traceScaleEvent("hiddenEvent") end)
    head:SetScript("OnShow", syncModelOpacity)
    head:SetScript("OnHide", syncModelOpacity)
    model:SetScript("OnModelLoaded", finishTalkingModel)
    model:SetScript("OnAnimFinished", function(self)
        if not scalePreview and active and not active.closing and self.talkAnimation then
            self.animationPending = true
        end
    end)

    local function label(font, y, height)
        local text = head:CreateFontString(nil, "OVERLAY", font)
        text:SetPoint("TOPLEFT", head, "TOPLEFT", 140, y)
        text:SetSize(312, height)
        text:SetJustifyH("LEFT")
        return text
    end
    -- Inherit quest font sizes as well as their localized font families.
    head.NameLayer = CreateFrame("Frame", nil, head)
    head.NameLayer:SetAllPoints(head)
    head.NameLayer:EnableMouse(false)
    head.Name = head.NameLayer:CreateFontString(nil, "OVERLAY", "QuestTitleFont")
    head.Name:SetJustifyH("LEFT")
    head.Name:SetJustifyV("TOP")
    head.Name:SetWordWrap(true)
    -- Hide auxiliary labels so they do not consume quest text space.
    head.Title = label("GameFontHighlight", -42, 32)
    head.Section = label("GameFontDisableSmall", -202, 16)
    head.Title:Hide()
    head.Section:Hide()

    local scroll = CreateFrame("ScrollFrame", nil, head)
    scroll:SetPoint("TOPLEFT", head, "TOPLEFT", 140, -10)
    scroll:SetSize(312, 136)
    scroll:EnableMouse(false)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(312, 136)
    content:EnableMouse(false)
    scroll:SetScrollChild(content)
    local body = content:CreateFontString(nil, "ARTWORK", "QuestFont")
    body:SetPoint("TOPLEFT", content, "TOPLEFT")
    body:SetWidth(312)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetWordWrap(true)
    head.TextScroll, head.TextContent, head.Body = scroll, content, body
    head.TextMeasure = head:CreateFontString(nil, "ARTWORK", "QuestFont")
    head.TextMeasure:SetWordWrap(true)
    head.TextMeasure:Hide()
    head.textRange = 0
    head.Progress = CreateFrame("Frame", nil, head)
    head.Progress:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", PANEL_LEFT, 2)
    head.Progress:SetSize(312, 2)
    head.Progress.Fill = head.Progress:CreateTexture(nil, "ARTWORK")
    head.Progress.Fill:SetPoint("BOTTOMLEFT", head.Progress, "BOTTOMLEFT")
    head.Progress.Fill:SetSize(1, 2)
    function head.Progress:SetValue(value)
        self.value = math.max(0, math.min(1, value))
        -- Native StatusBar defers fill geometry: a new line can briefly show
        -- the previous full texture even though GetValue() is already near 0.
        -- Set the texture width ourselves before making it visible.
        self.Fill:SetWidth(self:GetWidth() * self.value)
        if self.value > 0 then self:Show() else self:Hide() end
    end
    function head.Progress:GetValue() return self.value end
    head.Progress:SetValue(0)

    -- Dismiss this line (queue autoplay may advance) or close the silent preview.
    local close = CreateFrame("Button", nil, head)
    createCloseArtwork(close)
    local function stopPlayback()
        if playlistHeadEditing then WV:SetWindowsUnlocked(false); return end
        playlistHeadEditing = nil
        refreshEditBorder()
        if active and active.preview then WV:StopTalkingHead()
        else WV:Silence("talking head button") end
    end
    close:SetScript("OnClick", stopPlayback)
    head:SetScript("OnClick", function(_, button)
        if button == "RightButton" then stopPlayback() end
    end)
    head.Close = close
    head.EditBorder = CreateFrame("Frame", nil, head, "BackdropTemplate")
    -- The TalkingHeads sheet has transparent/faded margins around the panel.
    -- Outline the visible panel instead of the texture's full rectangle.
    head.EditBorder:SetPoint("TOPLEFT", head, "TOPLEFT", PANEL_LEFT, -PANEL_TOP)
    head.EditBorder:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", -PANEL_RIGHT, PANEL_BOTTOM)
    head.EditBorder:SetFrameLevel(head:GetFrameLevel() + 20)
    WV:UpdateFrameEditBorder(head.EditBorder)
    head.EditBorder:EnableMouse(false)
    head.EditBorder:Hide()
    head:SetScript("OnUpdate", updateHead)
    applyHeadAppearance()
    layoutHead()
    restorePosition()
    head:Hide()
end

function WV:RefreshTalkingHeadModel()
    if not (head and active) then return end
    traceScaleEvent("reload")
    -- Late speaker capture/cache completion must not clear a frozen portrait.
    -- Coalesce those requests and load the latest identity after release.
    if scalePreview then scalePreview.modelRefresh = true; return end
    local model, speaker = head.Model, active.context.speaker
    disablePortraitBlend(model)
    model.talkAnimation = nil
    model.animationPending, model.animationNextCheck = nil, nil
    model.portraitReady = false
    model:ClearModel()
    model:SetAlpha(0)
    if model.SetModelAlpha then model:SetModelAlpha(0) end
    head.Icon:SetTexture(speaker and speaker.icon or FALLBACK_ICON)
    head.Icon:Show()
    head.IconBorder:Show()
    active.modelNextTry, active.modelDeadline = 0, GetTime() + 20
    if active.preview then
        local loaded = model:SetUnit("player", false)
        disablePortraitBlend(model)
        debugLog("SetUnit(player)=" .. tostring(loaded) .. " display=" .. tostring(model:GetDisplayInfo()))
        -- A successful SetUnit may use a cached model; do not leave it transparent
        -- while waiting for an event. OnModelLoaded handles camera and animation.
        if loaded then
            model.portraitReady = true
            updatePortraitCamera(model)
            model.animationPending = true
            model:SetAlpha(1)
            syncModelOpacity()
            head.Icon:Hide()
            head.IconBorder:Hide()
        end
    else
        tryTalkingModel()
    end
end

function WV:StartTalkingHead(context, endsAt, duration, startedAt, preview)
    self:StopTalkingHead()
    if not context then return end
    active = { context = context, startedAt = startedAt or WV.PlaybackTime(), endsAt = endsAt,
        duration = duration, preview = preview }
    createHead()
    head:EnableMouse(true)
    head:SetAlpha(1)
    setHeadOpacity(1)
    local speaker = context.speaker
    local name = speaker and speaker.name or L["Описание задания"]
    -- Some imported NPC names have enclosing brackets. Keep the source intact
    -- and remove only that outer wrapper from the displayed heading.
    L.SetContentText(head.Name, name:match("^%[([^%[%]]+)%]$") or name)
    L.SetContentText(head.Title, context.title or (L["Квест "] .. context.questId))
    head.Section:SetText(SECTION[context.section] or "")
    head.Progress:SetValue(0)
    head:Show()
    local text = WowVoiceAudioSources.DisplayText(context)
    L.SetContentText(head.Body, text and text ~= "" and text or (context.queueOwner and "" or L["Текст задания недоступен."]))
    layoutHead()
    restorePosition()
    self:RefreshTalkingHeadModel()
    refreshEditBorder()
end

-- Audio has already stopped and Dialog has been restored by Core. Leave only
-- the visual tail alive; it cannot keep talking or restart audio/model requests.
function WV:FinishTalkingHead(forceFade)
    traceScaleEvent("finished")
    if not (active and head and head:IsShown()) or (active.preview and not active.autoPreview) then
        self:StopTalkingHead()
        return
    end
    if active.closing and not forceFade then return end
    updatePlaybackText()
    active.closing = true
    head.Model.talkAnimation = nil
    head.Model.animationPending = nil
    if head.Model.portraitReady then head.Model:SetAnimation(0) end
    local gap = not forceFade and self.questQueue and self.questQueue.enabled and self.questQueue.gap
    if gap and not gap.fadeDuration then transition = nil
    else transition = { startedAt = GetTime(), duration = gap and gap.fadeDuration or 1 } end
end

function WV:StopTalkingHead()
    self:EndHeadScalePreview(true)
    local wasPreview = active and active.preview
    if wasPreview and self.SetTrackerPulsePreview then self:SetTrackerPulsePreview(false) end
    active = nil
    transition = nil
    if head then
        local wasDragging = head.draggingPosition ~= nil
        head.draggingPosition = nil
        anchor:StopMovingOrSizing()
        if wasDragging or (wasPreview and WowVoiceDB.headPosition) then setPosition(centerPosition()) end
        head.EditBorder:Hide()
        head:EnableMouse(false)
        head.Model.talkAnimation = nil
        head.Model.animationPending, head.Model.animationNextCheck = nil, nil
        head.Model.portraitReady = false
        head.Model:ClearModel()
        head:Hide()
        head:SetAlpha(1)
    end
end

function WV:GetHeadSettings()
    createHead()
    local x, y = centerPosition()
    return { width = head:GetWidth(), height = head:GetHeight(), scale = scalePreview and scalePreview.scale or head:GetScale(),
        x = x, y = y, anchor = self:GetHeadAnchor() }
end

function WV:SetHeadAnchor(point)
    if not headAnchorPoints[point] then return false, "Выберите точку привязки на схеме." end
    createHead()
    self:EndHeadScalePreview(true)
    local x, y = centerPosition()
    WowVoiceDB.headAnchor = point
    setPosition(x, y)
    if self.RefreshHeadOptions then self:RefreshHeadOptions() end
    return true
end

function WV:GetHeadAnchorPosition()
    createHead()
    local x, y = centerPosition()
    local movement = head.draggingPosition
    if movement and movement.cursorX and movement.cursorY and GetCursorPosition then
        local cursorX, cursorY = GetCursorPosition()
        if cursorX and cursorY then
            -- Native StartMoving can expose a cached frame rectangle until
            -- release. Cursor delta gives a live readout in UIParent units.
            x, y = clampCenterPosition(movement.x + (cursorX - movement.cursorX) / movement.scale,
                movement.y + (cursorY - movement.cursorY) / movement.scale)
        end
    end
    local point = self:GetHeadAnchor()
    local ax, ay = panelPointOffset(point)
    -- All nine selected points share one coordinate origin: screen center.
    -- Saved placement may still use an edge-relative anchor for screen resizing.
    return x + ax, y + ay
end

function WV:SetHeadAnchorPosition(x, y)
    if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y
        or math.abs(x) == math.huge or math.abs(y) == math.huge then
        return false, "Введите числа в поля X и Y. Допускаются минус и дробная часть."
    end
    createHead()
    self:EndHeadScalePreview(true)
    local point = self:GetHeadAnchor()
    local ax, ay = panelPointOffset(point)
    WowVoiceDB.headAnchor = point
    setPosition(x - ax, y - ay)
    if self.RefreshHeadOptions then self:RefreshHeadOptions() end
    return true
end

function WV:CenterTalkingHead()
    createHead()
    self:EndHeadScalePreview(true)
    local _, y = centerPosition()
    -- Center the visible panel, whose transparent margins are asymmetric.
    local x = panelPointOffset("CENTER")
    setPosition(-x, y)
    if self.RefreshHeadOptions then self:RefreshHeadOptions() end
end

function WV:ResetHeadPosition()
    self:EndHeadScalePreview(true)
    WowVoiceDB.headPosition, WowVoiceDB.headAnchor = nil, nil
    restorePosition()
    if self.RefreshHeadOptions then self:RefreshHeadOptions() end
end

local function restoreSnapshotSource()
    if not scalePreview or not scalePreview.reparented then return end
    head:SetParent(anchor)
    head:ClearAllPoints()
    head:SetPoint("CENTER", anchor, "CENTER")
    head:SetFrameStrata("FULLSCREEN_DIALOG")
    head:SetFrameLevel(200)
    scalePreview.reparented = nil
end

local function beginVertexTextPreview()
    local vertex = Enum and Enum.FontStringScaleAnimationMode and Enum.FontStringScaleAnimationMode.Vertex
    if not vertex or not head.SetIgnoreParentScale or not head.CreateAnimationGroup then return false end
    for _, text in ipairs({ head.Name, head.Body }) do
        if not text.SetScaleAnimationMode or not text.GetScaleAnimationMode then return false end
    end
    if not head.TextScaleLayer then
        local layer = CreateFrame("Frame", nil, head)
        layer:EnableMouse(false)
        layer:SetIgnoreParentScale(true)
        layer:SetPoint("TOPLEFT", head, "TOPLEFT", 0, 0)
        layer:Hide()
        local group = layer:CreateAnimationGroup()
        group:SetLooping("REPEAT")
        local transform = group:CreateAnimation("Scale")
        transform:SetOrigin("TOPLEFT", 0, 0)
        transform:SetDuration(1)
        transform:SetScaleFrom(1, 1)
        transform:SetScaleTo(1, 1)
        layer.Group, layer.Transform = group, transform
        head.TextScaleLayer = layer
    end
    local layer = head.TextScaleLayer
    local state = { baseScale = head:GetScale(),
        namePoint = { head.Name:GetPoint(1) }, scrollPoint = { head.TextScroll:GetPoint(1) },
        scrollWidth = head.TextScroll:GetWidth(), scrollHeight = head.TextScroll:GetHeight(),
        contentWidth = head.TextContent:GetWidth(), contentHeight = head.TextContent:GetHeight(),
        scrollOffset = head.TextScroll:GetVerticalScroll(),
        nameLevel = head.NameLayer:GetFrameLevel(), scrollLevel = head.TextScroll:GetFrameLevel(),
        nameMode = head.Name:GetScaleAnimationMode(), bodyMode = head.Body:GetScaleAnimationMode() }
    layer:SetScale(head:GetEffectiveScale())
    layer:SetSize(head:GetWidth(), head:GetHeight())
    -- Ignore the changing parent scale so native glyph metrics and line layout
    -- stay at their original effective size. Only the render transform changes.
    head.NameLayer:SetParent(layer)
    head.NameLayer:ClearAllPoints()
    head.NameLayer:SetAllPoints(layer)
    head.Name:ClearAllPoints()
    head.Name:SetPoint(state.namePoint[1], layer, state.namePoint[3], state.namePoint[4], state.namePoint[5])
    head.TextScroll:SetParent(layer)
    head.TextScroll:ClearAllPoints()
    head.TextScroll:SetPoint(state.scrollPoint[1], layer, state.scrollPoint[3], state.scrollPoint[4], state.scrollPoint[5])
    head.Name:SetScaleAnimationMode(vertex)
    head.Body:SetScaleAnimationMode(vertex)
    layer:Show()
    scalePreview.vertexText = state
    textScalePreviewStatus = "vertex"
    return true
end

local function updateVertexTextPreview(scale)
    local layer = head.TextScaleLayer
    local state = scalePreview.vertexText
    local ratio = scale / state.baseScale
    -- Vertex animations change glyph geometry, not native child anchors or the
    -- ScrollFrame's clip rectangle. Scale those explicitly in the fixed-scale
    -- layer's units, always from the captured layout (never cumulatively).
    head.Name:ClearAllPoints()
    head.Name:SetPoint(state.namePoint[1], layer, state.namePoint[3],
        state.namePoint[4] * ratio, state.namePoint[5] * ratio)
    head.TextScroll:ClearAllPoints()
    head.TextScroll:SetPoint(state.scrollPoint[1], layer, state.scrollPoint[3],
        state.scrollPoint[4] * ratio, state.scrollPoint[5] * ratio)
    head.TextScroll:SetSize(state.scrollWidth * ratio, state.scrollHeight * ratio)
    -- The scroll child's extent must match the transformed glyphs so native
    -- scroll bounds neither clamp a growing preview nor expose extra lines.
    head.TextContent:SetSize(state.contentWidth * ratio, state.contentHeight * ratio)
    head.TextScroll:UpdateScrollChildRect()
    head.TextScroll:SetVerticalScroll(state.scrollOffset * ratio)
    layer.Transform:SetScaleFrom(ratio, ratio)
    layer.Transform:SetScaleTo(ratio, ratio)
    -- A constant looping transform holds the exact ratio between slider events.
    layer.Group:Play()
end

local function endVertexTextPreview(state)
    if not state then return end
    local layer = head.TextScaleLayer
    layer.Group:Stop()
    head.NameLayer:SetParent(head)
    head.NameLayer:SetFrameLevel(state.nameLevel)
    head.NameLayer:ClearAllPoints()
    head.NameLayer:SetAllPoints(head)
    head.Name:ClearAllPoints()
    head.Name:SetPoint(state.namePoint[1], state.namePoint[2], state.namePoint[3], state.namePoint[4], state.namePoint[5])
    head.TextScroll:SetParent(head)
    head.TextScroll:SetFrameLevel(state.scrollLevel)
    head.TextScroll:ClearAllPoints()
    head.TextScroll:SetPoint(state.scrollPoint[1], state.scrollPoint[2], state.scrollPoint[3], state.scrollPoint[4], state.scrollPoint[5])
    head.TextScroll:SetSize(state.scrollWidth, state.scrollHeight)
    head.TextContent:SetSize(state.contentWidth, state.contentHeight)
    head.TextScroll:UpdateScrollChildRect()
    head.TextScroll:SetVerticalScroll(state.scrollOffset)
    head.Name:SetScaleAnimationMode(state.nameMode)
    head.Body:SetScaleAnimationMode(state.bodyMode)
    layer:Hide()
end

local function beginPortraitViewportPreview()
    local model = head.Model
    if not model.SetIgnoreParentScale then return end
    local state = { baseScale = head:GetScale(), ownScale = model:GetScale(),
        width = model:GetWidth(), height = model:GetHeight(), point = { model:GetPoint(1) },
        ignoreScale = model.IsIgnoringParentScale and model:IsIgnoringParentScale() or false }
    local effectiveScale = model:GetEffectiveScale()
    model:SetIgnoreParentScale(true)
    model:SetScale(effectiveScale)
    scalePreview.portraitViewport = state
end

local function updatePortraitViewportPreview(scale)
    local state, model = scalePreview.portraitViewport, head.Model
    local ratio = scale / state.baseScale
    -- Changing the inherited scale needed RefreshCamera on every input frame.
    -- Keep the model's native scale constant and resize its actual viewport,
    -- preserving the aspect ratio, camera, pose and screen-space placement.
    model:ClearAllPoints()
    model:SetPoint(state.point[1], state.point[2], state.point[3],
        state.point[4] * ratio, state.point[5] * ratio)
    model:SetSize(state.width * ratio, state.height * ratio)
    traceScaleEvent("viewport")
end

local function endPortraitViewportPreview(state)
    if not state then return end
    local model = head.Model
    model:SetIgnoreParentScale(state.ignoreScale)
    model:SetScale(state.ownScale)
    model:ClearAllPoints()
    model:SetPoint(state.point[1], state.point[2], state.point[3], state.point[4], state.point[5])
    model:SetSize(state.width, state.height)
end

updateScalePreviewVisual = function()
    if not scalePreview or scalePreview.capturePending then return end
    local scale = scalePreview.scale
    scalePreview.visualDirty = nil
    if scalePreview.appliedScale == scale then return end
    -- Moving an ancestor after starting the vertex transform invalidates the
    -- text layer's render placement, particularly with a non-central pivot.
    -- Stop the previous transform before any geometry changes and restart it
    -- only after the panel, scroll viewport and glyph offsets are final.
    if scalePreview.vertexText then head.TextScaleLayer.Group:Stop() end
    if scalePreview.snapshot then
        scaleSnapshot:SetScale(scale)
    else
        -- Failed capture must not disable live resizing. Keep the pose/text frozen
        -- and preserve the configured camera. Reapplying zoom/position/rotation
        -- for every slider event resets the portrait unnecessarily.
        if head:GetScale() ~= scale then
            local scrollOffset = head.TextScroll:GetVerticalScroll()
            head:SetScale(scale)
            if scalePreview.portraitViewport then
                updatePortraitViewportPreview(scale)
            elseif head.Model.portraitReady then
                disablePortraitBlend(head.Model)
                traceScaleEvent("camera")
                head.Model:RefreshCamera()
            end
            -- Refresh native clipping at the new effective scale without setting
            -- text/fonts/widths or rebuilding the frozen line and scroll layout.
            if not scalePreview.vertexText then
                head.TextScroll:UpdateScrollChildRect()
                head.TextScroll:SetVerticalScroll(scrollOffset)
            end
        end
    end
    sizeHeadAnchor(head:GetWidth(), head:GetHeight(), scale)
    if WowVoiceDB.headPosition then
        local ax, ay = panelPointOffset(scalePreview.anchorPoint)
        setPosition(scalePreview.pivotX - ax, scalePreview.pivotY - ay, true)
    else restorePosition() end
    if scalePreview.vertexText then updateVertexTextPreview(scale) end
    scalePreview.appliedScale = scale
end

local function captureScaleSnapshot()
    if not head:IsShown() or (head.visualAlpha or 1) <= 0 then return false end
    if scaleCapture == false then return false end
    if not scaleCapture then
        local ok, frame = pcall(CreateFrame, "OffScreenFrame", "WowVoiceHeadScaleCapture")
        if not ok or not frame.TakeSnapshot or not frame.ApplySnapshot or not frame.Flush or not frame.SetMaxSnapshots then
            scaleSnapshotStatus = ok and "snapshot API unavailable" or tostring(frame)
            scaleCapture = false
            return false
        end
        scaleCapture = frame
        scaleCapture:SetMaxSnapshots(1)
        scaleSnapshot = CreateFrame("Frame", "WowVoiceHeadScaleSnapshot", anchor)
        scaleSnapshot:SetFrameStrata("FULLSCREEN_DIALOG")
        scaleSnapshot:SetFrameLevel(200)
        scaleSnapshot:SetScript("OnUpdate", updateHead)
        scaleSnapshot:EnableMouse(false)
        scaleSnapshot:SetPoint("CENTER", anchor, "CENTER")
        scaleSnapshot.Texture = scaleSnapshot:CreateTexture(nil, "ARTWORK")
        scaleSnapshot.Texture:SetAllPoints(scaleSnapshot)
        scaleSnapshot:Hide()
    end
    -- Preserve the source's effective scale and screen rectangle during capture.
    -- Only this offscreen tree is rasterized: no world or options UI is included.
    scaleCapture:SetScale(anchor:GetEffectiveScale())
    scaleCapture:SetSize(head:GetWidth() * head:GetScale(), head:GetHeight() * head:GetScale())
    scaleCapture:ClearAllPoints()
    scaleCapture:SetPoint("CENTER", UIParent, "CENTER", scalePreview.x, scalePreview.y)
    scaleCapture:Show()
    scalePreview.reparented = true
    head:SetParent(scaleCapture)
    head:ClearAllPoints()
    head:SetPoint("CENTER", scaleCapture, "CENTER")
    local preview, frames = scalePreview, 0
    preview.capturePending = true
    scaleSnapshotStatus = "waiting for render"
    -- Blizzard's own OffScreenFrame consumer waits two frames before capturing.
    -- Reparenting and requesting a snapshot in the same input callback is too early.
    scaleCapture:SetScript("OnUpdate", function()
        if scalePreview ~= preview then return end
        frames = frames + 1
        if frames < 2 then return end
        local ok, snapshotID = pcall(scaleCapture.TakeSnapshot, scaleCapture)
        scaleSnapshotStatus = ok and "TakeSnapshot returned nil" or tostring(snapshotID)
        if ok and snapshotID then
            local applied, success = pcall(scaleCapture.ApplySnapshot, scaleCapture, scaleSnapshot.Texture, snapshotID)
            scaleSnapshotStatus = applied and "ApplySnapshot returned false" or tostring(success)
            if applied and success ~= false then
                preview.capturePending, preview.snapshot = nil, true
                scaleSnapshotStatus = "ready"
                scaleCapture:SetScript("OnUpdate", nil)
                scaleSnapshot:SetSize(head:GetWidth(), head:GetHeight())
                scaleSnapshot:SetAlpha(1)
                updateScalePreviewVisual()
                -- OffScreenFrame children can still draw on screen. Only the
                -- texture may remain visible, or the original covers its resize.
                scaleCapture:Hide()
                scaleSnapshot:Show()
                return
            end
        end
        scaleCapture:Flush()
        if frames < 6 then return end
        preview.capturePending = nil
        scaleCapture:SetScript("OnUpdate", nil)
        restoreSnapshotSource()
        scaleCapture:Hide()
        updateScalePreviewVisual()
        debugLog("scale snapshot: " .. scaleSnapshotStatus)
    end)
    return false
end

-- Measure complete word prefixes at the original scale. Selection rectangles
-- are not a reliable source of wrapped-line coordinates on every client.
local function frozenLineText(text, source)
    if not head.ScaleTextMeasure then
        head.ScaleTextMeasure = head:CreateFontString(nil, "ARTWORK")
        head.ScaleTextMeasure:Hide()
    end
    local measure = head.ScaleTextMeasure
    measure:SetFont(text:GetFont())
    measure:SetSpacing(text:GetSpacing())
    measure:SetWidth(text:GetWidth())
    measure:SetHeight(0)
    measure:SetWordWrap(text:CanWordWrap())
    measure:SetNonSpaceWrap(text:CanNonSpaceWrap())
    if measure.SetSmoothScaling and text.GetSmoothScaling then
        measure:SetSmoothScaling(text:GetSmoothScaling())
    end
    local function height(value)
        measure:SetText(value)
        return measure:GetStringHeight()
    end
    local originalHeight, singleHeight = height(source), height(L["А"])
    if math.abs(originalHeight - text:GetStringHeight()) > 0.1 then return end
    local parts, previousHeight, previousEnd = {}, nil, 1
    for start, word, finish in source:gmatch("()(%S+)()") do
        local gap = source:sub(previousEnd, start - 1)
        parts[#parts + 1] = gap
        -- Complex inline objects and words spanning several lines retain their
        -- normal layout if it cannot be reproduced and verified exactly.
        if height(word) > singleHeight + 0.1 then return end
        local prefixHeight = height(source:sub(1, finish - 1))
        if previousHeight and prefixHeight > previousHeight + 0.1
            and not gap:find("\n", 1, true) and not gap:find("|n", 1, true) then
            parts[#parts + 1] = "\n"
        end
        parts[#parts + 1] = word
        previousHeight, previousEnd = prefixHeight, finish
    end
    parts[#parts + 1] = source:sub(previousEnd)
    local frozen = table.concat(parts)
    local _, fontSize = text:GetFont()
    local width = text:GetWidth() * 4 + fontSize * #source
    -- Keep multiline rendering enabled. Extra width prevents automatic wraps;
    -- the inserted newlines alone define the frozen layout.
    measure:SetWordWrap(true)
    measure:SetWidth(width)
    if math.abs(height(frozen) - originalHeight) > 0.1 then return end
    return frozen, width
end

local function restoreTextLines(entry)
    entry.text:SetWordWrap(entry.wrap)
    entry.text:SetNonSpaceWrap(entry.nonSpaceWrap)
    entry.text:SetWidth(entry.width)
    entry.text:SetText(entry.source)
end

local function freezeHeadTextLines()
    local entries = {}
    for _, text in ipairs({ head.Name, head.Body }) do
        local source = text:GetText()
        if source and source ~= "" and text.CanWordWrap and text.CanNonSpaceWrap then
            local ok, frozen, width = pcall(frozenLineText, text, source)
            if ok and frozen then
                local originalHeight = text:GetStringHeight()
                local entry = { text = text, source = source, width = text:GetWidth(),
                    wrap = text:CanWordWrap(), nonSpaceWrap = text:CanNonSpaceWrap() }
                text:SetWordWrap(true)
                text:SetWidth(width)
                text:SetText(frozen)
                if math.abs(text:GetStringHeight() - originalHeight) <= 0.1 then
                    entries[#entries + 1] = entry
                else
                    restoreTextLines(entry)
                end
            end
        end
    end
    return entries
end

function WV:BeginHeadScalePreview()
    if scalePreview then return end
    createHead()
    local x, y = centerPosition()
    scalePreview = { x = x, y = y, startedAt = GetTime(), playback = active,
        scale = head:GetScale(), alpha = head.visualAlpha or 1,
        keepModel = head.Model.GetKeepModelOnHide and head.Model:GetKeepModelOnHide() or false,
        paused = head.Model.GetPaused and head.Model:GetPaused() or false }
    scalePreview.anchorPoint = self:GetHeadAnchor()
    local ax, ay = panelPointOffset(scalePreview.anchorPoint)
    scalePreview.pivotX, scalePreview.pivotY = x + ax, y + ay
    scalePreview.trace = { source = active and (active.preview and "test" or "NPC") or "idle",
        from = head:GetScale(), display = head.Model:GetDisplayInfo(), lastDisplay = head.Model:GetDisplayInfo(),
        pausedAPI = head.Model.GetPaused ~= nil }
    if head.Model.SetKeepModelOnHide then head.Model:SetKeepModelOnHide(true) end
    disablePortraitBlend(head.Model)
    if head.Model.SetPaused then head.Model:SetPaused(true) end
    scalePreview.textLines, scalePreview.textScaling = {}, {}
    if beginVertexTextPreview() then
        beginPortraitViewportPreview()
        return
    end
    textScalePreviewStatus = "legacy fallback"
    -- Capture line breaks before changing even the font's smooth-scaling mode.
    scalePreview.textLines = freezeHeadTextLines()
    -- Smooth scaling is only a drag preview, not the settled font-rendering mode.
    scalePreview.textScaling = {}
    for _, text in ipairs({ head.Name, head.Body, head.TextMeasure }) do
        if text.SetSmoothScaling then
            scalePreview.textScaling[#scalePreview.textScaling + 1] = {
                text = text, smooth = text.GetSmoothScaling and text:GetSmoothScaling() or false,
            }
            text:SetSmoothScaling(true)
        end
    end
    scalePreview.snapshot = captureScaleSnapshot()
end

function WV:EndHeadScalePreview(cancel)
    if not scalePreview then return true end
    local preview, scale = scalePreview, math.floor(scalePreview.scale * 100 + 0.5) / 100
    local trace = preview.trace
    trace.to, trace.cancelled = preview.scale, cancel == true
    trace.path = preview.vertexText and "vertex" or preview.snapshot and "snapshot" or "fallback"
    scaleTraces[#scaleTraces + 1] = trace
    if #scaleTraces > 3 then table.remove(scaleTraces, 1) end
    if scaleCapture then scaleCapture:SetScript("OnUpdate", nil) end
    restoreSnapshotSource()
    if scaleSnapshot then
        scaleSnapshot:Hide()
        scaleSnapshot.Texture:SetTexture(nil)
        scaleCapture:Flush()
        scaleCapture:Hide()
    end
    scalePreview = nil
    endPortraitViewportPreview(preview.portraitViewport)
    endVertexTextPreview(preview.vertexText)
    for _, entry in ipairs(preview.textLines) do restoreTextLines(entry) end
    for _, entry in ipairs(preview.textScaling) do entry.text:SetSmoothScaling(entry.smooth) end
    if head.Model.SetKeepModelOnHide then head.Model:SetKeepModelOnHide(preview.keepModel) end
    if head.Model.SetPaused then head.Model:SetPaused(preview.paused) end
    -- A silent preview resumes from the frozen text; real audio keeps its clock.
    if active and active == preview.playback and active.preview then
        local elapsed = GetTime() - preview.startedAt
        active.startedAt, active.endsAt = active.startedAt + elapsed, active.endsAt + elapsed
    end
    if preview.modelRefresh then self:RefreshTalkingHeadModel()
    elseif preview.modelLoaded then finishTalkingModel(head.Model) end
    if cancel then
        local changed = head:GetScale() ~= self:GetHeadScale()
        scale = self:GetHeadScale()
        head:SetScale(scale)
        sizeHeadAnchor(head:GetWidth(), head:GetHeight(), scale)
        if changed and head.Model.portraitReady then updatePortraitCamera(head.Model) end
        restorePosition()
    elseif scale ~= self:GetHeadScale() or head:GetScale() ~= scale then
        local ok, reason = self:SetHeadScale(scale)
        if ok then return true end
        -- Display bounds may have changed since the last accepted drag value.
        scale = self:GetHeadScale()
        head:SetScale(scale)
        sizeHeadAnchor(head:GetWidth(), head:GetHeight(), scale)
        restorePosition()
        refreshHeadTextFonts()
        updatePlaybackText()
        return false, reason
    end
    refreshHeadTextFonts()
    updatePlaybackText()
    return true
end

function WV:SetHeadScale(scale, temporary)
    if type(scale) ~= "number" or scale ~= scale or scale < 0.5 or scale > 1.5 then
        return false, "Введите масштаб от 50 до 150%."
    end
    createHead()
    -- Keep fractional slider positions while dragging; only saved values use 1% steps.
    if not temporary then scale = math.floor(scale * 100 + 0.5) / 100 end
    if head:GetWidth() * scale > UIParent:GetWidth() or head:GetHeight() * scale > UIParent:GetHeight() then
        return false, "Панель больше экрана. Уменьшите масштаб."
    end
    if temporary then
        self:BeginHeadScalePreview()
        scalePreview.scale = scale
        -- Native sliders can emit multiple changes (and duplicates) before a
        -- render. Apply only the latest percentage to the preview.
        scalePreview.visualDirty = true
        return true
    end
    local x, y = centerPosition()
    local positioned = WowVoiceDB.headPosition ~= nil
    local point = self:GetHeadAnchor()
    local ax, ay = panelPointOffset(point)
    local pivotX, pivotY = x + ax, y + ay
    WowVoiceDB.headScale = scale
    layoutHead()
    if head.Model.portraitReady then updatePortraitCamera(head.Model) end
    -- Hold the selected point in place; screen bounds take precedence if the
    -- enlarged panel would otherwise extend offscreen. Automatic placement
    -- continues to follow the action bars until the user chooses a point.
    if positioned then
        ax, ay = panelPointOffset(point)
        setPosition(pivotX - ax, pivotY - ay)
    else restorePosition() end
    if self.RefreshHeadOptions then self:RefreshHeadOptions() end
    return true
end

function WV:ApplyHeadSettings(settings)
    for _, key in ipairs({ "width", "height", "scale", "x", "y" }) do
        local v = settings[key]
        if type(v) ~= "number" or v ~= v or math.abs(v) == math.huge then
            return false, "Введите числовые значения во все поля."
        end
    end
    if settings.width < 360 or settings.width > 1000 or settings.height < 140 or settings.height > 600
        or settings.scale < 0.5 or settings.scale > 1.5 then
        return false, "Ширина: 360–1000; высота: 140–600; масштаб: 50–150%."
    end
    if settings.width * settings.scale > UIParent:GetWidth()
        or settings.height * settings.scale > UIParent:GetHeight() then
        return false, "Панель больше экрана. Уменьшите размер или масштаб."
    end
    createHead()
    WowVoiceDB.headWidth, WowVoiceDB.headHeight, WowVoiceDB.headScale = settings.width, settings.height, settings.scale
    layoutHead()
    setPosition(settings.x, settings.y)
    return true
end

function WV:EnsureHeadPreview(suppressTrackerPulse)
    -- Scale controls preview only the head, even when reusing an explicit test.
    if suppressTrackerPulse and self.SetTrackerPulsePreview then self:SetTrackerPulsePreview(false) end
    -- Reusing an automatic preview cancels its old deadline/fade without
    -- reloading the model. Real playback and an explicit test remain independent.
    if active and active.preview and active.autoPreview then
        active.autoHideAt = nil
        if active.closing then
            active.closing, transition = nil, nil
            setHeadOpacity(1)
            if head.Model.portraitReady then
                startTalkingAnimation(head.Model)
                head.Model.animationPending = true
            end
        end
        return true
    end
    if active and not active.closing then return true end
    local ok, reason = self:ToggleHeadPreview(suppressTrackerPulse)
    if ok and active and active.preview then active.autoPreview = true; refreshEditBorder() end
    return ok, reason
end

function WV:FinishAutoHeadPreview(delay)
    if not (active and active.preview and active.autoPreview) then return end
    active.autoHideAt = GetTime() + delay
    if delay == 0 and not scalePreview and not head.draggingPosition then
        active.autoHideAt = nil
        self:FinishTalkingHead()
    end
end

local function showSilentHeadPreview()
    WV:StartTalkingHead({ questId = 0, section = "a", title = L["Тест говорящей головы"],
        speaker = { questId = 0, name = UnitName("player") or L["Ваш персонаж"] },
        text = L["Это тест говорящей головы. Слева показана модель вашего персонажа. Звук в этом режиме не запускается.\n\n"]
            .. L["Здесь будет текст задания. Каждый блок остаётся неподвижным, пока идёт его чтение. "]
            .. L["Затем короткий плавный сдвиг открывает продолжение, сохраняя две строки предыдущего блока. "]
            .. L["Последний блок раскрывается заранее и стоит на месте до конца реплики.\n\n"]
            .. L["Кнопка центрирования выравнивает окно по горизонтали, сохраняя высоту.\n\n"]
            .. L["Только во время теста панель можно перемещать мышью. В обычном режиме её положение закреплено. "]
            .. L["Тест повторяется каждые 30 секунд и прекращается при закрытии настроек."] },
        WV.PlaybackTime() + 30, 30, nil, true)
end

function WV:RefreshPlaylistHeadPreview()
    if not playlistHeadEditing then return end
    if not active then showSilentHeadPreview() end
    if active and active.preview then
        active.autoPreview, active.autoHideAt, active.closing, transition = nil, nil, nil, nil
        setHeadOpacity(1)
    end
    refreshEditBorder()
end

function WV:SetPlaylistHeadEditing(enabled)
    playlistHeadEditing = enabled == true or nil
    if enabled then
        self:RefreshPlaylistHeadPreview()
    else
        if head and head.draggingPosition then
            head.draggingPosition = nil
            anchor:StopMovingOrSizing()
            setPosition(centerPosition())
        end
        self:HideHeadPreview()
        refreshEditBorder()
    end
    if self.RefreshFrameLockOption then self:RefreshFrameLockOption() end
end

function WV:IsWindowsUnlocked()
    return playlistHeadEditing == true
end

function WV:SetWindowsUnlocked(unlocked)
    if self.PreviewQuestQueue then self:PreviewQuestQueue(unlocked == true, true)
    else
        self:GetHeadSettings()
        self:SetPlaylistHeadEditing(unlocked == true)
    end
end

function WV:ToggleHeadPreview(suppressTrackerPulse)
    -- Pressing Test during an automatic preview pins that same panel open.
    if active and active.preview and active.autoPreview then
        self:EnsureHeadPreview()
        active.autoPreview, active.autoHideAt = nil, nil
        if self.SetTrackerPulsePreview then self:SetTrackerPulsePreview(not suppressTrackerPulse) end
        return true
    end
    if active and active.preview then
        playlistHeadEditing = nil
        self:StopTalkingHead()
        return true
    end
    -- Stop the audio and its timer, restoring Dialog before opening a silent preview.
    self:Silence("talking head preview")
    showSilentHeadPreview()
    if self.SetTrackerPulsePreview then self:SetTrackerPulsePreview(not suppressTrackerPulse) end
    return true
end

function WV:HideHeadPreview()
    if active and active.preview then self:StopTalkingHead() end
end

function WV:ResetHeadSettings()
    createHead()
    WowVoiceDB.headWidth, WowVoiceDB.headHeight, WowVoiceDB.headScale, WowVoiceDB.headPosition = nil, nil, nil, nil
    WowVoiceDB.headAnchor = nil
    layoutHead()
    restorePosition()
end

function WV:HeadCommand(command)
    if command == "reset" then
        self:ResetHeadPosition()
        message(L["положение говорящей головы сброшено"])
    else
        if self.OpenOptions then self:OpenOptions() end
    end
end

function WV:HeadScaleDiagnostics()
    if #scaleTraces == 0 then message("Scale: сначала измените масштаб ползунком."); return end
    for index, trace in ipairs(scaleTraces) do
        message(string.format("Scale[%d] %s %.1f>%.1f%% id=%s %s frames=%d cam=%d/full=%d view=%d load=%d reload=%d show/hide=%d/%d alpha0=%d hidden=%d unready=%d ids=%d unpaused=%s blend=%d finish=%d %s",
            index, trace.source, trace.from * 100, trace.to * 100, tostring(trace.display), trace.path,
            trace.frames or 0, trace.camera or 0, trace.fullCamera or 0, trace.viewport or 0, trace.loaded or 0, trace.reload or 0,
            trace.shown or 0, trace.hiddenEvent or 0, trace.alphaZero or 0, trace.hidden or 0,
            trace.unready or 0, trace.identity or 0, trace.pausedAPI and tostring(trace.unpaused or 0) or "?",
            trace.blending or 0, trace.finished or 0, trace.cancelled and "cancel" or "release"))
    end
end

function WV:HeadDiagnostics()
    message("Scale snapshot: " .. scaleSnapshotStatus)
    message("Text scale preview: " .. textScalePreviewStatus)
    self:HeadScaleDiagnostics()
    local quests, count = characterQuests(), 0
    if quests then for _ in pairs(quests) do count = count + 1 end end
    message("Portrait: сохранено квестгиверов=" .. count)
    if head and active then
        message("Camera: model=" .. tostring(head.Model.cameraFileID)
            .. " profile=" .. tostring(head.Model.cameraProfile))
        message("Animation: selected=" .. tostring(head.Model.talkAnimation)
            .. " hasTalk=" .. tostring(head.Model:HasAnimation(60))
            .. " paused=" .. tostring(head.Model.GetPaused and head.Model:GetPaused())
            .. " pending=" .. tostring(head.Model.animationPending == true))
    end
    local speaker = active and active.context.speaker
    if speaker then
        message("Portrait: quest=" .. speaker.questId .. " npc=" .. tostring(speaker.npcID)
            .. " display=" .. tostring(speaker.displayID) .. " item=" .. tostring(speaker.itemID)
            .. " icon=" .. tostring(speaker.icon))
    end
end

local events = CreateFrame("Frame", "WowVoicePortraitEvents")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("QUEST_ACCEPTED")
events:RegisterEvent("QUEST_TURNED_IN")
events:RegisterEvent("QUEST_REMOVED")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event, questId)
    queueQuestPortraits()
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD"
        or event == "QUEST_LOG_UPDATE" or event == "BAG_UPDATE_DELAYED" then return end
    local quests = characterQuests()
    if not quests then return end
    if event == "QUEST_ACCEPTED" then
        if pending and pending.questId == questId then
            quests[questId] = pending
            pending = nil
            debugLog("saved quest=" .. questId)
        else
            debugLog("QUEST_ACCEPTED quest=" .. tostring(questId) .. ": нет соответствующего QUEST_DETAIL")
        end
    else
        quests[questId] = nil
        if pending and pending.questId == questId then pending = nil end
        debugLog(event .. ": removed quest=" .. tostring(questId))
        -- active keeps the current speaker until voice playback stops.
    end
end)

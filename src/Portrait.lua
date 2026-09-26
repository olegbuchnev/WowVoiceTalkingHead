-- Quest giver appearance capture and WowVoice's talking-head panel.
-- SavedVariables stores data only, never frames or unit references.
local WV = _G.WowVoice
local pending, probe, request, head, anchor, active, transition
-- PlayerModel geometry must follow our own panel's visibility and fade.
-- The panel is independent of UIParent and other addons' interface fades.
local function syncModelOpacity()
    if not head then return end
    local model = head.Model
    local alpha = head.visualAlpha or 1
    if transition then alpha = math.max(0, 1 - math.max(0, GetTime() - transition.startedAt)) end
    if not active or not model.portraitReady or not head:IsVisible() then
        alpha = 0
    elseif model.SetModelAlpha then
        alpha = alpha * head.Portrait:GetEffectiveAlpha()
    end
    if model.SetModelAlpha then model:SetModelAlpha(alpha)
    else model:SetAlpha(alpha) end
end

local SECTION = { a = "Описание задания", p = "Выполнение задания", c = "Завершение задания" }
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_Note_01"
local DEFAULT_WIDTH, DEFAULT_HEIGHT = 570, 155
-- Retail TalkingHeadUI.xml fallback; managed layouts place it above action bars.
local DEFAULT_BOTTOM_OFFSET = 96
local TALKING_HEAD_TEXTURE = "Interface\\AddOns\\WowVoice\\Media\\TalkingHeads"
local CLOSE_UP = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up"
local CLOSE_DOWN = "Interface\\Buttons\\UI-Panel-MinimizeButton-Down"
local PRESET_ORDER = { "retail", "classic", "ellesmere" }
local PRESETS = {
    retail = {
        name = "Retail",
        title = { 1, 0.82, 0.02, 1 }, text = { 1, 1, 1, 1 },
        edge = { 0.65, 0.53, 0.25, 1 }, accent = { 0.85, 0.68, 0.3, 1 },
    },
    classic = {
        name = "Classic",
        background = "Interface\\DialogFrame\\UI-DialogBox-Background",
        border = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 16,
        fill = { 1, 1, 1, 1 }, edge = { 1, 1, 1, 1 },
        title = { 1, 0.82, 0, 1 }, text = { 1, 0.95, 0.82, 1 },
        accent = { 0.85, 0.68, 0.3, 1 },
    },
    ellesmere = {
        name = "EllesmereUI",
        background = "Interface\\Buttons\\WHITE8X8",
        border = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
        fill = { 0.06, 0.06, 0.07, 0.95 }, edge = { 0.4, 0.33, 0.19, 1 },
        title = { 1, 0.82, 0, 1 }, text = { 1, 1, 1, 1 },
        accent = { 0.85, 0.68, 0.3, 1 },
    },
}

function WV:GetHeadPreset()
    local preset = WowVoiceDB and WowVoiceDB.headPreset
    return PRESETS[preset] and preset or "retail"
end

function WV:GetHeadPresets()
    local choices = {}
    for _, key in ipairs(PRESET_ORDER) do
        choices[#choices + 1] = { key = key, name = PRESETS[key].name }
    end
    return choices
end

local function colorValues(color)
    return color[1], color[2], color[3], color[4]
end

local function readEllesmereBackground()
    local eui = _G.EllesmereUI
    if not eui or _G.EUI_CLIENT_BLOCKED then return end
    local module = eui._ModuleNS and eui._ModuleNS.EllesmereUIBlizzardSkin
    local skin = module and module.WSkin
    if not skin or type(skin.GetStyle) ~= "function" then return end
    -- Use EllesmereUI's third-party theme resolver, without skinning our frame.
    local style = skin.GetStyle("tp:WowVoice")
    if style == "eui" then return style end
    if style ~= "modern" or type(skin.GetModernBG) ~= "function" then return end
    local r, g, b, a = skin.GetModernBG()
    for _, value in ipairs({ r, g, b, a }) do
        if type(value) ~= "number" or value ~= value or value < 0 or value > 1 then return end
    end
    if r == nil or g == nil or b == nil or a == nil then return end
    return style, r, g, b, a
end

local function refreshEllesmereBackground(force)
    if not head then return end
    local now = GetTime()
    if not force and now < (head.nextBackgroundCheck or 0) then return end
    head.nextBackgroundCheck = now + 0.5
    local style, r, g, b, a
    if WV:GetHeadPreset() == "ellesmere" then
        -- Optional integration must never prevent a quest voice line from playing.
        local ok
        ok, style, r, g, b, a = pcall(readEllesmereBackground)
        if not ok then style = nil end
    end
    local signature = table.concat({ style or "fallback", tostring(r), tostring(g), tostring(b), tostring(a),
        tostring(head:GetWidth()), tostring(head:GetHeight()) }, ":")
    if not force and head.backgroundSignature == signature then return end
    head.backgroundSignature = signature
    head.EllesmereBackground:Hide()
    head.EllesmereShade:Hide()
    if WV:GetHeadPreset() ~= "ellesmere" then return end
    head.Background:SetBackdropColor(colorValues(PRESETS.ellesmere.fill))
    if style == "modern" then
        head.Background:SetBackdropColor(r, g, b, a)
    elseif style == "eui" then
        local texture = head.EllesmereBackground
        local ok, loaded = pcall(texture.SetTexture, texture, "Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png")
        if not ok or not loaded then
            head.backgroundSignature = nil
            return
        end
        -- Match EllesmereUI's centered cover crop of the background atlas.
        local aspect, sourceAspect = head:GetWidth() / head:GetHeight(), 561 / 433
        if aspect > sourceAspect then
            local trim = (0.75 - 0.75 * sourceAspect / aspect) / 2
            texture:SetTexCoord(0.25, 1, trim, 0.75 - trim)
        else
            local trim = (0.75 - 0.75 * aspect / sourceAspect) / 2
            texture:SetTexCoord(0.25 + trim, 1 - trim, 0, 0.75)
        end
        head.Background:SetBackdropColor(0, 0, 0, 0)
        texture:Show()
        head.EllesmereShade:Show()
    end
end

local function applyHeadAppearance()
    local key = WV:GetHeadPreset()
    local style = PRESETS[key]
    local retail = key == "retail"
    if retail then
        head.Background:SetBackdrop(nil)
        head.RetailBackground:Show()
        head.PortraitBackground:Show()
        head.PortraitOverlay:Show()
    else
        local inset = key == "ellesmere" and 0 or 4
        head.Background:SetBackdrop({ bgFile = style.background, edgeFile = style.border,
            tile = key ~= "ellesmere", tileSize = 32, edgeSize = style.edgeSize,
            insets = { left = inset, right = inset, top = inset, bottom = inset } })
        head.Background:SetBackdropColor(colorValues(style.fill))
        head.Background:SetBackdropBorderColor(colorValues(style.edge))
        head.RetailBackground:Hide()
        head.PortraitBackground:Hide()
        head.PortraitOverlay:Hide()
    end
    local close = head.Close
    close:ClearAllPoints()
    close.flat = key == "ellesmere"
    close.Stock:SetTexture(CLOSE_UP)
    close.Highlight:Hide()
    close.Glyph:SetPoint("CENTER", close, "CENTER", -2, 0)
    if close.flat then
        close:SetSize(24, 24)
        close:SetPoint("TOPRIGHT", head, "TOPRIGHT", -16, -16)
        close.Stock:Hide()
        close.Glyph:SetVertexColor(1, 1, 1, 0.75)
        close.Glyph:Show()
    else
        close:SetSize(32, 32)
        close:SetPoint("TOPRIGHT", head, "TOPRIGHT", -12, -12)
        close.Glyph:Hide()
        close.Stock:Show()
    end
    head.Name:SetTextColor(colorValues(style.title))
    head.Body:SetTextColor(colorValues(style.text))
    head.IconBorder:SetColorTexture(colorValues(style.edge))
    head.Progress:SetStatusBarColor(colorValues(style.accent))
    refreshEllesmereBackground(true)
end

local function message(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffWowVoice|r: " .. text)
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
local function indexedSpeaker(questId)
    local source = _G.WowVoiceIndex
    if type(source) ~= "table" then return end
    if source ~= indexedSource then
        indexedSource, indexedSpeakers = source, {}
        for title, entries in pairs(source) do
            for _, entry in ipairs(entries) do
                if positive(entry.q) then
                    local previous = indexedSpeakers[entry.q]
                    local npcID = positive(entry.i) and entry.i or nil
                    if previous == nil then
                        -- Only i/n describe the giver; ei/en describe the receiver.
                        indexedSpeakers[entry.q] = { questId = entry.q, title = title,
                            npcID = npcID, name = npcID and entry.n or nil }
                    elseif previous and previous.npcID ~= npcID then
                        -- Conflicting records must not choose an arbitrary speaker.
                        indexedSpeakers[entry.q] = false
                    end
                end
            end
        end
    end
    return indexedSpeakers[questId] or nil
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

local function replaySpeaker(questId, record, quests)
    if record and (positive(record.displayID) or positive(record.npcID)
        or positive(record.itemID) or positive(record.objectID)) then return record end

    local recovered = {}
    if record then for key, value in pairs(record) do recovered[key] = value end end
    recovered.questId = questId
    local item = questStarterItem(questId)
    if item then
        recovered.itemID = item.itemID
        recovered.icon = positive(item.iconFileID) and item.iconFileID or nil
        recovered.name = item.itemName ~= "" and item.itemName or nil
        -- Keep an identified item after it is consumed or removed from the bags.
        if quests then quests[questId] = recovered end
        return recovered
    end

    local forever = _G.WowVoiceForeverSpeakers
    local indexed
    if type(forever) == "table" then indexed = forever[questId] end
    -- Explicit non-NPC or multiple starters must not fall back to a possibly
    -- different/partial Classic giver. Captured identity and exact items win.
    if indexed == false then return record end
    indexed = indexed or indexedSpeaker(questId)
    if not (indexed and positive(indexed.npcID)) then return record end
    recovered.npcID, recovered.name = indexed.npcID, indexed.name
    recovered.title = recovered.title or indexed.title
    recovered.displayID = knownDisplay(quests, indexed.npcID)
    -- Inferred identity stays transient, so updated metadata can correct it.
    debugLog("recovered quest=" .. questId .. " npc=" .. indexed.npcID)
    return recovered
end

local warmModels, warmScanAt, warmNextAt = {}, nil, 0
local function portraitKey(speaker)
    if not speaker or speaker.itemID or speaker.objectID then return end
    if positive(speaker.displayID) then return "Display" .. speaker.displayID end
    if positive(speaker.npcID) then return "NPC" .. speaker.npcID end
end

local function cachedPortraitDisplay(speaker)
    local job = warmModels[portraitKey(speaker)]
    return job and job.displayID
end

local function scanQuestPortraits()
    local log = C_QuestLog
    if not (log and log.GetNumQuestLogEntries and log.GetInfo) then return end
    for _, job in pairs(warmModels) do job.wanted = false end
    for index = 1, log.GetNumQuestLogEntries() do
        local info = log.GetInfo(index)
        if info and not info.isHeader and WV:HasQuestAudio(info.questID) then
            local speaker = WV:GetReplaySpeaker(info.questID).speaker
            local key = portraitKey(speaker)
            if key then
                local job = warmModels[key]
                if not job then
                    job = { npcID = speaker.npcID, requestedDisplay = speaker.displayID }
                    warmModels[key] = job
                end
                job.wanted = true
                if job.exhausted and GetTime() >= job.retryAfter then job.exhausted = nil end
            end
        end
    end
    for _, job in pairs(warmModels) do
        if not job.wanted and job.model then
            job.model:Hide()
            job.expires = nil
        end
    end
end

local function updateQuestPortraits()
    local now = GetTime()
    if warmScanAt and now >= warmScanAt then
        warmScanAt = nil
        scanQuestPortraits()
    end
    if now < warmNextAt then return end
    warmNextAt = now + 0.25
    local scheduled = {}
    for key, job in pairs(warmModels) do
        if job.wanted and not job.displayID and not job.exhausted then
            scheduled[#scheduled + 1] = { key = key, job = job }
        end
    end
    -- New requests go before retries, so slow NPCs cannot starve the queue.
    table.sort(scheduled, function(a, b)
        local first, second = a.job.nextTry or 0, b.job.nextTry or 0
        if first == second then return a.key < b.key end
        return first < second
    end)
    for _, entry in ipairs(scheduled) do
        local key, job = entry.key, entry.job
        if job.wanted and not job.displayID and not job.exhausted and now >= (job.retryAfter or 0) then
            if not job.expires then
                job.expires, job.attempts, job.nextTry = now + 20, 0, now
            end
            if now >= job.expires then
                job.expires, job.retryAfter = nil, now + 60
                job.exhausted = true
                if job.model then job.model:Hide() end
            elseif now >= job.nextTry and job.attempts < 8 then
                if not job.model then
                    -- Each identity owns its model: late loads cannot be attributed
                    -- to a different NPC after a queue slot is reused.
                    local model = CreateFrame("PlayerModel", "WowVoiceWarmPortrait" .. key, UIParent)
                    job.model = model
                    model:SetSize(1, 1)
                    model:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT")
                    model:SetAlpha(0)
                    if model.SetModelAlpha then model:SetModelAlpha(0) end
                    model:EnableMouse(false)
                    model:SetScript("OnModelLoaded", function()
                        if not job.wanted then return end
                        local display = model:GetDisplayInfo()
                        if not positive(display) then return end
                        job.displayID = display
                        model:Hide()
                        if head and active and not active.preview and not head.Model.portraitReady
                            and portraitKey(active.context.speaker) == key then
                            WV:RefreshTalkingHeadModel()
                        end
                    end)
                end
                job.attempts, job.nextTry = job.attempts + 1, now + 2
                job.model:Show()
                if positive(job.requestedDisplay) then
                    pcall(job.model.SetDisplayInfo, job.model, job.requestedDisplay)
                else
                    pcall(job.model.SetCreature, job.model, job.npcID)
                end
                -- GetDisplayInfo can return metadata before the model is loaded.
                -- Only OnModelLoaded may complete this job and hide its frame.
                return -- Start at most one request per update interval.
            end
        end
    end
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
    return { questId = questId, section = section, title = title, text = text, speaker = record }
end

function WV:GetReplaySpeaker(questId)
    local quests = characterQuests()
    local record = replaySpeaker(questId, quests and quests[questId], quests)
    local title = record and record.title
    if not title and C_QuestLog and C_QuestLog.GetTitleForQuestID then
        title = C_QuestLog.GetTitleForQuestID(questId)
    end
    local text = record and record.description
    if (not text or text == "") and C_QuestLog and C_QuestLog.GetLogIndexForQuestID
        and type(GetQuestLogQuestText) == "function" then
        local index = C_QuestLog.GetLogIndexForQuestID(questId)
        -- nil means the selected quest, whose text may belong to another ID.
        if positive(index) then text = GetQuestLogQuestText(index) end
    end
    return { questId = questId, section = "a", title = title, text = text, speaker = record }
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
        if bottomContainer then
            anchor:SetPoint("BOTTOM", bottomContainer, "BOTTOM", 0, 0)
        else
            anchor:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, DEFAULT_BOTTOM_OFFSET)
        end
    end
end

local function centerPosition()
    local x, y = anchor:GetCenter()
    local cx, cy = UIParent:GetCenter()
    return x - cx, y - cy
end

local function setPosition(x, y)
    -- Coordinates in UI units relative to the center of the screen.
    local maxX = math.max(0, (UIParent:GetWidth() - anchor:GetWidth()) / 2)
    local maxY = math.max(0, (UIParent:GetHeight() - anchor:GetHeight()) / 2)
    x, y = math.max(-maxX, math.min(maxX, x)), math.max(-maxY, math.min(maxY, y))
    WowVoiceDB.headPosition = { "CENTER", "CENTER", x, y }
    restorePosition()
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
    if not (head and active) then return end
    local elapsed = math.max(0, GetTime() - active.startedAt)
    if active.preview and elapsed >= active.duration then
        active.startedAt = GetTime()
        active.endsAt = active.startedAt + active.duration
        elapsed = 0
    end
    local length = active.endsAt - active.startedAt
    head.Progress:SetValue(length > 0 and math.min(1, elapsed / length) or 1)
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

local function updatePortraitCamera(model)
    -- Let PlayerModel compute its portrait camera. Selecting an embedded M2
    -- camera with SetCamera(0) can leave a model in its authored full-body view.
    local profile, key, fileID = WV:GetPortraitCameraProfile(model)
    model.cameraProfile, model.cameraFileID = key, fileID
    model:SetPortraitZoom(1)
    model:SetCamDistanceScale(profile.distance)
    model:SetPosition(0, profile.y, profile.z)
    model:SetRotation(0)
    model:RefreshCamera()
end

local function finishTalkingModel(model)
    if not active or active.closing then return end
    local speaker = active.context.speaker
    -- Late notifications must not cover an item or unknown speaker's icon.
    if not active.preview and (not portraitKey(speaker)
        or not positive(model:GetDisplayInfo())) then return end
    -- A later load can reset the camera even if a previous model was ready.
    -- Reapply it for every real OnModelLoaded notification.
    model.portraitReady = true
    updatePortraitCamera(model)
    model.talkAnimation = model:HasAnimation(60) and 60 or 0
    model:SetAnimation(model.talkAnimation)
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
    local display = speaker.displayID or cachedPortraitDisplay(speaker)
    if positive(display) then
        local ok, loaded = pcall(model.SetDisplayInfo, model, display)
        if (not ok or loaded == false) and positive(speaker.npcID) then
            pcall(model.SetCreature, model, speaker.npcID)
        end
    elseif positive(speaker.npcID) then
        pcall(model.SetCreature, model, speaker.npcID)
    end
    -- A numeric display ID is not proof that render resources are ready.
    -- Keep the placeholder until OnModelLoaded configures the camera.
end

local function layoutHead()
    local width = (WowVoiceDB and WowVoiceDB.headWidth) or DEFAULT_WIDTH
    local height = (WowVoiceDB and WowVoiceDB.headHeight) or DEFAULT_HEIGHT
    local scale = (WowVoiceDB and WowVoiceDB.headScale) or 1
    local textLeft, textRight = 152, 42
    -- All presets share Retail's composition: portrait on the left, name above
    -- the text on the right, and space reserved for the close button.
    head.Name:SetWidth(width - textLeft - textRight)
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
    head:SetScale(scale)
    -- Only the panel receives the preset scale; the anchor uses UIParent units.
    anchor:SetSize(width * scale, height * scale)
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
    head.Progress:SetWidth(width - 16)
    head.TextContent:SetWidth(textWidth)
    head.Body:SetWidth(textWidth)
    local measure = head.TextMeasure
    measure:SetFont(head.Body:GetFont())
    measure:SetSpacing(head.Body:GetSpacing())
    measure:SetWidth(textWidth)
    measure:SetText("А")
    local singleHeight = measure:GetStringHeight()
    measure:SetText("А\nА")
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
    refreshEllesmereBackground(true)
    updatePlaybackText()
end

-- Keep model ancestors opaque: PlayerModel's rendered geometry needs its own
-- opacity, rather than relying on a parent frame fade. Apply the same value to
-- every visible component, without multiplying it again through its parents.
local function setHeadOpacity(alpha)
    head.visualAlpha = alpha
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
    setHeadOpacity(math.max(0, 1 - elapsed))
    if GetTime() >= transition.startedAt + 1 then WV:StopTalkingHead() end
end

-- Match the normal UI's coordinate scale without inheriting its visibility.
local function refreshHeadScale()
    if not anchor then return end
    anchor:SetScale(UIParent:GetEffectiveScale())
    if head and head.Model.portraitReady then updatePortraitCamera(head.Model) end
end

local scaleEvents = CreateFrame("Frame", "WowVoiceHeadScaleEvents")
scaleEvents:RegisterEvent("PLAYER_LOGIN")
scaleEvents:RegisterEvent("UI_SCALE_CHANGED")
scaleEvents:RegisterEvent("DISPLAY_SIZE_CHANGED")
scaleEvents:SetScript("OnEvent", refreshHeadScale)

local function createHead()
    if head then return end
    anchor = CreateFrame("Frame", "WowVoiceTalkingHeadAnchor")
    anchor:SetScale(UIParent:GetEffectiveScale())
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    head = CreateFrame("Button", "WowVoiceTalkingHead", anchor)
    head:SetPoint("CENTER", anchor, "CENTER")
    head:SetSize(DEFAULT_WIDTH, DEFAULT_HEIGHT)
    head:SetFrameStrata("DIALOG")
    head:EnableMouse(false)
    head:RegisterForDrag("LeftButton")
    head:RegisterForClicks("RightButtonUp")
    head:SetScript("OnDragStart", function()
        if active and active.preview then anchor:StartMoving() end
    end)
    head:SetScript("OnDragStop", function()
        anchor:StopMovingOrSizing()
        if active and active.preview then
            setPosition(centerPosition())
            if WV.RefreshHeadOptions then WV:RefreshHeadOptions() end
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
    head.Background = CreateFrame("Frame", nil, head, "BackdropTemplate")
    head.Background:SetAllPoints(head)
    head.Background:SetFrameLevel(head:GetFrameLevel())
    head.Background:EnableMouse(false)
    head.Portrait = CreateFrame("Frame", nil, head)
    head.Portrait:SetAllPoints(head)
    head.Portrait:EnableMouse(false)
    head.RetailBackground = retailTexture(head.Background, "BACKGROUND", 0, 0, 570, 155)
    head.RetailBackground:SetAllPoints(head)
    head.EllesmereBackground = head.Background:CreateTexture(nil, "BACKGROUND", nil, 0)
    head.EllesmereBackground:SetAllPoints(head)
    head.EllesmereShade = head.Background:CreateTexture(nil, "BACKGROUND", nil, 1)
    head.EllesmereShade:SetColorTexture(0, 0, 0, 0.62)
    head.EllesmereShade:SetAllPoints(head)
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
        -- PlayerModel can reset its camera when a hidden parent is shown again.
        if active and self.portraitReady then updatePortraitCamera(self) end
        syncModelOpacity()
    end)
    head:SetScript("OnShow", syncModelOpacity)
    head:SetScript("OnHide", syncModelOpacity)
    model:SetScript("OnModelLoaded", finishTalkingModel)
    model:SetScript("OnAnimFinished", function(self)
        if active and self.talkAnimation then self:SetAnimation(self.talkAnimation) end
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
    head.Progress = CreateFrame("StatusBar", nil, head)
    head.Progress:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 8, 2)
    head.Progress:SetSize(312, 2)
    head.Progress:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    head.Progress:SetMinMaxValues(0, 1)

    -- Every preset uses the same stop action, with its own close-button style.
    local close = CreateFrame("Button", nil, head)
    -- Own both artwork layers instead of clearing native Button texture slots:
    -- an empty texture path can leave the previous stock artwork on screen.
    close.Stock = close:CreateTexture(nil, "ARTWORK")
    close.Stock:SetAllPoints(close)
    close.Highlight = close:CreateTexture(nil, "OVERLAY")
    close.Highlight:SetTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    -- Stock highlight art has a black background and requires additive blending.
    close.Highlight:SetBlendMode("ADD")
    close.Highlight:SetAllPoints(close)
    -- Match the borderless close glyph used by EllesmereUI's window skins.
    local cross = close:CreateTexture(nil, "OVERLAY")
    cross:SetAtlas("uitools-icon-close")
    cross:SetSize(14, 14)
    cross:SetPoint("CENTER", close, "CENTER", -2, 0)
    close.Glyph = cross
    close:SetScript("OnEnter", function()
        if close.flat then cross:SetVertexColor(1, 1, 1, 1)
        else close.Highlight:Show() end
    end)
    close:SetScript("OnLeave", function()
        cross:SetVertexColor(1, 1, 1, 0.75)
        cross:SetPoint("CENTER", close, "CENTER", -2, 0)
        close.Highlight:Hide()
        close.Stock:SetTexture(CLOSE_UP)
    end)
    close:SetScript("OnMouseDown", function()
        if close.flat then cross:SetPoint("CENTER", close, "CENTER", -1, -1)
        else close.Stock:SetTexture(CLOSE_DOWN) end
    end)
    close:SetScript("OnMouseUp", function()
        cross:SetPoint("CENTER", close, "CENTER", -2, 0)
        close.Stock:SetTexture(CLOSE_UP)
    end)
    local function stopPlayback()
        if active and active.preview then WV:StopTalkingHead()
        else WV:Silence("talking head button") end
    end
    close:SetScript("OnClick", stopPlayback)
    head:SetScript("OnClick", function(_, button)
        if button == "RightButton" then stopPlayback() end
    end)
    head.Close = close
    head:SetScript("OnUpdate", function()
        tryTalkingModel()
        refreshEllesmereBackground(false)
        if active and not active.closing then updatePlaybackText() end
        updateHeadTransition()
        syncModelOpacity()
    end)
    applyHeadAppearance()
    layoutHead()
    restorePosition()
    head:Hide()
end

function WV:RefreshTalkingHeadModel()
    if not (head and active) then return end
    local model, speaker = head.Model, active.context.speaker
    model.talkAnimation = nil
    model.portraitReady = false
    model:ClearModel()
    model:SetAlpha(0)
    if model.SetModelAlpha then model:SetModelAlpha(0) end
    head.Icon:SetTexture(speaker and speaker.icon or FALLBACK_ICON)
    head.Icon:Show()
    head.IconBorder:Show()
    active.modelNextTry, active.modelDeadline = 0, GetTime() + 20
    if active.preview then
        local loaded = model:SetUnit("player")
        debugLog("SetUnit(player)=" .. tostring(loaded) .. " display=" .. tostring(model:GetDisplayInfo()))
        -- A successful SetUnit may use a cached model; do not leave it transparent
        -- while waiting for an event. OnModelLoaded handles camera and animation.
        if loaded then
            model.portraitReady = true
            updatePortraitCamera(model)
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
    active = { context = context, startedAt = startedAt or GetTime(), endsAt = endsAt,
        duration = duration, preview = preview }
    if not preview and WowVoiceDB and WowVoiceDB.headEnabled == false then return end
    createHead()
    head:EnableMouse(true)
    head:SetAlpha(1)
    setHeadOpacity(1)
    local speaker = context.speaker
    head.Name:SetText(speaker and speaker.name or "Описание задания")
    head.Title:SetText(context.title or ("Квест " .. context.questId))
    head.Section:SetText(SECTION[context.section] or "")
    head.Progress:SetValue(0)
    head:Show()
    local text = context.text
    head.Body:SetText(text and text ~= "" and text or "Текст задания недоступен.")
    layoutHead()
    self:RefreshTalkingHeadModel()
end

-- Audio has already stopped and Dialog has been restored by Core. Leave only
-- the visual tail alive; it cannot keep talking or restart audio/model requests.
function WV:FinishTalkingHead()
    if not (active and head and head:IsShown()) or active.preview then
        self:StopTalkingHead()
        return
    end
    if active.closing then return end
    updatePlaybackText()
    active.closing = true
    head.Model.talkAnimation = nil
    if head.Model.portraitReady then head.Model:SetAnimation(0) end
    transition = { startedAt = GetTime() }
end

function WV:StopTalkingHead()
    local wasPreview = active and active.preview
    active = nil
    transition = nil
    if head then
        anchor:StopMovingOrSizing()
        if wasPreview and WowVoiceDB.headPosition then setPosition(centerPosition()) end
        head:EnableMouse(false)
        head.Model.talkAnimation = nil
        head.Model.portraitReady = false
        head.Model:ClearModel()
        head:Hide()
        head:SetAlpha(1)
    end
end

function WV:GetHeadSettings()
    createHead()
    local x, y = centerPosition()
    return { width = head:GetWidth(), height = head:GetHeight(), scale = head:GetScale(),
        x = x, y = y, enabled = WowVoiceDB.headEnabled ~= false, preset = self:GetHeadPreset() }
end

function WV:SetHeadPreset(preset)
    if not PRESETS[preset] then return false end
    createHead()
    local x, y = centerPosition()
    local hasSavedPosition = WowVoiceDB.headPosition ~= nil
    WowVoiceDB.headPreset = preset
    -- Selecting a preset restores the common geometry without moving the panel.
    WowVoiceDB.headWidth, WowVoiceDB.headHeight, WowVoiceDB.headScale = nil, nil, nil
    applyHeadAppearance()
    layoutHead()
    if hasSavedPosition then setPosition(x, y) else restorePosition() end
    if self.RefreshHeadOptions then self:RefreshHeadOptions() end
    return true
end

function WV:CenterTalkingHead()
    createHead()
    local _, y = centerPosition()
    setPosition(0, y)
end

function WV:ResetHeadPosition()
    WowVoiceDB.headPosition = nil
    restorePosition()
end

function WV:ApplyHeadSettings(settings)
    for _, key in ipairs({ "width", "height", "scale", "x", "y" }) do
        local v = settings[key]
        if type(v) ~= "number" or v ~= v or math.abs(v) == math.huge then
            return false, "Введите числовые значения во все поля."
        end
    end
    if settings.width < 360 or settings.width > 1000 or settings.height < 140 or settings.height > 600
        or settings.scale < 0.5 or settings.scale > 2 then
        return false, "Ширина: 360–1000; высота: 140–600; масштаб: 50–200%."
    end
    if settings.width * settings.scale > UIParent:GetWidth()
        or settings.height * settings.scale > UIParent:GetHeight() then
        return false, "Панель больше экрана. Уменьшите размер или масштаб."
    end
    createHead()
    WowVoiceDB.headWidth, WowVoiceDB.headHeight, WowVoiceDB.headScale = settings.width, settings.height, settings.scale
    layoutHead()
    setPosition(settings.x, settings.y)
    self:SetHeadEnabled(settings.enabled ~= false)
    return true
end

function WV:SetHeadEnabled(enabled)
    WowVoiceDB.headEnabled = enabled
    if self.RefreshStopButton then self:RefreshStopButton() end
    if active and active.preview then return end
    if not enabled then
        if active and active.closing then self:StopTalkingHead()
        elseif head then head:Hide() end
    elseif active and head and not head:IsShown() then
        self:StartTalkingHead(active.context, active.endsAt, active.duration, active.startedAt)
    elseif active and not head then
        self:StartTalkingHead(active.context, active.endsAt, active.duration, active.startedAt)
    end
end

function WV:ToggleHeadPreview()
    if active and active.preview then self:StopTalkingHead(); return true end
    -- Stop the audio and its timer, restoring Dialog before opening a silent preview.
    self:Silence("talking head preview")
    self:StartTalkingHead({ questId = 0, section = "a", title = "Тест говорящей головы",
        speaker = { questId = 0, name = UnitName("player") or "Ваш персонаж" },
        text = "Это тест говорящей головы. Слева показана модель вашего персонажа. Звук в этом режиме не запускается.\n\n"
            .. "Здесь будет текст задания. Каждый блок остаётся неподвижным, пока идёт его чтение. "
            .. "Затем короткий плавный сдвиг открывает продолжение, сохраняя две строки предыдущего блока. "
            .. "Последний блок раскрывается заранее и стоит на месте до конца реплики.\n\n"
            .. "На странице настроек можно выбрать оформление Retail, Classic или EllesmereUI. "
            .. "Кнопка центрирования выравнивает окно по горизонтали, сохраняя высоту.\n\n"
            .. "Только во время теста панель можно перемещать мышью. В обычном режиме её положение закреплено. "
            .. "Тест повторяется каждые 30 секунд и прекращается при закрытии настроек." },
        GetTime() + 30, 30, nil, true)
    return true
end

function WV:HideHeadPreview()
    if active and active.preview then self:StopTalkingHead() end
end

function WV:ResetHeadSettings()
    createHead()
    WowVoiceDB.headWidth, WowVoiceDB.headHeight, WowVoiceDB.headScale, WowVoiceDB.headPosition = nil, nil, nil, nil
    layoutHead()
    restorePosition()
end

function WV:HeadCommand(command)
    if command == "on" or command == "off" then
        self:SetHeadEnabled(command == "on")
        message("говорящая голова: " .. (WowVoiceDB.headEnabled and "вкл" or "выкл"))
    elseif command == "reset" then
        self:ResetHeadPosition()
        message("положение говорящей головы сброшено")
    else
        if self.OpenOptions then self:OpenOptions() end
    end
end

function WV:HeadDiagnostics()
    local quests, count = characterQuests(), 0
    if quests then for _ in pairs(quests) do count = count + 1 end end
    message("Portrait: сохранено квестгиверов=" .. count .. "; показ="
        .. tostring(not (WowVoiceDB and WowVoiceDB.headEnabled == false)))
    if head and active then
        message("Camera: model=" .. tostring(head.Model.cameraFileID)
            .. " profile=" .. tostring(head.Model.cameraProfile))
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
events:SetScript("OnUpdate", updateQuestPortraits)
events:SetScript("OnEvent", function(_, event, questId)
    warmScanAt = warmScanAt or (GetTime() + 0.5)
    if event == "PLAYER_LOGIN" or event == "QUEST_LOG_UPDATE" then return end
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

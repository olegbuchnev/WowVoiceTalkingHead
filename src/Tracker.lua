-- Small replay controls in Blizzard's tracker (including EllesmereUI) and
-- Questie. Keep our state outside either tracker's pooled rows.
local WV = _G.WowVoice
local buttons, hooked = {}, {}
local progress, pulses = {}, {}
local REMINDER_DURATION = 10
local REMINDER_MESSAGE_DURATION = 5
local LISTENED_COOLDOWN = 30 * 60
local previewStarted
local reminderPreview
local reminderTestQuest, reminderTestStarted
local lastProgressQuest

local function enabled()
    return WowVoiceDB and WowVoiceDB.trackerButtons ~= false
end

local function pulseEnabled()
    return enabled() and WowVoiceDB.enabled ~= false and WowVoiceDB.trackerProgressPulse ~= false
end

local function visibleTrackerQuest(play)
    if not play.active or not play:IsVisible() or play:GetEffectiveAlpha() <= 0 then return false end
    -- Hidden/collapsed parents are covered by IsVisible. Also exclude buttons
    -- whose center is outside the screen, even if their frame is still shown.
    local x, y = play:GetCenter()
    if not x or not y then return false end
    local scale = play:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if x * scale < 0 or y * scale < 0 or x * scale > UIParent:GetWidth()
        or y * scale > UIParent:GetHeight() then return false end
    return true
end

local function positionReminder(self)
    local status = self.statusFrame
    if not status then return end
    local offset = (self.statusFontSize or 18) + 6
    local top = status.GetTop and status:GetTop()
    if top and status.GetRegions and status:IsVisible() then
        local scale = self:GetEffectiveScale()
        top = top * status:GetEffectiveScale() / scale
        -- Read the rendered message regions, including native wrapping and
        -- multiple simultaneous messages, rather than the container's height.
        for _, region in ipairs({ status:GetRegions() }) do
            if region:IsObjectType("FontString") and region:IsVisible() and region:GetAlpha() > 0 then
                local text, bottom = region:GetText(), region:GetBottom()
                if text and text:find("%S") and bottom then
                    offset = math.max(offset, top - bottom * region:GetEffectiveScale() / scale + 6)
                end
            end
        end
    end
    -- Keep the lowest position for this appearance. Expiring messages must
    -- not pull the clickable reminder upward, including while hovered.
    offset = math.max(offset, self.statusOffset or 0)
    if offset ~= self.statusOffset then
        self.statusOffset = offset
        self:ClearAllPoints()
        self:SetPoint("TOP", status, "TOP", 0, -offset)
    end
end

local function updateReminderPreview(self)
    if not self.isTest and not pulseEnabled() then self:Hide(); return end
    positionReminder(self)
    if self.hovered then return end
    local remaining = self.expiresAt - GetTime()
    if remaining <= 0 then self:Hide(); return end
    self:SetAlpha(math.min(1, remaining / 0.35))
end

-- Shared by actual progress and the explicit mock. Only the mock emits a
-- synthetic yellow message; normal notifications leave Blizzard's text alone.
local function showQuestReminder(id, isTest)
    if reminderPreview and reminderPreview:IsShown() and reminderPreview.hovered
        and reminderPreview.questID ~= id then
        -- Do not change the click target under the user's mouse.
        return
    end
    if not reminderPreview then
        local frame = CreateFrame("Button", "WowVoiceQuestReminderPreview", UIParent)
        reminderPreview = frame
        frame:SetSize(180, 20)
        frame:SetFrameStrata("DIALOG")
        local label = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        label:SetPoint("LEFT", frame, "LEFT", 0, 0)
        label:SetText("Вспомнить задание")
        label:SetWordWrap(false)
        label:SetTextColor(1, 0.82, 0)
        frame.Label = label
        local _, baseFontSize = label:GetFont()
        frame.baseFontSize = baseFontSize or 12
        frame:SetWidth(label:GetStringWidth() + 24)
        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
        icon:SetSize(18, 18)
        icon:SetPoint("LEFT", label, "RIGHT", 6, 0)
        icon:SetAlpha(0.7)
        frame.Icon = icon
        frame:SetScript("OnEnter", function(self)
            self.hovered = true
            self:SetAlpha(1)
            self.Icon:SetAlpha(1)
        end)
        frame:SetScript("OnLeave", function(self)
            if self.hovered then self.expiresAt = GetTime() + REMINDER_MESSAGE_DURATION end
            self.hovered = false
            self.Icon:SetAlpha(0.7)
        end)
        frame:SetScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
            self.statusOffset = nil
            self.hovered = false
            self.Icon:SetAlpha(0.7)
        end)
        frame:SetScript("OnClick", function(self)
            if WV:ReplayQuest(self.questID) then self:Hide() end
        end)
        frame:Hide()
    end
    local frame = reminderPreview
    if UIErrorsFrame then
        if frame.statusFrame ~= UIErrorsFrame then frame.statusOffset = nil end
        frame.statusFrame = UIErrorsFrame
        local font, size, flags = UIErrorsFrame:GetFont()
        if font and size then
            size = size * UIErrorsFrame:GetEffectiveScale() / frame:GetEffectiveScale()
            frame.Label:SetFont(font, size, flags)
        end
        local ratio = (size or frame.baseFontSize) / frame.baseFontSize
        local iconSize, gap = 18 * ratio, 6 * ratio
        frame.Icon:SetSize(iconSize, iconSize)
        frame.Icon:ClearAllPoints()
        frame.Icon:SetPoint("LEFT", frame.Label, "RIGHT", gap, 0)
        frame:SetSize(frame.Label:GetStringWidth() + gap + iconSize,
            math.max((size or 18) + 4, iconSize + 2))
        frame.statusFontSize = size or 18
        if isTest then
            local log = _G.C_QuestLog
            local objectives = log and log.GetQuestObjectives and log.GetQuestObjectives(id)
            local text = objectives and objectives[1] and objectives[1].text
            UIErrorsFrame:AddMessage(text and text:find("%S") and text or "Цель задания: 1/5", 1, 1, 0)
        end
        positionReminder(frame)
    else
        frame.statusFrame, frame.statusOffset = nil, nil
        frame:ClearAllPoints()
        frame:SetPoint("TOP", UIParent, "TOP", 0, -146)
    end
    frame.questID = id
    frame.isTest = isTest == true
    frame.expiresAt = GetTime() + REMINDER_MESSAGE_DURATION
    frame:SetAlpha(1)
    frame:Show()
    frame:SetScript("OnUpdate", updateReminderPreview)
end

-- Showing a mock never manufactures quest progress or changes cooldowns.
function WV:TestQuestReminder(id)
    reminderTestQuest, reminderTestStarted = nil, nil
    if reminderPreview then reminderPreview:Hide() end
    self:RefreshTrackerButtons()
    if id == false then return end
    local log, inLog = _G.C_QuestLog, {}
    if log and log.GetNumQuestLogEntries and log.GetInfo then
        for index = 1, log.GetNumQuestLogEntries() do
            local info = log.GetInfo(index)
            if info and not info.isHeader and info.questID then inLog[info.questID] = true end
        end
    end
    local candidates, seen = {}, {}
    for _, play in pairs(buttons) do
        local questID = play.questID
        if (not id or id == questID) and inLog[questID] and not seen[questID]
            and visibleTrackerQuest(play) and self:HasQuestAudio(questID) then
            seen[questID] = true
            candidates[#candidates + 1] = questID
        end
    end
    if #candidates == 0 then
        DEFAULT_CHAT_FRAME:AddMessage(WV.displayName .. ": нет видимого квеста с кнопкой озвучки для теста")
        return
    end
    table.sort(candidates)
    id = candidates[math.random(#candidates)]
    showQuestReminder(id, true)
    reminderTestQuest, reminderTestStarted = id, GetTime()
    self:RefreshTrackerButtons()
end

function WV:IsQuestReminderTest(id)
    return (reminderPreview and reminderPreview:IsShown() and reminderPreview.isTest
        and reminderPreview.questID == id)
        or (reminderTestQuest == id and reminderTestStarted
            and GetTime() - reminderTestStarted < REMINDER_DURATION)
end

function WV:FinishQuestReminderTest(id)
    if reminderTestQuest == id then reminderTestQuest, reminderTestStarted = nil, nil end
    if reminderPreview and reminderPreview.isTest and reminderPreview.questID == id then
        reminderPreview:Hide()
    end
    self:RefreshTrackerButtons()
end

local function currentTimestamp()
    -- Absolute time survives both /reload and a full client restart.
    return GetServerTime and GetServerTime() or time()
end

local function resetQuestReminder(id)
    if type(id) ~= "number" or id <= 0 then return end
    -- Acceptance/removal starts a fresh baseline, never a progress reminder.
    progress[id], pulses[id] = nil, nil
    if reminderPreview and reminderPreview.questID == id then reminderPreview:Hide() end
end

local function listenedQuests(incremental)
    local guid = UnitGUID("player")
    if not (WowVoiceDB and guid) then return end
    WowVoiceDB.listenedQuests = WowVoiceDB.listenedQuests or {}
    if not WowVoiceDB.reminderCooldown30Minutes then
        -- Previous builds stored one-hour deadlines. Keep the original start
        -- time when shortening existing pauses, including other characters.
        for _, quests in pairs(WowVoiceDB.listenedQuests) do
            for id, expiresAt in pairs(quests) do
                if type(expiresAt) == "number" then quests[id] = expiresAt - 30 * 60 end
            end
        end
        WowVoiceDB.reminderCooldown30Minutes = true
    end
    WowVoiceDB.listenedQuests[guid] = WowVoiceDB.listenedQuests[guid] or {}
    local listened = WowVoiceDB.listenedQuests[guid]
    local now = currentTimestamp()
    for id, expiresAt in pairs(listened) do
        -- Old session booleans have no playback time and cannot establish
        -- a deadline. Discard them along with expired timestamps.
        if type(expiresAt) ~= "number" or not (expiresAt > now) then listened[id] = nil end
        if incremental then coroutine.yield() end
    end
    return listened
end

function WV:MarkQuestListened(id)
    local listened = listenedQuests()
    if listened then listened[id] = currentTimestamp() + LISTENED_COOLDOWN end
    pulses[id] = nil
    if reminderTestQuest == id then
        reminderTestQuest, reminderTestStarted = nil, nil
    end
    if reminderPreview and reminderPreview.questID == id then reminderPreview:Hide() end
    self:RefreshTrackerButtons()
end

local function stopPulse(play)
    play:SetScript("OnUpdate", nil)
    play.glowFrame = nil
    play.ProgressGlow:Hide()
    play.ProgressAnts:Hide()
    play.Icon:SetAlpha(play.hovered and 1 or 0.7)
end

local function updatePulse(play)
    local testStarted = reminderTestQuest == play.questID and reminderTestStarted
    if testStarted and GetTime() - testStarted >= REMINDER_DURATION then testStarted = nil end
    local started = previewStarted or testStarted or pulses[play.questID]
    local elapsed = started and (GetTime() - started)
    if not play.active or not enabled() or not elapsed
        or (not previewStarted and not testStarted and (not pulseEnabled() or elapsed >= REMINDER_DURATION)) then
        stopPulse(play)
        return
    end
    play:SetScript("OnUpdate", updatePulse)
    -- Blizzard's ActionButton loop: gold outer glow plus the moving edge
    -- from IconAlertAnts (22 tiles, 48x48 in a 256x256 texture, 0.01 s/tile).
    -- Only the texture frame changes; opacity and size stay steady.
    local frame = math.floor(math.max(0, elapsed) / 0.01) % 22
    if play.glowFrame ~= frame then
        local left, top = (frame % 5) * 48 / 256, math.floor(frame / 5) * 48 / 256
        play.ProgressAnts:SetTexCoord(left, left + 48 / 256, top, top + 48 / 256)
        play.glowFrame = frame
    end
    play.ProgressGlow:Show()
    play.ProgressAnts:Show()
end

local function makeButton(block, readQuestID, parent)
    local play = CreateFrame("Button", nil, parent or block)
    readQuestID = readQuestID or function() return block.id end
    play:SetSize(18, 18)
    play:SetFrameLevel(block:GetFrameLevel() + 5)
    play.Icon = play:CreateTexture(nil, "ARTWORK")
    play.Icon:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    play.Icon:SetSize(18, 18)
    play.Icon:SetPoint("CENTER")
    play.ProgressGlow = play:CreateTexture(nil, "OVERLAY")
    -- The outerGlow region of Blizzard's ActionButton overlay, with its native
    -- gold color and 1.4x button size. No scale/alpha animation or recoloring.
    play.ProgressGlow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
    play.ProgressGlow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
    play.ProgressGlow:SetSize(25.2, 25.2)
    play.ProgressGlow:SetAlpha(1)
    play.ProgressGlow:SetPoint("CENTER")
    play.ProgressGlow:Hide()
    play.ProgressAnts = play:CreateTexture(nil, "OVERLAY", nil, 1)
    play.ProgressAnts:SetTexture("Interface\\SpellActivationOverlay\\IconAlertAnts")
    play.ProgressAnts:SetSize(25.2 * 0.85, 25.2 * 0.85)
    play.ProgressAnts:SetAlpha(1)
    play.ProgressAnts:SetPoint("CENTER")
    play.ProgressAnts:Hide()
    -- Dim only the triangle; the separate glow textures retain full opacity.
    play:SetAlpha(1)
    play.Icon:SetAlpha(0.7)
    play:SetScript("OnClick", function()
        -- Resolve at click time: either tracker can recycle a row.
        local id = readQuestID()
        if enabled() and play.active and id and WV:HasQuestAudio(id) then
            pulses[id] = nil
            stopPulse(play)
            WV:ReplayQuest(id)
        end
    end)
    play:SetScript("OnEnter", function(self)
        self.hovered = true
        self.Icon:SetAlpha(1)
    end)
    play:SetScript("OnLeave", function(self)
        self.hovered = false
        self.Icon:SetAlpha(0.7)
    end)
    play:SetScript("OnHide", function(self)
        self.hovered = false
        stopPulse(self)
    end)
    play:SetScript("OnShow", updatePulse)
    buttons[block] = play
    return play
end

-- Questie's module iterator is the only source of rows; do not inspect its
-- private pool, parse titles, reuse VoiceOver's buttons or change native layout.
local questiePool
local questieScrollHooks = {}
local questieRefreshPending
local function requestQuestieRefresh()
    if questieRefreshPending then return end
    if C_Timer and C_Timer.After then
        questieRefreshPending = true
        C_Timer.After(0, function()
            questieRefreshPending = nil
            WV:RefreshTrackerButtons()
        end)
    else
        WV:RefreshTrackerButtons()
    end
end

local function questieQuestID(line)
    if line.mode == "quest" and type(line.Quest) == "table"
        and type(line.Quest.Id) == "number" and line.Quest.Id > 0 then
        return line.Quest.Id
    end
end

local function questieScroll(line)
    local parent = line:GetParent()
    while parent do
        if parent.IsObjectType and parent:IsObjectType("ScrollFrame") then return parent end
        parent = parent:GetParent()
    end
end

local function refreshQuestieLine(line)
    local id = questieQuestID(line)
    if not (id and line.label and line.expandQuest and line:IsVisible()
        and WV:HasQuestAudio(id)) then return end
    local scroll = questieScroll(line)
    local host = scroll and scroll:GetParent() or line
    local play = buttons[line]
    if not play then
        -- A sibling of the scroll frame avoids horizontal clipping of the new
        -- column. Vertical clipping and row lifecycle are mirrored below.
        play = makeButton(line, function() return questieQuestID(line) end, host)
        play.questieLine = line
        line:HookScript("OnHide", function() play.active = false; play:Hide() end)
        line:HookScript("OnShow", requestQuestieRefresh)
        -- Preserve Questie's hover/fade behavior when the cursor is over play.
        for _, script in ipairs({"OnEnter", "OnLeave"}) do
            play:HookScript(script, function()
                local handler = line:GetScript(script)
                if handler then handler(line) end
            end)
        end
    elseif play:GetParent() ~= host then
        play:SetParent(host)
    end
    if scroll and not questieScrollHooks[scroll] then
        questieScrollHooks[scroll] = true
        scroll:HookScript("OnVerticalScroll", requestQuestieRefresh)
        scroll:HookScript("OnSizeChanged", requestQuestieRefresh)
    end
    play:SetScale(line:GetEffectiveScale() / host:GetEffectiveScale())
    play:SetFrameLevel(line:GetFrameLevel() + 5)
    play.questID = id
    play:ClearAllPoints()
    -- expandQuest retains its anchor even when Questie hides the minus on a
    -- completed quest or replaces it with an item. Keep a fixed column.
    local _, size = line.label:GetFont()
    size = size or 14
    local iconSize = math.max(12, size + 4)
    if play.questieIconSize ~= iconSize then
        play.questieIconSize = iconSize
        play:SetSize(iconSize, iconSize)
        play.Icon:SetSize(iconSize, iconSize)
        play.ProgressGlow:SetSize(iconSize * 1.4, iconSize * 1.4)
        play.ProgressAnts:SetSize(iconSize * 1.4 * 0.85, iconSize * 1.4 * 0.85)
    end
    play:SetPoint("RIGHT", line.expandQuest, "TOPLEFT", -math.max(2, size * 3 / 14), -size / 2)
    if scroll then
        local top, bottom = scroll:GetTop(), scroll:GetBottom()
        local y = line.label:GetTop()
        if not (top and bottom and y) then return end
        local scale = line:GetEffectiveScale()
        y = y * scale
        local halfHeight = iconSize / 2
        local center = y - size * scale / 2
        if center + halfHeight * scale > top * scroll:GetEffectiveScale()
            or center - halfHeight * scale < bottom * scroll:GetEffectiveScale() then return end
    end
    play.active = true
    play:Show()
    updatePulse(play)
end

local function setupQuestie()
    local loader = _G.QuestieLoader
    if not (loader and type(loader.ImportModule) == "function") then return end
    local pool = loader:ImportModule("TrackerLinePool")
    local tracker = loader:ImportModule("QuestieTracker")
    if not (type(pool) == "table" and type(pool.UpdateQuestTitleLines) == "function"
        and type(pool.ResetLinesForChange) == "function" and type(tracker) == "table"
        and type(tracker.Update) == "function" and type(tracker.UpdateFormatting) == "function") then return end
    questiePool = pool
    if not hooked[tracker] then
        hooked[tracker] = true
        hooksecurefunc(tracker, "Update", requestQuestieRefresh)
        hooksecurefunc(tracker, "UpdateFormatting", requestQuestieRefresh)
        hooksecurefunc(pool, "ResetLinesForChange", function()
            for line, play in pairs(buttons) do
                if play.questieLine and not questieQuestID(line) then
                    play.active = false
                    play:Hide()
                end
            end
        end)
        requestQuestieRefresh()
    end
end

function WV:RefreshTrackerButtons()
    if reminderPreview and reminderPreview:IsShown() and (not enabled()
        or not WV:HasQuestAudio(reminderPreview.questID)
        or (not reminderPreview.isTest and not pulseEnabled())) then reminderPreview:Hide() end
    for id, started in pairs(pulses) do
        if not pulseEnabled() or GetTime() - started >= REMINDER_DURATION then pulses[id] = nil end
    end
    for _, play in pairs(buttons) do play.active = false end
    local tracker = _G.QuestObjectiveTracker
    if enabled() and tracker and tracker.usedBlocks then
        for _, blocks in pairs(tracker.usedBlocks) do
            for _, block in pairs(blocks) do
                if block.HeaderText and WV:HasQuestAudio(block.id) then
                    local play = buttons[block] or makeButton(block)
                    play.questID = block.id
                    play.active = true
                    play:ClearAllPoints()
                    -- Leave the title and objective layout untouched. In the stock
                    -- tracker, also leave room for the quest's waypoint marker.
                    local poi = block.poiButton
                    if poi and poi:IsShown() then
                        play:SetPoint("RIGHT", poi, "LEFT", -2, 0)
                    else
                        local _, size = block.HeaderText:GetFont()
                        play:SetPoint("RIGHT", block.HeaderText, "TOPLEFT", -4, -(size or 14) / 2)
                    end
                    play:Show()
                    updatePulse(play)
                end
            end
        end
    end
    if enabled() and questiePool then
        questiePool.UpdateQuestTitleLines(refreshQuestieLine)
    end
    for _, play in pairs(buttons) do
        if not play.active then play:Hide() end
    end
end

function WV:SetTrackerProgressPulseEnabled(value)
    WowVoiceDB.trackerProgressPulse = value == true
    self:RefreshTrackerButtons()
    if self.RefreshHeadOptions then self:RefreshHeadOptions() end
end

function WV:SetTrackerPulsePreview(value)
    previewStarted = value and GetTime() or nil
    self:RefreshTrackerButtons()
end

local function objectiveState(id)
    local objectives = C_QuestLog.GetQuestObjectives(id)
    if not objectives or #objectives == 0 then return end
    local state = {}
    for i, objective in ipairs(objectives) do
        -- Missing text indicates that the client's objective cache is not ready.
        if not objective.text or not objective.text:find("%S") then return end
        state[i] = table.concat({ objective.type or "", tostring(objective.numFulfilled),
            tostring(objective.numRequired), tostring(objective.finished == true),
            -- Some non-counter objectives report progress only through text.
            objective.numFulfilled == nil and objective.text or "" }, "\031")
    end
    return table.concat(state, "\030")
end

local function scanProgress()
    local log = _G.C_QuestLog
    if not (log and log.GetNumQuestLogEntries and log.GetInfo and log.GetQuestObjectives) then return end
    local present, changed = {}, {}
    local listened = listenedQuests(true) or {}
    for index = 1, log.GetNumQuestLogEntries() do
        local info = log.GetInfo(index)
        if info and not info.isHeader and info.questID and info.questID > 0 then
            local id = info.questID
            present[id] = true
            local state = objectiveState(id)
            if state then
                if progress[id] and progress[id] ~= state then changed[id] = true end
                -- Always keep the baseline current, even with reminders off.
                progress[id] = state
            end
        end
        coroutine.yield()
    end
    local reminderID
    for id in pairs(changed) do
        -- Only a still-active listening pause slides with real progress.
        -- After 30 quiet minutes the next change can remind again.
        if listened[id] then listened[id] = currentTimestamp() + LISTENED_COOLDOWN end
        if not listened[id] and pulseEnabled() and WV:HasQuestAudio(id) then
            pulses[id] = GetTime()
            -- Prefer the most recent native progress event; use a stable order
            -- when several changes arrive without QUEST_WATCH_UPDATE.
            if not reminderID or id == lastProgressQuest
                or (reminderID ~= lastProgressQuest and id < reminderID) then reminderID = id end
        end
        coroutine.yield()
    end
    for id in pairs(progress) do
        if not present[id] then progress[id], pulses[id] = nil, nil end
        coroutine.yield()
    end
    if reminderPreview and not present[reminderPreview.questID] then reminderPreview:Hide() end
    if reminderID and pulseEnabled() and not listened[reminderID] and WV:HasQuestAudio(reminderID) then
        showQuestReminder(reminderID, false)
    end
    WV:RefreshTrackerButtons()
end

function WV:SetTrackerButtonsEnabled(value)
    WowVoiceDB.trackerButtons = value == true
    self:RefreshTrackerButtons()
    if self.RefreshHeadOptions then self:RefreshHeadOptions() end
end

local function setup()
    setupQuestie()
    local tracker = _G.QuestObjectiveTracker
    if tracker and hooked[tracker] then return end
    if tracker and not hooked[tracker] and type(tracker.Update) == "function"
        and type(tracker.FreeBlock) == "function" then
        hooked[tracker] = true
        hooksecurefunc(tracker, "Update", function() WV:RefreshTrackerButtons() end)
        hooksecurefunc(tracker, "FreeBlock", function(_, block)
            -- Shared pools may hand the frame to an entirely different module.
            local play = buttons[block]
            if play then play.active = false; play:Hide() end
        end)
    end
    WV:RefreshTrackerButtons()
end

local events = CreateFrame("Frame", "WowVoiceTrackerEvents")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("QUEST_WATCH_UPDATE")
events:RegisterEvent("QUEST_ACCEPTED")
events:RegisterEvent("QUEST_REMOVED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event, questId, legacyQuestId)
    if event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" then
        WV.Work:Cancel("tracker-progress")
        local id = event == "QUEST_ACCEPTED" and (legacyQuestId or questId) or questId
        resetQuestReminder(id)
        if event == "QUEST_REMOVED" and type(id) == "number" and id > 0 then
            -- Clear on removal, not acceptance: the new offer's automatic
            -- description can start before QUEST_ACCEPTED and must keep its pause.
            local listened = listenedQuests()
            if listened then listened[id] = nil end
            if reminderTestQuest == id then reminderTestQuest, reminderTestStarted = nil, nil end
            if lastProgressQuest == id then lastProgressQuest = nil end
        end
        WV.Work:Queue("tracker-progress", scanProgress, 0.05)
        WV:RefreshTrackerButtons()
    elseif event == "QUEST_WATCH_UPDATE" then
        lastProgressQuest = questId
        WV.Work:Queue("tracker-progress", scanProgress, 0.05)
    elseif event == "QUEST_LOG_UPDATE" then
        WV.Work:Queue("tracker-progress", scanProgress, 0.05)
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LOGIN" then
        -- Login/reload and loading screens establish a fresh, silent baseline.
        progress, pulses = {}, {}
        lastProgressQuest, reminderTestQuest, reminderTestStarted = nil, nil, nil
        if reminderPreview then reminderPreview:Hide() end
        WV.Work:Cancel("tracker-progress")
        setup()
        WV.Work:Queue("tracker-progress", scanProgress, 0.05)
    else
        setup()
    end
end)
setup()

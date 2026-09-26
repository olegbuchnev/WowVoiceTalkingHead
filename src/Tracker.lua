-- Small replay controls in Blizzard's on-screen quest tracker, including
-- EllesmereUI's skin. Keep our state outside Blizzard's pooled blocks.
local WV = _G.WowVoice
local buttons, hooked = {}, {}
local progress, pulses = {}, {}
local REMINDER_DURATION = 10
local previewStarted

local function listenedQuests()
    local guid = UnitGUID("player")
    if not (WowVoiceDB and guid) then return end
    WowVoiceDB.listenedQuests = WowVoiceDB.listenedQuests or {}
    WowVoiceDB.listenedQuests[guid] = WowVoiceDB.listenedQuests[guid] or {}
    return WowVoiceDB.listenedQuests[guid]
end

function WV:MarkQuestListened(id)
    local listened = listenedQuests()
    if listened then listened[id] = true end
    pulses[id] = nil
    self:RefreshTrackerButtons()
end

local function enabled()
    return WowVoiceDB and WowVoiceDB.trackerButtons ~= false
end

local function pulseEnabled()
    return enabled() and WowVoiceDB.enabled ~= false and WowVoiceDB.trackerProgressPulse ~= false
end

local function stopPulse(play)
    play:SetScript("OnUpdate", nil)
    play.glowFrame = nil
    play.ProgressGlow:Hide()
    play.ProgressAnts:Hide()
    play.Icon:SetAlpha(play.hovered and 1 or 0.7)
end

local function updatePulse(play)
    local started = previewStarted or pulses[play.questID]
    local elapsed = started and (GetTime() - started)
    if not play.active or not enabled() or not elapsed
        or (not previewStarted and (not pulseEnabled() or elapsed >= REMINDER_DURATION)) then
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

local function makeButton(block)
    local play = CreateFrame("Button", nil, block)
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
        -- Read the current ID: Blizzard can reuse this block for another quest.
        if enabled() and play.active and WV:HasQuestAudio(block.id) then
            pulses[block.id] = nil
            stopPulse(play)
            WV:ReplayQuest(block.id)
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

function WV:RefreshTrackerButtons()
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
    local present = {}
    local listened = listenedQuests() or {}
    for index = 1, log.GetNumQuestLogEntries() do
        local info = log.GetInfo(index)
        if info and not info.isHeader and info.questID and info.questID > 0 then
            local id = info.questID
            present[id] = true
            if WV:HasQuestAudio(id) then
                local state = objectiveState(id)
                if state then
                    if progress[id] and progress[id] ~= state and not listened[id] and pulseEnabled() then
                        pulses[id] = GetTime()
                    end
                    -- Always keep the baseline current, even with reminders off.
                    progress[id] = state
                end
            end
        end
    end
    for id in pairs(progress) do
        if not present[id] then progress[id], pulses[id] = nil, nil end
    end
    WV:RefreshTrackerButtons()
end

function WV:SetTrackerButtonsEnabled(value)
    WowVoiceDB.trackerButtons = value == true
    self:RefreshTrackerButtons()
    if self.RefreshHeadOptions then self:RefreshHeadOptions() end
end

local function setup()
    local tracker = _G.QuestObjectiveTracker
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
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event, isInitialLogin, isReloadingUi)
    if event == "QUEST_LOG_UPDATE" then
        scanProgress()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LOGIN" then
        if event == "PLAYER_ENTERING_WORLD" and isInitialLogin and not isReloadingUi then
            -- A real login starts a new listening session. Reloads and zone
            -- transitions keep this character's saved playback marks.
            local listened = listenedQuests()
            if listened then for id in pairs(listened) do listened[id] = nil end end
        end
        -- Login/reload and loading screens establish a fresh, silent baseline.
        progress, pulses = {}, {}
        setup()
        scanProgress()
    else
        setup()
    end
end)
setup()

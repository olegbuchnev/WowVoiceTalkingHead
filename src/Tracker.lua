-- Small replay controls in Blizzard's on-screen quest tracker, including
-- EllesmereUI's skin. Keep our state outside Blizzard's pooled blocks.
local WV = _G.WowVoice
local buttons, hooked = {}, {}

local function enabled()
    return WowVoiceDB and WowVoiceDB.trackerButtons ~= false
end

local function makeButton(block)
    local play = CreateFrame("Button", nil, block)
    play:SetSize(18, 18)
    play:SetFrameLevel(block:GetFrameLevel() + 5)
    play.Icon = play:CreateTexture(nil, "ARTWORK")
    play.Icon:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    play.Icon:SetSize(18, 18)
    play.Icon:SetPoint("CENTER")
    play:SetAlpha(0.7)
    play:SetScript("OnClick", function()
        -- Read the current ID: Blizzard can reuse this block for another quest.
        if enabled() and play.active and WV:HasQuestAudio(block.id) then
            WV:ReplayQuest(block.id)
        end
    end)
    play:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
    end)
    play:SetScript("OnLeave", function(self)
        self:SetAlpha(0.7)
    end)
    play:SetScript("OnHide", function(self)
        self:SetAlpha(0.7)
    end)
    buttons[block] = play
    return play
end

function WV:RefreshTrackerButtons()
    for _, play in pairs(buttons) do play.active = false end
    local tracker = _G.QuestObjectiveTracker
    if enabled() and tracker and tracker.usedBlocks then
        for _, blocks in pairs(tracker.usedBlocks) do
            for _, block in pairs(blocks) do
                if block.HeaderText and WV:HasQuestAudio(block.id) then
                    local play = buttons[block] or makeButton(block)
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
                end
            end
        end
    end
    for _, play in pairs(buttons) do
        if not play.active then play:Hide() end
    end
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
events:SetScript("OnEvent", setup)
setup()

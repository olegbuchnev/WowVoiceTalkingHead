--[[ Voice-over Stop button.

When the talking head is disabled, show the button during voice playback.
The talking head's close button replaces this standalone control when enabled.
The player can drag it, and its position is saved.

  /wv button auto    - show only during playback (default)
  /wv button always  - keep visible at all times
  /wv button off     - hide the button
  /wv button reset   - return to the default central position
]]

local WV = _G.WowVoice
if not WV then return end

-- Style only our own buttons, and leave them unchanged without EllesmereUI.
-- Preserve click handlers and dragging behavior.
local buttonSkins = {}
local function applyEllesmereStyle(btn)
    local eui = _G.EllesmereUI
    if not eui or _G.EUI_CLIENT_BLOCKED then return end
    local module = eui._ModuleNS and eui._ModuleNS.EllesmereUIBlizzardSkin
    local skin = module and module.WSkin
    if skin and type(skin.Button) == "function" then
        if buttonSkins[btn] == "native" then return end
        if skin.ResolveTheme and (not skin.Theme or not skin.Theme.bgR) then
            skin.ResolveTheme()
        end
        -- Match the adjacent Back button. Preserve Icon explicitly because
        -- the EllesmereUI skin otherwise removes all original button textures.
        skin.Button(btn, { "Icon" })
        buttonSkins[btn] = "native"
        return
    end
    if buttonSkins[btn] then return end

    -- Without BlizzardSkin, reproduce EllesmereUI's flat button style.
    -- If the module loads later, its native skin replaces these textures.
    for _, region in ipairs({ btn:GetRegions() }) do
        if region:IsObjectType("Texture") and region ~= btn.Icon then region:SetAlpha(0) end
    end
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0.08, 0.08, 0.08, 0.92)
    bg:SetAllPoints(btn)
    local hover = btn:CreateTexture(nil, "HIGHLIGHT")
    hover:SetColorTexture(1, 1, 1, 0.1)
    hover:SetAllPoints(btn)
    for _, edge in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local border = btn:CreateTexture(nil, "BORDER")
        border:SetColorTexture(0.2, 0.2, 0.2, 1)
        if edge == "TOP" or edge == "BOTTOM" then
            border:SetHeight(1)
            border:SetPoint(edge .. "LEFT", btn, edge .. "LEFT")
            border:SetPoint(edge .. "RIGHT", btn, edge .. "RIGHT")
        else
            border:SetWidth(1)
            border:SetPoint("TOP" .. edge, btn, "TOP" .. edge)
            border:SetPoint("BOTTOM" .. edge, btn, "BOTTOM" .. edge)
        end
    end
    buttonSkins[btn] = "fallback"
end

WV.StyleButton = applyEllesmereStyle

local DEFAULT_POINT = { "CENTER", "CENTER", 0, -180 }

local button = CreateFrame("Button", "WowVoiceStopButton", UIParent,
                           "UIPanelButtonTemplate")
button:SetWidth(150)
button:SetHeight(24)
button:SetText("Остановить реплику")
button:SetFrameStrata("HIGH")
button:Hide()

button:SetMovable(true)
button:EnableMouse(true)
button:RegisterForDrag("LeftButton")

button:SetScript("OnDragStart", function(self) self:StartMoving() end)
button:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    WowVoiceDB.buttonPos = { point, relPoint, x, y }
end)

button:SetScript("OnClick", function()
    WV:Silence()
end)

button:HookScript("OnShow", applyEllesmereStyle)
applyEllesmereStyle(button)

function WV:RestoreButton()
    local p = WowVoiceDB and WowVoiceDB.buttonPos
    -- Invalid or incomplete position data must not move the button offscreen.
    if not (p and p[1] and p[2] and p[3] and p[4]) then p = DEFAULT_POINT end
    button:ClearAllPoints()
    button:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    self:RefreshStopButton()
end

function WV:ResetButton()
    WowVoiceDB.buttonPos = nil
    self:RestoreButton()
end

local voicePlaying = false
function WV:RefreshStopButton()
    local mode = (WowVoiceDB and WowVoiceDB.button) or "auto"
    local headEnabled = WowVoiceDB and WowVoiceDB.headEnabled ~= false
    if headEnabled or mode == "off" then
        button:Hide()
    elseif mode == "always" then
        button:Show()
    elseif voicePlaying then
        button:Show()
    else
        button:Hide()
    end
end

function WV.OnPlaybackChanged(playing)
    voicePlaying = playing == true
    WV:RefreshStopButton()
end

function WV:ButtonMode(mode)
    WowVoiceDB.button = mode
    self:RefreshStopButton()
end

-- Replay descriptions in the modern journal. Buttons belong to pooled rows,
-- so read their current ID on every click instead of capturing it in a closure.
local journalButtons = {}
local journalHooks = {}

local function updatePlayButton(play)
    if not WV:HasQuestAudio(play.questOwner.questID) then
        play:Hide()
        return
    end
    if not play.compact then applyEllesmereStyle(play) end
    local available = WowVoiceDB and WowVoiceDB.enabled
    local alpha = play.compact and not play.hovered and 0.7 or 1
    play:SetAlpha(available and alpha or 0.4)
    play:Show()
end

local function makePlayButton(parent, questOwner, compact)
    local template
    if not compact then template = "UIPanelButtonTemplate" end
    local play = CreateFrame("Button", nil, parent, template)
    play.compact = compact
    play.questOwner = questOwner
    play:SetSize(compact and 22 or 108, 22)
    if compact then
        -- The default font does not include the play triangle on every client.
        -- Use a built-in texture for the icon instead.
        local icon = play:CreateTexture(nil, "ARTWORK")
        play.Icon = icon
        icon:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
        icon:SetSize(20, 20)
        icon:SetPoint("CENTER")
    else
        play:SetText("Слушать")
    end
    play:SetScript("OnClick", function(self)
        if WV:HasQuestAudio(self.questOwner.questID) then
            WV:ReplayQuest(self.questOwner.questID)
        end
        updatePlayButton(self)
    end)
    play:SetScript("OnEnter", function(self)
        self.hovered = true
        updatePlayButton(self)
    end)
    play:SetScript("OnLeave", function(self)
        self.hovered = false
        updatePlayButton(self)
    end)
    play:SetScript("OnHide", function(self)
        self.hovered = false
    end)
    play:SetScript("OnShow", updatePlayButton)
    journalButtons[questOwner] = play
    return play
end

local function refreshQuestList()
    local scroll = _G.QuestScrollFrame
    local pool = scroll and scroll.titleFramePool
    if not (pool and pool.EnumerateActive) then return end
    for row in pool:EnumerateActive() do
        if row.Checkbox then
            local play = journalButtons[row] or makePlayButton(row, row, true)
            -- Make room to the right of the checkbox. The template already anchors
            -- the quest title and markers to it, so they move together.
            if WV:HasQuestAudio(row.questID) then
                if not play.checkboxPoint then play.checkboxPoint = { row.Checkbox:GetPoint() } end
                row.Checkbox:ClearAllPoints()
                row.Checkbox:SetPoint("TOPRIGHT", row, "TOPRIGHT", -26, -8)
            elseif play.checkboxPoint then
                local p = play.checkboxPoint
                row.Checkbox:ClearAllPoints()
                row.Checkbox:SetPoint(p[1], p[2], p[3], p[4], p[5])
            end
            play:ClearAllPoints()
            play:SetPoint("LEFT", row.Checkbox, "RIGHT", 3, 0)
            updatePlayButton(play)
        end
    end
end

local function refreshQuestDetails()
    local map = _G.QuestMapFrame
    local details = map and (map.DetailsFrame or (map.QuestsFrame and map.QuestsFrame.DetailsFrame))
    if not details then return end
    local parent = details.BackFrame or details
    local play = journalButtons[details] or makePlayButton(parent, details, false)
    play:ClearAllPoints()
    if parent.BackButton then
        play:SetPoint("LEFT", parent.BackButton, "RIGHT", 8, 0)
    else
        play:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, -12)
    end
    updatePlayButton(play)
end

local function setupJournal()
    applyEllesmereStyle(button)
    -- Blizzard may load the journal after WowVoice. Retry on ADDON_LOADED
    -- to connect it without installing duplicate hooks.
    if type(QuestLogQuests_Update) == "function" and not journalHooks.list then
        hooksecurefunc("QuestLogQuests_Update", refreshQuestList)
        journalHooks.list = true
    end
    if type(QuestMapFrame_ShowQuestDetails) == "function" and not journalHooks.details then
        hooksecurefunc("QuestMapFrame_ShowQuestDetails", refreshQuestDetails)
        journalHooks.details = true
    end
    local map = _G.QuestMapFrame
    if map and not journalHooks.show then
        map:HookScript("OnShow", function()
            refreshQuestList()
            refreshQuestDetails()
        end)
        journalHooks.show = true
    end
    refreshQuestList()
    refreshQuestDetails()
end

local journalEvents = CreateFrame("Frame")
journalEvents:RegisterEvent("PLAYER_LOGIN")
journalEvents:RegisterEvent("ADDON_LOADED")
journalEvents:SetScript("OnEvent", setupJournal)
setupJournal()

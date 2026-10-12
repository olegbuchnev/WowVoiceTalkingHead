-- Account-wide invitation, once per installed version.
local WV, L = WowVoice, WowVoiceLocale
local URL = "https://talkingheadru.tw1.ru/"
local FONT = "Interface\\AddOns\\TalkingHeadRu\\Media\\Fonts\\frizqt___cyr.ttf"
local WIDTH, HEIGHT = 540, 540
local SCALE = 2 / 3
local panel

local function label(parent, text, size, y, height, r, g, b)
    local region = parent:CreateFontString(nil, "OVERLAY")
    region:SetFont(FONT, size, "")
    region:SetSize(WIDTH - 48, height)
    region:SetPoint("TOP", parent, "TOP", 0, -y)
    region:SetJustifyH("CENTER")
    region:SetJustifyV("MIDDLE")
    region:SetWordWrap(true)
    region:SetSpacing(4)
    region:SetTextColor(r or 0.87, g or 0.86, b or 0.84)
    region:SetText(text)
    return region
end

local function flatFrame(frame, r, g, b)
    frame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
        edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1 / frame:GetEffectiveScale()})
    frame:SetBackdropColor(r, g, b, 1)
    frame:SetBackdropBorderColor(0.22, 0.22, 0.22, 1)
end

local function createPanel()
    local frame = CreateFrame("Frame", "TalkingHeadRuVoteInvite", UIParent, "BackdropTemplate")
    frame:Hide()
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    flatFrame(frame, 0.063, 0.063, 0.067)

    label(frame, "TalkingHead Ru", 26, 16, 34, 0.86, 0.65, 0.50)
    local art = frame:CreateTexture(nil, "ARTWORK")
    art:SetTexture("Interface\\AddOns\\TalkingHeadRu\\Media\\VoteAdventurers.tga")
    art:SetSize(240, 240 * 290 / 346)
    art:SetTexCoord(0, 346 / 512, 0, 290 / 512)
    art:SetPoint("TOP", frame, "TOP", 0, -56)
    frame.Art = art
    frame.Title = label(frame, L["Голосуйте за лучшую озвучку"], 26, 279, 32, 0.95, 0.93, 0.91)
    frame.Description = label(frame,
        (L["Сравните голоса из WowVoice, CatQuest и Wayfarer. Ваш выбор поможет подобрать озвучку для заданий и персонажей WoW Forever."]
            :gsub("WowVoice", "|cff40b3ffWowVoice|r")
            :gsub("CatQuest", "|cffff8c33CatQuest|r")
            :gsub("Wayfarer", "|cff66d973Wayfarer|r")),
        18, 323, 66)

    local link = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
    link:SetSize(360, 34)
    link:SetPoint("TOP", frame, "TOP", 0, -403)
    link:SetAutoFocus(false)
    link:SetFont(FONT, 18, "")
    link:SetTextColor(0.86, 0.65, 0.50)
    link:SetJustifyH("CENTER")
    flatFrame(link, 0.09, 0.09, 0.095)
    link:SetText(URL)
    link:SetScript("OnMouseUp", function(self) self:SetFocus(); self:HighlightText() end)
    link:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    link:SetScript("OnTextChanged", function(self)
        if self:GetText() ~= URL then self:SetText(URL); self:HighlightText() end
    end)
    link:SetScript("OnEscapePressed", function() frame:Hide() end)
    link:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    frame.Link = link
    label(frame, L["Нажмите на ссылку, затем Ctrl+C"], 14, 448, 20, 0.65, 0.65, 0.65)

    local close = CreateFrame("Button", nil, frame, "BackdropTemplate")
    close:SetSize(160, 32)
    close:SetPoint("BOTTOM", frame, "BOTTOM", 0, 20)
    flatFrame(close, 0.13, 0.13, 0.14)
    local caption = close:CreateFontString(nil, "OVERLAY")
    caption:SetFont(FONT, 16, "")
    caption:SetAllPoints(close)
    caption:SetTextColor(0.87, 0.86, 0.84)
    caption:SetText(L["Закрыть"])
    close:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(0.86, 0.65, 0.50, 1) end)
    close:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.22, 0.22, 0.22, 1) end)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame.Close = close
    frame:SetScript("OnHide", function() link:ClearFocus(); frame:StopMovingOrSizing() end)
    UISpecialFrames = UISpecialFrames or {}
    table.insert(UISpecialFrames, "TalkingHeadRuVoteInvite")
    return frame
end

local function version()
    local metadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local value = metadata and metadata("TalkingHeadRu", "Version")
    return type(value) == "string" and value:find("%S") and value or nil
end

function WV:ShowVoteInvite(manual)
    local db, current = TalkingHeadRuDB, version()
    if not db then return false end
    if not manual and (db.enabled == false or not current
        or db.voteInviteSeenVersions and db.voteInviteSeenVersions[current]) then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    panel = panel or createPanel()
    panel:SetScale(math.min(SCALE, (UIParent:GetHeight() - 40) / HEIGHT, (UIParent:GetWidth() - 40) / WIDTH))
    flatFrame(panel, 0.063, 0.063, 0.067)
    panel:Show()
    if current then
        db.voteInviteSeenVersions = db.voteInviteSeenVersions or {}
        db.voteInviteSeenVersions[current] = true
    end
    return true
end

local events = CreateFrame("Frame", "TalkingHeadRuVoteInviteEvents")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
local scheduled, pending
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        if scheduled then return end
        scheduled = true
        local function show()
            if InCombatLockdown and InCombatLockdown() then
                pending = true
                self:RegisterEvent("PLAYER_REGEN_ENABLED")
            else
                WV:ShowVoteInvite()
            end
        end
        if C_Timer and C_Timer.After then C_Timer.After(3, show) else show() end
    elseif event == "PLAYER_REGEN_ENABLED" and pending then
        pending = nil
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        WV:ShowVoteInvite()
    end
end)

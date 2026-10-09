local WV, L = WowVoice, WowVoiceLocale
local originalTooltip = GameTooltip
local metadata = C_AddOns.GetAddOnMetadata
local version = '0.6.0'
C_AddOns.GetAddOnMetadata = function(addon, field)
    if addon == 'CatQuest_Voices' and field == 'Version' then return version end
    return metadata and metadata(addon, field)
end

-- Model tooltip line creation/font assignment at Show, after AddLine. A skin
-- may likewise replace the fonts in OnShow. The old pre-Show adaptation is lost.
local tooltip = { lines = {}, regions = {}, hooks = {} }
local regionParent = CreateFrame('Frame', nil, UIParent)
GameTooltip = tooltip
local nativeFace = L.isEnglish and 'Fonts\\FRIZQT__.TTF' or L.cyrillicFont
function tooltip:GetName() return 'TalkingHeadRuTestTooltip' end
function tooltip:NumLines() return #self.lines end
function tooltip:HookScript(event, fn)
    assert(not self.hooks[event], 'Tooltip restoration hook must only be installed once')
    self.hooks[event] = fn
end
function tooltip:SetOwner(owner)
    self:Hide()
    self.owner, self.lines = owner, {}
end
function tooltip:IsOwned(owner) return self.owner == owner end
function tooltip:AddLine(text) self.lines[#self.lines + 1] = text end
function tooltip:Show()
    local opening = not self.visible
    self.visible = true
    self.layoutFonts = {}
    for i, text in ipairs(self.lines) do
        local region = self.regions[i] or regionParent:CreateFontString(nil, 'ARTWORK', 'GameTooltipText')
        self.regions[i] = region
        _G[self:GetName() .. 'TextLeft' .. i] = region
        if opening then region:SetFont(nativeFace, i == 1 and 16 or 12, 'OUTLINE') end
        region:SetText(text)
        -- Native Show lays out the tooltip even when already visible, but
        -- OnShow font replacement only runs on the hidden -> shown transition.
        self.layoutFonts[i] = region:GetFont()
    end
end
function tooltip:Hide()
    self.visible, self.owner = false, nil
    if self.hooks.OnHide then self.hooks.OnHide(self) end
end
local function checkShown(owner)
    owner.scripts.OnEnter(owner)
    assert(tooltip.visible and tooltip:IsOwned(owner))
    assert(#tooltip.lines == 2)
    for i, region in ipairs(tooltip.regions) do
        local face, size, flags = region:GetFont()
        assert(face == L.cyrillicFont, 'Russian tooltip text must retain Cyrillic font after Show')
        assert(tooltip.layoutFonts[i] == face,
            'Tooltip bounds must be measured with the displayed font, not the previous font')
        assert(size == (i == 1 and 16 or 12) and flags == 'OUTLINE')
    end
end
local function checkHidden(owner)
    owner.scripts.OnLeave(owner)
    assert(not tooltip.visible)
    for _, region in ipairs(tooltip.regions) do
        assert(region:GetFont() == nativeFace, 'Restore the tooltip font for other owners')
    end
end

WV:OpenOptions()
local options = frames.WowVoiceOptionsPanel
local warning = options.AudioSourceWarning
for _, installed in ipairs({'0.6.0', '0.2.2'}) do
    version = installed
    WV:RefreshAudioSourceOptions()
    assert(warning:IsShown())
    checkShown(warning)
    assert(tooltip.lines[2]:find(installed, 1, true))
    checkHidden(warning)
end
local schema = CatQuestVoicePack.schemaVersion
CatQuestVoicePack.schemaVersion = 999
WV:RefreshAudioSourceOptions()
checkShown(warning)
assert(tooltip.lines[2]:find('формат индекса', 1, true))
checkHidden(warning)
CatQuestVoicePack.schemaVersion = schema
WV:RefreshAudioSourceOptions()
checkShown(options.SharedVoiceTooltip)
checkHidden(options.SharedVoiceTooltip)

tooltip:SetOwner(UIParent)
tooltip:AddLine('Unrelated English tooltip')
tooltip:Show()
assert(tooltip.regions[1]:GetFont() == nativeFace)
tooltip:Hide()
GameTooltip, C_AddOns.GetAddOnMetadata = originalTooltip, metadata
WV:RefreshAudioSourceOptions()
print('PASS: ' .. GetLocale() .. ' Russian options tooltips survive Show font replacement, preserve size/flags and restore fonts for other owners')

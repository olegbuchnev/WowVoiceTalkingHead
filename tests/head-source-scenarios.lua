event('ADDON_LOADED')
local WV = WowVoice
assert(TalkingHeadRuDB.showVoiceSource == false, 'Source label must be opt-in')
assert(WV:ReplayQuest(179))
local head = frames.TalkingHeadRu
assert(not head.Source:IsShown())
local fullNameWidth = head.Name:GetWidth()
WV:OpenOptions()
local options = frames.WowVoiceOptionsPanel
assert(not options.ShowVoiceSource:GetChecked())
local played, stopped = #plays, #stops
options.ShowVoiceSource:SetChecked(true)
options.ShowVoiceSource.scripts.OnClick(options.ShowVoiceSource)
assert(head.Source:IsShown() and head.Source:GetText() == 'WowVoice')
assert(#plays == played and #stops == stopped, 'Showing source must not restart audio')
assert(head.Name:GetWidth() == fullNameWidth, 'Source must not reduce NPC name space')
for _, entry in ipairs({
    {'catquest', 'CatQuest', 1, 0.55, 0.2},
    {'wayfarer', 'Wayfarer', 0.4, 0.85, 0.45},
    {'wowvoice', 'WowVoice', 0.25, 0.7, 1},
}) do
    assert(WV:PreviewQuestAudio(179, 'sample.ogg', 10, nil, entry[1], true))
    assert(head.Source:GetText() == entry[2])
    for i = 1, 3 do assert(head.Source.textColor[i] == entry[i + 2]) end
end
-- Choosing a different preference does not relabel the currently playing file.
assert(WV:SetVoicePriority({'catquest', 'wayfarer', 'wowvoice'}))
assert(head.Source:GetText() == 'WowVoice')
local loaded = C_AddOns.IsAddOnLoaded
C_AddOns.IsAddOnLoaded = function(name) return name == 'WowVoiceSounds' end
WV:RefreshAudioSources()
assert(WV:ReplayQuest(179) and head.Source:GetText() == 'WowVoice', 'Show actual fallback library')
C_AddOns.IsAddOnLoaded = loaded
WV:RefreshAudioSources()
event('ADDON_LOADED')
assert(TalkingHeadRuDB.showVoiceSource == true, 'Enabled option must survive reload')
WV:FinishTalkingHead(true)
now = now + 0.5
head.scripts.OnUpdate()
assert(math.abs(head.Source.alpha - head.Name.alpha) < 0.0001, 'Source must fade with the head')
WV:SetShowVoiceSource(false)
assert(not head.Source:IsShown() and head.Name:GetWidth() == fullNameWidth)
event('ADDON_LOADED')
assert(TalkingHeadRuDB.showVoiceSource == false, 'Disabled option must survive reload')
WV:SetShowVoiceSource(true)
WV:Silence()
WV:ToggleHeadPreview()
assert(not head.Source:IsShown(), 'Silent player preview has no audio source')
WV:StopTalkingHead()
-- Unknown sources must not retain the previous line's library label.
local replaySpeaker = WV.GetReplaySpeaker
local sharedContext = replaySpeaker(WV, 179)
sharedContext.audioSourceID = 'catquest'
WV.GetReplaySpeaker = function() return sharedContext end
assert(WV:PreviewQuestAudio(179, 'sample.ogg', 10, nil, 'wowvoice', true))
assert(head.Source:GetText() == 'WowVoice' and sharedContext.audioSourceID == 'catquest',
    'Playback source must not mutate a reusable quest context')
assert(WV:PreviewQuestAudio(179, 'unknown.ogg', 10, nil, nil, true))
assert(not head.Source:IsShown())
assert(sharedContext.audioSourceID == 'catquest')
WV.GetReplaySpeaker = replaySpeaker
WV:Silence()
print('PASS: optional source label, all library colors, actual fallback, live toggle, reload, fade and silent/unknown previews')

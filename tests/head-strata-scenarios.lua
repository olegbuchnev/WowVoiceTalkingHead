local WV = WowVoice
TalkingHeadRuDB.headStrata = 'HIGH'
event('ADDON_LOADED')
WV:GetHeadSettings()
local head = TalkingHeadRu
assert(head:GetFrameStrata() == 'HIGH', 'saved layer applies when the head is created')
WV:EnsureQuestQueuePreview()
local player = frames.WowVoiceQuestQueuePlayer
assert(player:GetFrameStrata() == 'HIGH', 'a newly created player inherits the head layer')
WV:OpenOptions()
local panel = frames.WowVoiceOptionsPanel
assert(panel.StrataSlider.value == 4 and panel.StrataValue:GetText() == 'Высокий')
local sounds = #plays
for index, strata in ipairs({'BACKGROUND','LOW','MEDIUM','HIGH','DIALOG','FULLSCREEN','FULLSCREEN_DIALOG','TOOLTIP'}) do
    panel.StrataSlider:SetValue(index)
    assert(TalkingHeadRuDB.headStrata == strata and head:GetFrameStrata() == strata)
    assert(player:GetFrameStrata() == strata and player.AlignmentGuide:GetFrameStrata() == strata)
end
assert(#plays == sounds, 'layer changes do not restart or play audio')
assert(not WV:SetHeadStrata('INVALID') and TalkingHeadRuDB.headStrata == 'TOOLTIP')
panel.StrataSlider:SetValue(5)
WV:EnsureHeadPreview(true)
WV:BeginHeadScalePreview()
WV:SetHeadScale(1.1, true)
frames.WowVoiceHeadScaleCapture:RenderFrame()
frames.WowVoiceHeadScaleCapture:RenderFrame()
local snapshot = frames.WowVoiceHeadScaleSnapshot
assert(snapshot and snapshot:GetFrameStrata() == 'DIALOG')
WV:SetHeadStrata('LOW')
assert(snapshot:GetFrameStrata() == 'LOW' and player:GetFrameStrata() == 'LOW')
WV:EndHeadScalePreview()
assert(head:GetFrameStrata() == 'LOW', 'restoring a scaled snapshot must preserve the selected layer')
WV:OpenOptions(); WV:RefreshHeadOptions()
assert(panel.StrataSlider.value == 2 and panel.StrataValue:GetText() == 'Низкий')
TalkingHeadRuDB.headStrata = 'INVALID'
assert(WV:GetHeadStrata() == 'FULLSCREEN_DIALOG')
TalkingHeadRuDB.headStrata = nil
assert(WV:GetHeadStrata() == 'FULLSCREEN_DIALOG', 'old saved settings keep the former layer')
print('PASS: named layer slider, saved layer, player/guide inheritance, silent live updates and scale snapshot restoration')

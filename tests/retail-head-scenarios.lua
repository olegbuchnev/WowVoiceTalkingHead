-- Existing users may have hidden the head and selected either removed theme.
for _, preset in ipairs({'classic','ellesmere'}) do
    TalkingHeadRuDB = {headEnabled=false, headPreset=preset, headWidth=520,
        headHeight=200, headScale=1.2, headPosition={'CENTER','CENTER',123,-200},
        button='always', buttonPos={'CENTER','CENTER',0,100},
        autoPlayAccept=false, autoPlayAcceptDefaultOnApplied=true, playlistAutoPlayApplied=2,
        autoPlayTurnIn=false, trackerButtons=false, trackerProgressPulse=false}
    event('ADDON_LOADED')
    assert(TalkingHeadRuDB.headEnabled==nil and TalkingHeadRuDB.headPreset==nil)
    assert(TalkingHeadRuDB.button==nil and TalkingHeadRuDB.buttonPos==nil)
    assert(not TalkingHeadRuDB.autoPlayAccept and not TalkingHeadRuDB.autoPlayTurnIn
        and TalkingHeadRuDB.trackerButtons==nil and TalkingHeadRuDB.trackerProgressPulse==nil)
    assert(WowVoice:ReplayQuest(179))
    local head=frames.TalkingHeadRu
    assert(head.visible and head.RetailBackground.visible and head.PortraitOverlay.visible)
    assert(head.width==520 and head.height==200 and head.scale==1.2)
    local settings=WowVoice:GetHeadSettings()
    assert(settings.x==123 and settings.y==-200)
    assert(head.EllesmereBackground==nil and head.Close.Glyph==nil)
    command('options')
    local panel=frames.WowVoiceOptionsPanel
    assert(panel.Enabled==nil and panel.Presets==nil)
    assert(WowVoice.SetHeadEnabled==nil and WowVoice.SetHeadPreset==nil)
    assert(frames.WowVoiceStopButton==nil)
    head.Close.scripts.OnClick()
    assert(not head.visible)
    restored('1','0.37')
    panel.LockFrames:SetChecked(false)
    panel.LockFrames.scripts.OnClick(panel.LockFrames)
    assert(head.visible and head.Model.unit=='player')
    panel:Hide()
    assert(not head.visible)
end
print('PASS: disabled/Classic/Ellesmere preferences migrate to visible Retail, preserving geometry and playback choices; obsolete controls removed')

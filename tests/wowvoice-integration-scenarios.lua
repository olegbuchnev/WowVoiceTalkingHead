local test = upstreamTest
if upstreamTestMode == 'early-login' then
    assert(test.disableCalls == 0 and test.stops == 1, 'detach handlers even before the player is ready')
    test.playerReady = true
    local login = frames.WowVoiceDisableUpstream
    login.scripts.OnEvent(login, 'PLAYER_LOGIN')
    assert(next(login.events) == nil and not login.scripts.OnEvent)
end
assert(test.disableCalls == (upstreamTestMode == 'absent' and 0 or 1))
assert(test.saves == (upstreamTestMode == 'legacy' and 0 or test.disableCalls))
assert(C_AddOns.IsAddOnLoaded('WowVoiceSounds'), 'sound library must stay enabled')
assert(C_AddOns.IsAddOnLoaded('CatQuest') and C_AddOns.IsAddOnLoaded('CatQuest_Voices'))
if test.upstream then
    assert(C_AddOns.IsAddOnLoaded('WowVoice'), 'disabling cannot unload the existing runtime')
    assert(test.stops == 1 and test.callbacks == 0)
    assert(next(test.frame.events) == nil and not test.frame.scripts.OnEvent)
    assert(not test.ticker.visible and not test.ticker.scripts.OnUpdate)
    assert(not test.button.visible and not test.button.scripts.OnClick)
    assert(not SlashCmdList.WOWVOICE and not SLASH_WOWVOICE1 and not SLASH_WOWVOICE2)
    assert(WowVoice ~= test.upstream and WowVoiceFrame ~= test.frame and WowVoiceTicker ~= test.ticker)
    assert(WowVoiceDB == test.db and WowVoiceDB.enabled and WowVoiceDB.stopmode == test.stopmode)
else
    assert(test.stops == 0 and #plays == 0 and #stops == 0)
end
assert(not WowVoiceIndex.upstream and not WowVoiceDur.upstream, 'our metadata must replace upstream tables')
-- The client restores our SavedVariables after the TOC files, then delivers
-- ADDON_LOADED. Existing preferences must survive the takeover.
WowVoiceDB = {enabled=true, channel='sound', queueAutoPlay=false, sharedQuestVoice='wowvoice'}
event('ADDON_LOADED')
assert(WowVoiceDB.enabled and not WowVoiceDB.queueAutoPlay)
assert(SlashCmdList.WOWVOICETALKINGHEAD, 'our commands remain available')
assert(WowVoice:ReplayQuest(179) and #plays == 1, 'our player uses the still-enabled sound pack')
assert(plays[1].file:find('WowVoiceSounds', 1, true))
WowVoice:Silence()
assert(#stops == 1 and test.callbacks == 0, 'only our playback reacts to stop')
print('PASS: upstream takeover (' .. upstreamTestMode .. '), independent controls and sound library')

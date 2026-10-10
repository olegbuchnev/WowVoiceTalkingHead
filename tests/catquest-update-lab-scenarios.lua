event('ADDON_LOADED')
local WV, S, Q = WowVoice, WowVoiceAudioSources, WowVoice.questQueue
local run = SlashCmdList.WOWVOICECATQUESTUPDATELAB
local original, metadata, resolve, snapshot = CatQuestVoicePack.quests[179], S.Metadata, S.Resolve, WowVoiceCatQuestAudio
local preference = TalkingHeadRuDB.sharedQuestVoice
local importedText = S.Text(179,'a')
run('report')
assert(has('REPORT build=20261002-3 mode=reset oneshot=false trace=false lines=0'))
assert(has('Журнал пуст:'), 'report must explain an empty session instead of silently doing nothing')
run('future')
assert(S.Status().updated and S.Status().version == '0.6.0')
assert(S.Resolve(98430,'a').duration == 42.15 and CatQuestVoicePack.quests[179] == original)
run('changed')
assert(S.Resolve(179,'a').path:find('6_m.ogg',1,true) and not S.Resolve(179,'a').verified)
assert(S.Text(179,'a') == importedText, 'simulated audio updates cannot replace imported texts')
assert(S.Resolve(99998,'a').path:find('5.ogg',1,true) and WowVoiceComparison.Known(99998,'catquest'))
TalkingHeadRuDB.autoPlay, TalkingHeadRuDB.autoPlayAccept, TalkingHeadRuDB.queueAutoPlay = true, true, true
run('queue')
assert(Q.current.context.questId == 179 and Q.current.context.queueOwner == 'catquest-update-lab')
assert(Q:Count() == 2 and plays[#plays].file:find('6_m.ogg',1,true))
run('audited')
assert(Q:Count() == 0, 'changing the lab scenario clears only lab-owned queue records')
assert(not S.Status().updated and S.Resolve(179,'a').verified and S.Resolve(99998,'a').verified)
assert(S.Resolve(179,'a').duration == snapshot.entries['6a'].audio.male.duration)
run('invalid')
assert(not S.Resolve(179,'a') and S.Resolve(99998,'a'))
assert(WV:SoundPath(179,'a'):find('WowVoiceSounds',1,true))
run('missing')
assert(S.Resolve(99998,'a').path:find('99998.ogg',1,true))
assert(S.Resolve(179,'a').path:find('6_m.ogg',1,true))
run('reset')
assert(S.Metadata == metadata and S.Resolve == resolve and WowVoiceCatQuestAudio == snapshot)
assert(CatQuestVoicePack.quests[179] == original and CatQuestVoicePack.quests[99998] == nil)
assert(TalkingHeadRuDB.sharedQuestVoice == preference and not S.Status().updated)
-- The helper never replaces ordinary queued quests, even during reset.
Q:Offer({questId=179,section='a',title='Real quest'}); Q:Accept(179)
local current, playsBefore, stopsBefore = Q.current, #plays, #stops
run('changed'); run('queue'); run('reset')
assert(Q.current == current and #plays == playsBefore and #stops == stopsBefore)
Q:Clear()
-- Trace both tracks through completion, preserving timers and API results.
local originalMusic, originalStopMusic = PlayMusic, StopMusic
local musicCalls, musicStops = {}, 0
local observedMusic = function(path) musicCalls[#musicCalls+1] = path; return true end
PlayMusic = observedMusic
StopMusic = function() musicStops = musicStops + 1 end
local observedStopMusic = StopMusic
local startedMethod, stoppedMethod = Q.PlaybackStarted, Q.PlaybackStopped
local channel = TalkingHeadRuDB.channel
TalkingHeadRuDB.channel = 'music'
run('changed'); run('trace'); run('queue')
local firstStart = now
assert(Q.current.context.questId == 179 and musicCalls[#musicCalls]:find('6_m.ogg',1,true))
local firstDuration = S.Resolve(179,'a').duration
tick(firstStart + firstDuration - 0.01)
assert(musicStops == 0 and Q.current.status == 'playing')
tick(firstStart + firstDuration + TalkingHeadRuDB.tail + 0.01)
assert(musicStops == 1 and has('STOP 179 elapsed=') and has('reason=duration timer'))
tick(Q.gap.deadline)
frames.WowVoiceQuestQueueDriver.scripts.OnUpdate()
local secondStart, secondDuration = now, S.Resolve(99998,'a').duration
assert(Q.current.context.questId == 99998 and musicCalls[#musicCalls]:find('5.ogg',1,true))
run('mark')
assert(has('MARK 99998 elapsed=0.000'))
tick(secondStart + secondDuration - 0.01)
assert(musicStops == 1 and Q.current.context.questId == 99998 and Q.current.status == 'playing')
tick(secondStart + secondDuration + TalkingHeadRuDB.tail + 0.01)
assert(musicStops == 2 and Q.current == nil and has('STOP 99998 elapsed='))
assert(has('START 99998 timer=20.350') and has('OGG=20.061'))
run('solo')
assert(Q:Count() == 1 and Q.current.context.questId == 99998,
    'solo must use the same queue path with only the second recording')
tick(now + secondDuration + TalkingHeadRuDB.tail + 0.01)
assert(musicStops == 3 and Q.current == nil)
run('reset')
assert(PlayMusic == observedMusic and StopMusic == observedStopMusic)
assert(Q.PlaybackStarted == startedMethod and Q.PlaybackStopped == stoppedMethod)
local beforeReport = #messages
run('report')
assert(#messages > beforeReport, 'trace report remains readable after reset')
-- One-shot Music isolates the API without shortening the approximate timers.
local originalSound, originalStopSound = PlaySoundFile, StopSound
local background = cvars.Sound_EnableSoundWhenGameIsInBG
cvars.Sound_EnableSoundWhenGameIsInBG = '0'
run('changed'); run('oneshot'); run('trace'); run('queue')
local oneShotStart, oneShotHandle, beforeMusic = now, plays[#plays].handle, #musicCalls
assert(plays[#plays].channel == 'Music' and plays[#plays].file:find('6_m.ogg',1,true))
assert(has('oneshot=true background=0') and has('PlaySoundFile channel=Music'))
local expectedDuration = S.Resolve(179,'a').duration
tick(oneShotStart + snapshot.entries['6a'].audio.male.duration + 0.1)
assert(stops[#stops] ~= oneShotHandle and Q.current.context.questId == 179,
    'one-shot must not replace the approximate queue timer with lab-only measurements')
tick(oneShotStart + expectedDuration + TalkingHeadRuDB.tail + 0.01)
assert(stops[#stops] == oneShotHandle and #musicCalls == beforeMusic)
tick(Q.gap.deadline)
frames.WowVoiceQuestQueueDriver.scripts.OnUpdate()
assert(Q.current.context.questId == 99998 and plays[#plays].channel == 'Music')
oneShotHandle = plays[#plays].handle
run('reset')
assert(stops[#stops] == oneShotHandle and Q:Count() == 0)
assert(PlayMusic == observedMusic and StopMusic == observedStopMusic)
assert(PlaySoundFile == originalSound and StopSound == originalStopSound)
assert(cvars.Sound_EnableSoundWhenGameIsInBG == '0', 'background preference must not change')
-- Ordinary playback and foreign PlayMusic calls are not rerouted.
run('changed'); run('oneshot')
local beforeSound = #plays
assert(WV:ReplayQuest(179) and #plays == beforeSound)
assert(musicCalls[#musicCalls]:find('6_m.ogg',1,true))
WV:Silence()
run('solo')
oneShotHandle = plays[#plays].handle
PlayMusic('foreign.ogg')
assert(stops[#stops] == oneShotHandle and musicCalls[#musicCalls] == 'foreign.ogg')
run('reset')
-- Failed one-shot starts and logout release handles and temporary settings.
run('changed'); run('trace'); run('oneshot'); run('trace')
soundOK = false
run('solo')
assert(Q.current == nil and not frames.WowVoiceTicker.visible)
assert(cvars.Sound_DialogVolume == '0.37' and cvars.Sound_MusicVolume == '0.25')
soundOK = true
run('solo')
oneShotHandle = plays[#plays].handle
local labLifecycle = frames.WowVoiceCatQuestUpdateLabLifecycle
labLifecycle.scripts.OnEvent(labLifecycle, 'PLAYER_LOGOUT')
assert(stops[#stops] == oneShotHandle and Q:Count() == 0)
assert(PlayMusic == observedMusic and StopMusic == observedStopMusic)
assert(PlaySoundFile == originalSound and StopSound == originalStopSound)
-- With background enabled, the default test uses production Master, retaining disabled/quiet zone music.
-- No separate trace/channel steps or experimental Music interception required.
TalkingHeadRuDB.channel = 'auto'
local musicCount, musicStopCount = #musicCalls, musicStops
local setCVar = SetCVar
SetCVar = function(key, value)
    assert(key ~= 'Sound_EnableMusic' and key ~= 'Sound_MusicVolume',
        'Master test must never enable or raise zone music, even temporarily')
    assert(key ~= 'Sound_EnableSoundWhenGameIsInBG', 'Master test must preserve background preference')
    return setCVar(key, value)
end
cvars.Sound_EnableMusic, cvars.Sound_MusicVolume = '0', '0'
cvars.Sound_EnableSoundWhenGameIsInBG = '1'
run('test')
assert(Q:Count() == 2 and Q.current.context.questId == 179)
assert(TalkingHeadRuDB.channel == 'auto' and plays[#plays].channel == 'Master')
assert(has('oneshot=false') and has('PlaySoundFile RESULT ok=true handle='))
tick(now + S.Resolve(179,'a').duration + TalkingHeadRuDB.tail + 0.01)
tick(Q.gap.deadline)
frames.WowVoiceQuestQueueDriver.scripts.OnUpdate()
assert(Q.current.context.questId == 99998 and plays[#plays].channel == 'Master')
tick(now + S.Resolve(99998,'a').duration + TalkingHeadRuDB.tail + 0.01)
assert(Q.current == nil and #musicCalls == musicCount and musicStops == musicStopCount,
    'Master test must never start or stop the music stream')
local reportStart = #messages
run('report')
local reported = table.concat(messages, '\n', reportStart + 1)
assert(reported:find('PlaySoundFile channel=Master',1,true) and reported:find('musicEnabled=0 musicVolume=0',1,true))
assert(not reported:find('PlayMusic',1,true) and not reported:find('StopMusic',1,true))
assert(reported:find('STOP 179',1,true) and reported:find('STOP 99998',1,true))
run('reset')
assert(TalkingHeadRuDB.channel == 'auto' and PlayMusic == observedMusic and StopMusic == observedStopMusic)
for _, enabled in ipairs({'0','1'}) do
    for _, volume in ipairs({'0','0.03'}) do
        cvars.Sound_EnableMusic, cvars.Sound_MusicVolume = enabled, volume
        run('test solo')
        assert(Q:Count() == 1 and Q.current.context.questId == 99998 and plays[#plays].channel == 'Master')
        run('reset')
        assert(TalkingHeadRuDB.channel == 'auto' and cvars.Sound_EnableMusic == enabled and cvars.Sound_MusicVolume == volume)
    end
end
soundOK = false
run('test solo')
assert(Q.current == nil and not frames.WowVoiceTicker.visible)
run('reset')
soundOK = true
SetCVar = setCVar
-- Background-off keeps the established PlayMusic route. A preference change
-- does not restart the active line; the next line switches to Master.
cvars.Sound_EnableMusic, cvars.Sound_MusicVolume = '0', '0.03'
cvars.Sound_EnableSoundWhenGameIsInBG = '0'
TalkingHeadRuDB.channel = 'sound'
local autoPlayCount = #plays
run('test')
assert(TalkingHeadRuDB.channel == 'auto' and #plays == autoPlayCount)
assert(musicCalls[#musicCalls]:find('6_m.ogg',1,true) and cvars.Sound_EnableSoundWhenGameIsInBG == '0')
local autoMusicCount, autoStops = #musicCalls, musicStops
cvars.Sound_EnableSoundWhenGameIsInBG = '1'
tick(now + 1)
assert(#musicCalls == autoMusicCount and #plays == autoPlayCount and musicStops == autoStops,
    'changing background preference must not move or restart active Music')
tick(now + S.Resolve(179,'a').duration + TalkingHeadRuDB.tail)
assert(cvars.Sound_EnableMusic == '0' and cvars.Sound_MusicVolume == '0.03')
tick(Q.gap.deadline)
frames.WowVoiceQuestQueueDriver.scripts.OnUpdate()
assert(Q.current.context.questId == 99998 and plays[#plays].channel == 'Master')
run('reset')
assert(TalkingHeadRuDB.channel == 'sound', 'reset restores the preference from before the automatic test')
-- A blocked experiment must preserve the player's queue and preference.
TalkingHeadRuDB.channel = 'sound'
Q:Offer({questId=179,section='a',title='Real quest'}); Q:Accept(179)
local ordinary, ordinaryPlays = Q.current, #plays
run('test')
assert(Q.current == ordinary and #plays == ordinaryPlays and TalkingHeadRuDB.channel == 'sound')
Q:Clear()
cvars.Sound_EnableSoundWhenGameIsInBG = background
PlayMusic, StopMusic, TalkingHeadRuDB.channel = originalMusic, originalStopMusic, channel
run('future')
local lifecycle = frames.WowVoiceCatQuestUpdateLabLifecycle
lifecycle.scripts.OnEvent(lifecycle,'PLAYER_LOGOUT')
assert(S.Metadata == metadata and S.Resolve == resolve and TalkingHeadRuDB.sharedQuestVoice == preference)
print('PASS: update lab scenarios, isolated queue/solo, both Music track timers, diagnostic hooks/report and reset restoration')

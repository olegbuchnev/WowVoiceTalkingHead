local WV, Q = WowVoice, WowVoice.questQueue
event('ADDON_LOADED')
local paused = restoreTestCase == 'paused'
TalkingHeadRuDB.queueAutoPlay = not paused
TalkingHeadRuQueueDB = {version = 1, savedAt = serverNow - 15, paused = paused,
    records = {
        {context = {questId = 179, section = 'a', title = 'Interrupted quest', text = 'Quest text'}, started = true},
        {context = {questId = 183, section = 'a', title = 'Next quest', text = 'Next text'}},
    }}
local events, driver = frames.WowVoiceQuestQueueEvents, frames.WowVoiceQuestQueueDriver
local function send(name) events.scripts.OnEvent(events, name) end
local function step() if driver:IsShown() then driver.scripts.OnUpdate() end end
local disabledFirst = restoreTestCase == 'disabled-first'
local legacy = restoreTestCase == 'legacy'
if disabledFirst then send('LOADING_SCREEN_DISABLED') end
send('PLAYER_ENTERING_WORLD')
if restoreTestCase == 'silent' or restoreTestCase == 'stale-silent' then
    send('LOADING_SCREEN_DISABLED'); step()
    assert(Q:Count() == 0 and not Q.current and #plays == 0,
        'a saved queue cannot restore recordings from disabled libraries')
    assert(not TalkingHeadRu or not TalkingHeadRu:IsShown())
    print('PASS: unavailable saved recordings discarded: ' .. restoreTestCase)
    return
end
assert(Q:Count() == 2 and not Q.current and #plays == 0)
if not disabledFirst and not legacy then
    step()
    tick(now + 35)
    step()
    assert(not Q.current and #plays == 0, 'no audio or playback clock during loading')
    send('LOADING_SCREEN_DISABLED')
end
local staleFrame = restoreTestCase:find('stale-', 1, true) ~= nil
if staleFrame then frameLag = 4 end
step()
-- Next render catches up to the real time at which playback began.
now, frameLag = now + frameLag, 0
if paused then
    assert(not Q.current and Q.paused and #plays == 0 and not TalkingHeadRuDB.queueAutoPlay)
    WV:SetQueueAutoPlay(true)
end
assert(Q.current and Q.current.context.questId == 179 and Q.current.status == 'playing')
local startedAt, played = now, #plays
local duration = select(2, WV:SoundPath(179, 'a'))
assert(played == 1)
local music = restoreTestCase == 'music' or restoreTestCase == 'stale-music'
assert(plays[1].channel == (music and 'Music' or 'Master'))
TalkingHeadRu.scripts.OnUpdate()
assert(TalkingHeadRu.Progress.value == 0, 'head progress starts at zero')
tick(startedAt + duration / 2)
send('PLAYER_ENTERING_WORLD')
if not legacy then send('LOADING_SCREEN_DISABLED') end
step()
assert(#plays == played, 'later world/loading events cannot restart audio')
tick(startedAt + duration - 0.01)
assert(Q.current.status == 'playing' and not Q.gap, 'full new duration must elapse')
tick(startedAt + duration + (music and 0 or TalkingHeadRuDB.tail) + 0.0001)
assert(Q.current.status == 'done' and Q.gap, 'full duration completes normally')
tick(Q.gap.deadline); step()
assert(Q.current.context.questId == 183 and #plays == played + 1,
    'the remaining playlist advances normally')
print('PASS: loading-safe full-duration queue restart: ' .. restoreTestCase)

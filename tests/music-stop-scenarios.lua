event('ADDON_LOADED')
local WV, Q = WowVoice, WowVoice.questQueue
local music = {}
function PlayMusic(path) music[#music + 1] = path; return true end
local silence = 'Interface\\AddOns\\WowVoiceTalkingHead\\Media\\silence.ogg'
cvars.Sound_EnableSoundWhenGameIsInBG = '0'
cvars.Sound_EnableMusic = '0'
local function atEnd(duration, offset, start)
    local count = #music
    tick(start + duration + offset - 0.0001)
    assert(#music == count, 'Music stopped before its scheduled end')
    tick(start + duration + offset + 0.0001)
    assert(#music == count + 1 and music[#music] == silence,
        'Music must stop on the first frame at its deadline')
    assert(cvars.Sound_EnableMusic == '0' and cvars.Sound_EnableSoundWhenGameIsInBG == '0')
end
-- Both audited packs, every production entry point, positive and manual offsets.
for _, source in ipairs({'wowvoice', 'catquest'}) do
    assert(WV:SetSharedQuestVoice(source))
    local _, duration, _, _, verified = WV:SoundPath(1095, 'a')
    assert(verified == true)
    for _, tail in ipairs({0.05, 0.3, 0, -0.025}) do
        WowVoiceDB.tail = tail
        for _, entry in ipairs({'replay', 'event', 'queue', 'comparison'}) do
            Q:Clear()
            if entry == 'replay' then assert(WV:ReplayQuest(1095))
            elseif entry == 'event' then questID = 1095; event('QUEST_DETAIL')
            elseif entry == 'queue' then
                assert(Q:Start({context = {questId = 1095, section = 'a', text = 'Text'}}))
            else assert(WowVoiceComparison.Play(1095, source)) end
            assert(music[#music] == WV:SoundPath(1095, 'a'))
            atEnd(duration, math.min(tail, 0), now)
            assert(WowVoiceDB.tail == tail, 'Do not overwrite saved transport settings')
        end
    end
end
Q:Clear()
WowVoiceDB.tail = 0.05
-- Changed CatQuest records retain the estimate and both existing pads.
local record = CatQuestVoicePack.quests[1095]
local original = record.d
record.d = original + 1
local _, duration, _, _, verified = WV:SoundPath(1095, 'a')
assert(verified == false and duration == record.d + 0.25)
assert(WV:ReplayQuest(1095))
atEnd(duration, 0.05, now)
record.d = original
Q:Clear()
-- Unverified explicit previews cannot claim exact timing.
local path = WV:SoundPath(1095, 'a')
assert(WV:PreviewQuestAudio(1095, path, 3, 'Text', 'catquest'))
atEnd(3, 0.05, now)
Q:Clear()
-- Master retains its existing timer.
cvars.Sound_EnableSoundWhenGameIsInBG = '1'
assert(WV:SetSharedQuestVoice('wowvoice') and WV:ReplayQuest(1095))
local start, stopped = now, #stops
duration = select(2, WV:SoundPath(1095, 'a'))
tick(start + duration + 0.0001)
assert(#stops == stopped)
tick(start + duration + 0.0501)
assert(#stops == stopped + 1)
Q:Clear()
-- Queue gaps follow audio termination and cannot extend the Music loop.
cvars.Sound_EnableSoundWhenGameIsInBG = '0'
assert(WV:ReplayQuest(1095))
Q:Offer({questId = 179, section = 'a', text = 'Next quest'})
Q:Accept(179)
atEnd(duration, 0, now)
assert(Q.gap and Q.current.status == 'done')
local deadline, count = Q.gap.deadline, #music
tick(deadline - 0.0001)
frames.WowVoiceQuestQueueDriver.scripts.OnUpdate()
assert(#music == count and Q.gap)
tick(deadline)
frames.WowVoiceQuestQueueDriver.scripts.OnUpdate()
assert(Q.current.context.questId == 179 and #music == count + 1)
Q:Clear()
print('PASS: verified Music stops without positive padding; Classic 1095, CatQuest, all playback paths, estimates, Master and queue gaps')

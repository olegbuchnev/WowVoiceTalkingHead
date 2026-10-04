event('ADDON_LOADED')
local WV, Q = WowVoice, WowVoice.questQueue
local loaded = {}
C_AddOns.IsAddOnLoaded = function(name) return loaded[name] == true end
event('PLAYER_LOGIN')
assert(not WV:HasQuestAudio(179) and not WV:CanPresentQuest(179))
assert(not WV:CanPresentQuest(999999) and not WV:CanPresentQuest(0) and not WV:CanPresentQuest(nil))
local realPlay, realStop, realMusic, realStopMusic, realCVar = PlaySoundFile, StopSound, PlayMusic, StopMusic, SetCVar
function PlaySoundFile() error('Unavailable audio called PlaySoundFile') end
function StopSound() error('Unavailable audio called StopSound') end
function PlayMusic() error('Unavailable audio called PlayMusic') end
function StopMusic() error('Unavailable audio called StopMusic') end
function SetCVar() error('Unavailable audio changed sound settings') end
local function record(id, section)
    return { context = { questId = id, section = section or 'a', text = 'Quest text',
        speaker = { npcID = 658, name = 'Speaker' } } }
end
local function noPresentation()
    assert(not Q.current and Q:Count() == 0)
    assert(not frames.WowVoiceTalkingHead or not frames.WowVoiceTalkingHead:IsShown())
end
-- Neither library: all transports and stages reject automatic/manual playback.
for _, channel in ipairs({'auto', 'music', 'sound'}) do
    for _, background in ipairs({'0', '1'}) do
        WowVoiceDB.channel = channel
        cvars.Sound_EnableSoundWhenGameIsInBG = background
        for _, section in ipairs({'a', 'p', 'c'}) do
            local item = record(179, section)
            Q:Offer(item.context); Q:Accept(179)
            assert(not Q:Start(item))
            noPresentation()
        end
        questID = 179
        event('QUEST_DETAIL'); event('QUEST_PROGRESS'); event('QUEST_COMPLETE')
        assert(not WV:ReplayQuest(179))
        noPresentation()
    end
end
PlaySoundFile, StopSound, PlayMusic, StopMusic, SetCVar = realPlay, realStop, realMusic, realStopMusic, realCVar
WowVoiceDB.channel = 'auto'
cvars.Sound_EnableSoundWhenGameIsInBG = '1'
loaded.WowVoiceSounds, loaded.CatQuest_Voices = true, true
WV:RefreshAudioSources()
-- Real reported quest: description exists, progress and turn-in do not.
assert(WV:SoundPath(86576, 'a') and not WV:SoundPath(86576, 'p') and not WV:SoundPath(86576, 'c'))
assert(not WV:SoundPath(999999, 'a'), 'Unknown IDs cannot invent Classic filenames')
assert(WV:ReplayQuest(179))
local current, count = Q.current, #plays
questID = 86576
event('QUEST_PROGRESS'); event('QUEST_COMPLETE')
assert(Q.current == current and Q:Count() == 1 and #plays == count,
    'Missing stages must not interrupt current audio or queue a silent head')
Q:Clear()
event('QUEST_PROGRESS'); event('QUEST_COMPLETE')
noPresentation()
event('QUEST_DETAIL')
assert(Q.current and plays[#plays].file:find('86576.ogg', 1, true))
Q:Clear()
-- Recheck a pending offer when accepted after source availability changes.
assert(WV:ReplayQuest(179))
Q:Offer(record(86576).context)
loaded.CatQuest_Voices = false
Q:Accept(86576)
assert(Q:Count() == 1 and Q.current.context.questId == 179)
Q:Clear()
-- Restore drops old unvoiced entries, preserves voiced ones and a paused state.
WowVoiceQueueDB = {version = 1, savedAt = GetServerTime(), paused = true, records = {
    record(86576, 'c'), record(86576), record(179), record(999999),
}}
Q:RestoreSession()
assert(Q:Count() == 1 and Q.paused and Q:Waiting().context.questId == 179)
assert(not frames.WowVoiceTalkingHead:IsShown())
assert(Q:Start(Q:Waiting(), true) and Q.current.context.questId == 179)
Q:Clear()
loaded.WowVoiceSounds = false
WowVoiceQueueDB = {version = 1, savedAt = GetServerTime(), records = {record(179)}}
Q:RestoreSession()
noPresentation()
-- Late loading restores real playback normally.
loaded.CatQuest_Voices = true
WV:RefreshAudioSources()
assert(WV:ReplayQuest(179) and plays[#plays].file:find('CatQuest_Voices', 1, true))
Q:Clear()
print('PASS: missing libraries/stages never show a head, real 86576 regression, admission/acceptance/restore and late audio loading')

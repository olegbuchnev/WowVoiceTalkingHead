local WV, S, Q = WowVoice, WowVoiceAudioSources, WowVoice.questQueue
local pack, quests = CatQuestVoicePack, CatQuestVoicePack.quests
local metadata = C_AddOns.GetAddOnMetadata
local version = '0.5.0'
C_AddOns.GetAddOnMetadata = function(name, field)
    if name == 'CatQuest_Voices' and field == 'Version' then return version end
    return metadata(name, field)
end
local sex, originalSex = 2, UnitSex
UnitSex = function() return sex end
WV:OpenOptions()
local panel = frames.WowVoiceOptionsPanel
assert(WV:SetSharedQuestVoice('catquest'))
local snapshot = WowVoiceCatQuestAudio.sourceVersion
assert(snapshot == '0.5.0' and not S.Status().updated and not panel.AudioSourceWarning:IsShown())
assert(WowVoiceQuestTexts.sourceVersion == '0.5.0' and WowVoiceCatQuestSpeakers.sourceVersion == '0.5.0')
-- Real 0.5.0 replacements: independently measured recordings and live metadata.
-- These live fields come from the external index, independently of the snapshot.
local previousFive, previousTwentySeven = quests[5], quests[27]
quests[5] = {d=20.1,v='human-male'}
quests[27] = {t={d=32.7,v='nightelf-male#54'}}
local migrated = S.Resolve(5, 'a')
assert(migrated and migrated.duration == 20.0605 and migrated.path:find('\\5.ogg', 1, true))
assert(WV:ReplayQuest(5) and plays[#plays].file == migrated.path)
local handle = plays[#plays].handle
tick(now + 19.893625)
assert(stops[#stops] ~= handle, 'the timer must not cut the current recording short')
tick(now + (20.0605 - 19.893625) + TalkingHeadRuDB.tail + 0.01)
assert(stops[#stops] == handle)
for _, playerSex in ipairs({2,3}) do
    sex = playerSex
    local resolved = S.Resolve(27, 'c')
    assert(resolved and resolved.path:find('\\27_t.ogg', 1, true) and resolved.duration == 32.696792)
    assert(S.Text(27, 'c'):find('Мой поклон юному друиду.', 1, true))
end
quests[5], quests[27], sex = previousFive, previousTwentySeven, 2
assert(S.Text(251, 'a'):find('Отнесите записку Шире Фон-Инди.', 1, true), 'same-duration wording changes must also be imported')
print('PASS: 0.5.0 replacements use measured timings, current texts and NPC snapshot')
-- New description, recovered JSON-only completion, and changed sex variants.
assert(S.Resolve(10, 'a').verified and S.Resolve(10, 'a').duration == 30.94725)
assert(S.Text(10, 'a'):find('младшего геодезиста Холстомера', 1, true))
assert(S.Resolve(16, 'c').verified and S.Resolve(16, 'c').duration == 4.373417)
assert(not S.Resolve(16, 'a') and not S.Text(16, 'c'))
assert(S.Resolve(99080, 'a').verified and S.Text(99080, 'c'))
assert(S.Resolve(2, 'a').verified and S.Resolve(2, 'a').duration == 18.530875)
assert(S.Resolve(251, 'a').verified and S.Resolve(251, 'a').duration == 10.081333)
for _, variant in ipairs({{2, 'm', 33.4065}, {3, 'f', 33.7015}}) do
    sex = variant[1]
    local added = S.Resolve(25, 'a')
    assert(added.verified and added.duration == variant[3])
    assert(added.path:find('\\25_' .. variant[2] .. '.ogg', 1, true))
    assert(S.Text(25, 'a') and S.Resolve(25, 'c').duration == 25.05125)
end
sex = 2
print('PASS: real 0.5.0 new quest variants and replaced audio use freshly measured durations and imported texts')
version = '0.6.0'; WV:RefreshAudioSources()
assert(snapshot == '0.5.0' and S.Status().updated and S.Status().version == '0.6.0')
assert(WV:GetSharedQuestVoice() == 'catquest' and panel.VoicePriorityRows[1].sourceID == 'catquest' and panel.VoicePriorityRows[1].available)
-- Changed durations must use the live index, independently for each section.
local original = quests[179]
quests[179] = {d=original.d + 1, g=original.g, v=original.v, c=original.c, t=original.t}
assert(S.Resolve(179, 'a').duration == original.d + 1.25 and S.Resolve(179, 'c'))
assert(WV:SoundPath(179, 'a'):find('CatQuest_Voices', 1, true))
assert(WV:SoundPath(179, 'c'):find('CatQuest_Voices', 1, true))
assert(S.Resolve(99108, 'a'), 'a changed shared recording cannot disable unrelated unique quests')
quests[179] = original
quests[179] = nil
assert(not S.Resolve(179,'a') and not WowVoiceComparison.Known(179,'catquest'),
    'a removed live recording must not be resurrected from the snapshot')
quests[179] = original
local record = quests[99108]
local voice, gender, duration, cues = record.v, record.g, record.d, record.c
for _, change in ipairs({
    function() record.v = 'unknown-new-voice' end,
    function() record.g = nil end,
    function() record.c = {m={{0, 'Changed transcript'}},f={{0, 'Changed transcript'}}} end,
    function() record.c = nil end,
}) do
    change()
    assert(S.Resolve(99108, 'a') and not S.Resolve(99108, 'a').verified)
    assert(S.Resolve(179, 'a') and S.Resolve(99162, 'a'))
    record.v, record.g, record.d, record.c = voice, gender, duration, cues
end
-- Invalid necessary metadata blocks only its own recording; subtitles/voice
-- are optional and must not mute a valid OGG.
for _, invalid in ipairs({false, '30', 0, -1, math.huge, 0/0}) do
    record.d = invalid
    assert(not S.Resolve(99108, 'a') and S.Resolve(99108, 'c'))
    assert(S.Resolve(179, 'a') and S.Resolve(99162, 'a'))
end
record.d = nil
assert(not S.Resolve(99108, 'a'))
record.d = duration
record.g = 'new-format'
assert(not S.Resolve(99108, 'a') and S.Resolve(99108, 'c'))
record.g = gender
local savedShared = quests[179]
quests[179] = {d=-1,t=savedShared.t}
assert(WV:SoundPath(179, 'a'):find('WowVoiceSounds', 1, true))
quests[179] = savedShared
for _, playerSex in ipairs({2, 3}) do
    sex = playerSex
    local resolved = S.Resolve(98430, 'a')
    assert(resolved and resolved.duration == quests[98430].d + 0.25)
    assert(resolved.path:find(playerSex == 3 and '_f.ogg' or '_m.ogg', 1, true))
end
sex = 2
assert(not S.Resolve(16, 'c'), 'new releases cannot inherit JSON-only files absent from their live index')
-- This fixture is independent of our snapshots: new ID, new text, new voice,
-- new gender layout. It can be tested before any real upstream release.
local newID = 99998
assert(not WowVoiceCatQuestAudio.entries[newID .. 'a'] and not WowVoiceQuestTexts.entries[newID .. 'a'])
quests[newID] = {d=10,g=1,v='future-voice',c={m={{0,'New male text.'}},f={{0,'New female text.'}}},
    t={d=3,c={x={{0,'New turn-in.'}}}}}
for _, playerSex in ipairs({2,3}) do
    sex = playerSex
    local resolved = S.Resolve(newID, 'a')
    assert(resolved and resolved.duration == 10.25 and not resolved.verified)
    assert(resolved.path:find(playerSex == 3 and '_f.ogg' or '_m.ogg', 1, true))
    assert(S.Text(newID,'a') == nil, 'new transcripts require a database import')
    assert(WV:ReplayQuest(newID))
    WV:Silence()
end
sex = 2
assert(S.Resolve(newID,'c').path:find('99998_t.ogg',1,true))
assert(S.QuestIDs()[newID] and WowVoiceComparison.QuestIDs()[newID])
assert(WowVoiceComparison.Known(newID,'catquest') and not WowVoiceComparison.Known(newID,'wowvoice'))
assert(WowVoiceComparison.Play(newID,'catquest') and plays[#plays].file == S.Resolve(newID,'a').path)
assert(frames.TalkingHeadRu.Body:GetText() ~= 'New male text.', 'preview must use the independent text database')
WV:Silence()
record.c = {m={{0,' Changed wording. '},{3,'Second sentence.'}},f={{0,'New female wording.'}}}
local importedText = S.Text(99108,'a')
assert(importedText and importedText ~= 'Changed wording. Second sentence.')
assert(WV:ReplayQuest(99108) and frames.TalkingHeadRu.Body:GetText() == importedText)
WV:Silence()
record.c = nil
assert(S.Text(99108,'a','catquest') == importedText,
    'audio metadata changes cannot remove imported quest text')
record.c = {m={{0,false}}}
assert(S.Text(99108,'a','catquest') == importedText and S.Resolve(99108,'a'), 'invalid optional subtitles cannot mute audio')
record.c = cues
-- Real old-pack counterexample to using only a 0.1s rounding allowance:
-- Voices 0.2.0 quest 132 declares 21s but its OGG is 21.180792s long.
local old132 = quests[132]
quests[132] = {d=21}
assert(S.Resolve(132,'a').duration == 21.25 and WV:ReplayQuest(132))
local oldPackHandle, oldPackStarted = plays[#plays].handle, now
tick(oldPackStarted + 21.180792)
assert(stops[#stops] ~= oldPackHandle, 'small index errors must not cut this old-pack recording')
tick(oldPackStarted + 21.25 + TalkingHeadRuDB.tail + 0.01)
assert(stops[#stops] == oldPackHandle)
quests[132] = old132
-- Runtime CatQuest remains usable even when our optional snapshots are absent.
local savedAudio, savedTexts = WowVoiceCatQuestAudio, WowVoiceQuestTexts
WowVoiceCatQuestAudio, WowVoiceQuestTexts = nil, nil
assert(S.Status() and S.Status().updated and S.Resolve(newID,'a'))
assert(S.Text(newID,'a') == nil and WowVoiceComparison.QuestIDs()[newID])
WowVoiceCatQuestAudio, WowVoiceQuestTexts = savedAudio, savedTexts
for _, futureVersion in ipairs({'0.6.0', '1.0.0', ''}) do
    version = futureVersion
    WV:RefreshAudioSources()
    assert(S.Resolve(99162, 'a') and WV:GetSharedQuestVoice() == 'catquest')
end
version = nil
WV:RefreshAudioSources()
assert(S.Resolve(99162, 'a') and not S.Resolve(16, 'c'))
version = '0.6.0'
WV:RefreshAudioSources()
-- Updated records play through the existing queue, and one missing OGG does
-- not poison another quest or the independently installed Classic library.
Q:Clear()
local first, second = S.Resolve(newID, 'a'), S.Resolve(99108, 'a')
local function context(id)
    return {questId=id,section='a',title='Updated library',speaker={npcID=id,name='NPC'}}
end
TalkingHeadRuDB.autoPlay, TalkingHeadRuDB.autoPlayAccept, TalkingHeadRuDB.queueAutoPlay = true, true, true
Q:Offer(context(newID)); Q:Accept(newID)
Q:Offer(context(99108)); Q:Accept(99108)
assert(Q.current.context.questId == newID and Q:Count() == 2 and plays[#plays].file == first.path)
local activeHandle, playCount, stopCount = plays[#plays].handle, #plays, #stops
WV:RefreshAudioSources()
assert(#plays == playCount and #stops == stopCount and Q.current.context.questId == newID,
    'source refresh must retain active audio, head and queue')
tick(now + first.duration - 0.01)
assert(Q.current.context.questId == newID and stops[#stops] ~= activeHandle)
tick(now + TalkingHeadRuDB.tail + 0.03)
tick(Q.gap.deadline)
frames.WowVoiceQuestQueueDriver.scripts.OnUpdate()
assert(Q.current.context.questId == 99108 and plays[#plays].file == second.path)
Q:Clear()
soundOK = false
assert(not WV:ReplayQuest(99162) and not WV:HasQuestAudio(99162))
soundOK = true
assert(WV:HasQuestAudio(99108) and WV:HasQuestAudio(179))
-- Music transport uses the same approximate timer and advances the same queue.
local playMusic, stopMusic, background = PlayMusic, StopMusic, cvars.Sound_EnableSoundWhenGameIsInBG
local music, musicStops = {}, 0
PlayMusic = function(path) music[#music+1] = path; return true end
StopMusic = function() musicStops = musicStops + 1 end
cvars.Sound_EnableSoundWhenGameIsInBG = '0'
Q:Offer(context(newID)); Q:Accept(newID)
Q:Offer(context(99108)); Q:Accept(99108)
assert(Q.current.context.questId == newID and music[#music] == first.path)
local started = now
tick(started + first.duration - 0.01)
assert(Q.current.context.questId == newID)
tick(started + first.duration + TalkingHeadRuDB.tail + 0.01)
assert(musicStops > 0)
tick(Q.gap.deadline)
frames.WowVoiceQuestQueueDriver.scripts.OnUpdate()
assert(Q.current.context.questId == 99108 and music[#music] == second.path)
Q:Clear()
PlayMusic, StopMusic, cvars.Sound_EnableSoundWhenGameIsInBG = playMusic, stopMusic, background
-- A future audited import automatically replaces live estimates by exact
-- sex-specific timing, without resetting the user's choice.
local beforeVersion = savedAudio.sourceVersion
savedAudio.entries[newID .. 'a'] = {indexDuration=10,gender=true,voice='future-voice',
    audio={male={file='99998_m.ogg',duration=9.95},female={file='99998_f.ogg',duration=8.75}}}
savedAudio.sourceVersion = version
for _, playerSex in ipairs({2,3}) do
    sex = playerSex
    WV:RefreshAudioSources()
    assert(not S.Status().updated and not panel.AudioSourceWarning:IsShown())
    assert(WV:GetSharedQuestVoice() == 'catquest')
    assert(S.Resolve(newID,'a').verified and S.Resolve(newID,'a').duration == (sex == 3 and 8.75 or 9.95))
end
savedAudio.entries[newID .. 'a'], savedAudio.sourceVersion, quests[newID], sex = nil, beforeVersion, nil, 2
pack.schemaVersion = 2
assert(not S.Status(), 'declared unsupported index schema cannot be played')
pack.schemaVersion = nil
version = snapshot; WV:RefreshAudioSources()
assert(S.Resolve(98430, 'a').duration == WowVoiceCatQuestAudio.entries['98430a'].audio.male.duration)
assert(S.Resolve(16, 'c') and WowVoiceCatQuestAudio.sourceVersion == snapshot)
panel:Hide()
UnitSex, C_AddOns.GetAddOnMetadata = originalSex, metadata
print('PASS: unverified CatQuest uses live new/changed records, sex/text/catalogue and both queue transports; snapshots optional, exact timing restored after audit')

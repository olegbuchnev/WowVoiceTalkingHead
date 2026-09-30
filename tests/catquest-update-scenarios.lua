local WV, S, Q = WowVoice, WowVoiceAudioSources, WowVoice.questQueue
local pack, quests = CatQuestVoicePack, CatQuestVoicePack.quests
local metadata = C_AddOns.GetAddOnMetadata
local version = '0.3.0'
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
assert(snapshot == '0.3.0' and not S.Status().updated and not panel.AudioSourceWarning:IsShown())
assert(WowVoiceCatQuestTexts.sourceVersion == '0.3.0' and WowVoiceCatQuestSpeakers.sourceVersion == '0.3.1')
-- Real 0.3.0 changes: longer recording and a renamed common turn-in file.
-- These live fields come from the external index, independently of the snapshot.
local previousFive, previousTwentySeven = quests[5], quests[27]
quests[5] = {d=20.1,v='human-male'}
quests[27] = {t={d=32.1,v='nightelf-male#54'}}
local migrated = S.Resolve(5, 'a')
assert(migrated and migrated.duration == 20.10425 and migrated.path:find('\\5.ogg', 1, true))
assert(WV:ReplayQuest(5) and plays[#plays].file == migrated.path)
local handle = plays[#plays].handle
tick(now + 19.893625)
assert(stops[#stops] ~= handle, 'the old 0.2.2 duration must not end the longer 0.3.0 recording')
tick(now + (20.10425 - 19.893625) + WowVoiceDB.tail + 0.01)
assert(stops[#stops] == handle)
for _, playerSex in ipairs({2,3}) do
    sex = playerSex
    local resolved = S.Resolve(27, 'c')
    assert(resolved and resolved.path:find('\\27_t.ogg', 1, true) and resolved.duration == 32.056875)
    assert(S.Text(27, 'c'):find('Мой поклон юному друиду.', 1, true))
end
quests[5], quests[27], sex = previousFive, previousTwentySeven, 2
assert(S.Text(251, 'a'):find('Отнесите записку Шире Фон-Инди.', 1, true), 'same-duration wording changes must also be imported')
print('PASS: migrated 0.3.0 records use new timings, common filenames and texts; 0.3.1 NPC snapshot is loaded')
version = '0.4.0'; WV:RefreshAudioSources()
assert(snapshot == '0.3.0' and S.Status().updated and S.Status().version == '0.4.0')
assert(WV:GetSharedQuestVoice() == 'catquest' and panel.SharedVoiceButtons.catquest:IsEnabled())
-- Metadata changes affect only their own sections, with Classic fallback.
local original = quests[179]
quests[179] = {d=original.d + 1, g=original.g, v=original.v, c=original.c, t=original.t}
assert(not S.Resolve(179, 'a') and S.Resolve(179, 'c'))
assert(WV:SoundPath(179, 'a'):find('WowVoiceSounds', 1, true))
assert(WV:SoundPath(179, 'c'):find('CatQuest_Voices', 1, true))
assert(S.Resolve(99108, 'a'), 'a changed shared recording cannot disable unrelated unique quests')
quests[179] = original
local record = quests[99108]
local voice, gender, duration, cues = record.v, record.g, record.d, record.c
for _, change in ipairs({
    function() record.v = 'unknown-new-voice' end,
    function() record.g = not gender end,
    function() record.d = nil end,
    function() record.c = {m={{0, 'Changed transcript'}},f={{0, 'Changed transcript'}}} end,
    function() record.c = nil end,
}) do
    change()
    assert(not S.Resolve(99108, 'a'))
    assert(S.Resolve(179, 'a') and S.Resolve(99162, 'a'))
    record.v, record.g, record.d, record.c = voice, gender, duration, cues
end
for _, playerSex in ipairs({2, 3}) do
    sex = playerSex
    local resolved = S.Resolve(98430, 'a')
    assert(resolved and resolved.duration == quests[98430].d + 0.1)
    assert(resolved.path:find(playerSex == 3 and '_f.ogg' or '_m.ogg', 1, true))
end
sex = 2
assert(not S.Resolve(99080, 'c'), 'new releases cannot inherit JSON-only files absent from their live index')
quests[999999] = {d=30,v='human-male'}
assert(not S.Resolve(999999, 'a'), 'unknown quests wait for metadata migration')
quests[999999] = nil
for _, futureVersion in ipairs({'0.5.0', '1.0.0', ''}) do
    version = futureVersion
    WV:RefreshAudioSources()
    assert(S.Resolve(99162, 'a') and WV:GetSharedQuestVoice() == 'catquest')
end
version = nil
WV:RefreshAudioSources()
assert(S.Resolve(99162, 'a') and not S.Resolve(99080, 'c'))
version = '0.4.0'
WV:RefreshAudioSources()
-- Updated records play through the existing queue, and one missing OGG does
-- not poison another quest or the independently installed Classic library.
Q:Clear()
local first, second = S.Resolve(99162, 'a'), S.Resolve(99108, 'a')
local function context(id)
    return {questId=id,section='a',title='Updated library',speaker={npcID=id,name='NPC'}}
end
WowVoiceDB.autoPlay, WowVoiceDB.autoPlayAccept, WowVoiceDB.queueAutoPlay = true, true, true
Q:Offer(context(99162)); Q:Accept(99162)
Q:Offer(context(99108)); Q:Accept(99108)
assert(Q.current.context.questId == 99162 and Q:Count() == 2 and plays[#plays].file == first.path)
tick(now + first.duration + WowVoiceDB.tail + 0.01)
tick(Q.gap.deadline)
frames.WowVoiceQuestQueueDriver.scripts.OnUpdate()
assert(Q.current.context.questId == 99108 and plays[#plays].file == second.path)
Q:Clear()
soundOK = false
assert(not WV:ReplayQuest(99162) and not WV:HasQuestAudio(99162))
soundOK = true
assert(WV:HasQuestAudio(99108) and WV:HasQuestAudio(179))
version = snapshot; WV:RefreshAudioSources()
assert(S.Resolve(98430, 'a').duration == WowVoiceCatQuestAudio.entries['98430a'].audio.male.duration)
assert(S.Resolve(99080, 'c') and WowVoiceCatQuestAudio.sourceVersion == snapshot)
panel:Hide()
UnitSex, C_AddOns.GetAddOnMetadata = originalSex, metadata
print('PASS: updated CatQuest keeps compatible records, source choice, both sexes, Classic fallback and queue; changed/unknown records stay isolated without metadata migration')

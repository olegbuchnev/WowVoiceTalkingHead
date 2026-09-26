event('ADDON_LOADED')
local WV = WowVoice
assert(CatQuestVoicePack == nil, 'supplement must work without CatQuest loaded')
local plainID, genderID, turninID
for key, entry in pairs(WowVoiceForeverAudio) do
    local id, section = key:match('^(%d+)([ac])$')
    if section == 'a' then
        if entry.male then genderID = tonumber(id) else plainID = tonumber(id) end
    else turninID = tonumber(id) end
end
assert(plainID and genderID and turninID)
local prefix = 'Interface\\AddOns\\CatVoices\\'
local sex = 2
function UnitSex(unit) assert(unit == 'player'); return sex end

-- Real event playback and timer, with our own head/text and no CatQuest code.
questID = plainID
local entry = WowVoiceForeverAudio[plainID .. 'a']
event('QUEST_DETAIL')
local play = plays[#plays]
assert(play.file == prefix .. entry.file and play.channel == 'Master')
assert(frames.WowVoiceTalkingHead.Body.text == GetQuestText())
assert(cvars.Sound_EnableDialog == '0')
local count = #plays
event('QUEST_DETAIL'); assert(#plays == count, 'duplicate event restarted supplement')
tick(now + entry.duration - 0.1)
assert(stops[#stops] ~= play.handle, 'supplement ended early')
tick(now + 0.1 + WowVoiceDB.tail + 0.01)
assert(stops[#stops] == play.handle)
restored('1', '0.37')

-- The selected gender controls both the file and its actual duration.
entry = WowVoiceForeverAudio[genderID .. 'a']
for _, variant in ipairs({{2, entry.male}, {3, entry.female}}) do
    sex = variant[1]
    local file, duration = WV:SoundPath(genderID, 'a')
    assert(file == prefix .. variant[2].file and duration == variant[2].duration)
    assert(WV:HasQuestAudio(genderID) and WV:ReplayQuest(genderID))
    assert(plays[#plays].file == file)
    WV:Silence()
end
sex = 2

-- Missing progress/turn-in recordings stay silent instead of replaying detail.
questID = plainID
WV:Silence()
assert(WV:SoundPath(plainID, 'p') == nil)
count = #plays
event('QUEST_PROGRESS'); assert(#plays == count)
if not WowVoiceForeverAudio[plainID .. 'c'] then
    event('QUEST_COMPLETE'); assert(#plays == count)
end
questID = turninID
local file, duration = WV:SoundPath(turninID, 'c')
assert(file and duration)
event('QUEST_COMPLETE'); assert(plays[#plays].file == file)
WV:Silence()

-- Future Classic additions win even if an old supplemental index still overlaps.
local old = WowVoiceDur[plainID .. 'a']
WowVoiceDur[plainID .. 'a'] = 12.5
file, duration = WV:SoundPath(plainID, 'a')
assert(file == 'Interface\\AddOns\\WowVoiceSounds\\' .. plainID .. 'a.ogg' and duration == 12.5)
assert(WV:ReplayQuest(plainID) and plays[#plays].file == file)
WV:Silence()
WowVoiceDur[plainID .. 'a'] = old

-- Supplemental OGG paths are independent of legacy filename/activation settings.
WowVoiceDB.ext = 'mp3'
WV.license = {content_key = 'unused-for-supplement'}
assert(WV:SoundPath(plainID, 'a') == prefix .. WowVoiceForeverAudio[plainID .. 'a'].file)
WV.license = nil
WowVoiceDB.ext = 'ogg'

soundOK = false
assert(not WV:ReplayQuest(plainID))
restored('1', '0.37')
soundOK = true
WowVoiceDB.enabled = false
count = #plays
assert(not WV:ReplayQuest(plainID) and #plays == count)
WowVoiceDB.enabled = true
local supplemental = WowVoiceForeverAudio
WowVoiceForeverAudio = nil
assert(not WV:HasQuestAudio(plainID) and WV:HasQuestAudio(179))
WowVoiceForeverAudio = supplemental
local loaded = C_AddOns.IsAddOnLoaded
C_AddOns.IsAddOnLoaded = function(name) return name ~= 'CatVoices' end
messages = {}
event('PLAYER_LOGIN')
assert(has('CatVoices') and has('полностью перезапустите игру'))
assert(not has('github.com') and not has('CurseForge'), 'complete bundle must not send users to download another pack')
C_AddOns.IsAddOnLoaded = loaded
print('PASS: supplemental events, own portrait, timing, gender, missing sections, Classic priority and failure restoration')

-- A Forever quest accepted before installation has no captured giver. Recover
-- its verified starter by ID, even with an unrelated NPC currently targeted.
WV:Silence()
questCache()[97250] = nil
npcGUID = 'Creature-0-1-0-1-999-0000000099'
assert(WV:ReplayQuest(97250))
local head = frames.WowVoiceTalkingHead
assert(head.Name.text == 'Рубака Логмар' and head.Model.creatureID == 5911)
assert(not head.Icon.visible and not questCache()[97250])
assert(plays[#plays].file == WV:SoundPath(97250, 'a'))
WV:Silence()
local partial = {description='Saved quest text'}
questCache()[97250] = partial
local context = WV:GetReplaySpeaker(97250)
assert(context.speaker.npcID == 5911 and context.text == partial.description)
assert(questCache()[97250] == partial and not partial.npcID)
-- Captured identity and item/object starters retain priority over static data.
for _, record in ipairs({{npcID=999, displayID=4321}, {itemID=123}, {objectID=456}}) do
    questCache()[97250] = record
    assert(WV:GetReplaySpeaker(97250).speaker == record)
end
questCache()[97250] = nil
assert(not WV:GetReplaySpeaker(999999).speaker)
print('PASS: pre-update Forever quest recovers Logmar, preserves captured identity and leaves unknown quests neutral')

-- All bundled identities resolve by ID; confirmed multiple/non-NPC starters
-- suppress Classic guesses, while an absent supplemental entry keeps fallback.
local savedQuests = WowVoiceDB.questSpeakers
WowVoiceDB.questSpeakers = {}
local recovered, blocked = 0, 0
for id, starter in pairs(WowVoiceForeverSpeakers) do
    local speaker = WV:GetReplaySpeaker(id).speaker
    if starter then
        assert(speaker and speaker.npcID == starter.npcID and speaker.name == starter.name)
        recovered = recovered + 1
    else
        assert(not speaker)
        blocked = blocked + 1
    end
end
assert(recovered > 3000 and blocked > 0)
local starter = WowVoiceForeverSpeakers[179]
WowVoiceForeverSpeakers[179] = false
assert(not WV:GetReplaySpeaker(179).speaker)
questCache()[179] = {npcID=658, name='Captured giver', displayID=1234}
assert(WV:GetReplaySpeaker(179).speaker.displayID == 1234)
questCache()[179] = nil
WowVoiceForeverSpeakers[179] = nil
assert(WV:GetReplaySpeaker(179).speaker.npcID == 658)
WowVoiceForeverSpeakers[179] = starter
WowVoiceDB.questSpeakers = savedQuests
print('PASS: entire Forever starter index, explicit exclusions, captured priority and Classic fallback')

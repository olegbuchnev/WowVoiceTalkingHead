event('ADDON_LOADED')
local WV = WowVoice
TalkingHeadRuDB.questSpeakers = {[playerGUID] = {}}
local quests = TalkingHeadRuDB.questSpeakers[playerGUID]
for _, id in ipairs({98245, 98246}) do
    local context = WV:GetReplaySpeaker(id)
    assert(context.speaker.npcID == 270637 and context.speaker.displayID == 11740)
    assert(context.speaker.name == '[Howin Kindfeather]')
    assert(not quests[id], 'Imported NPC metadata must remain transient')
    assert(WV:ReplayQuest(id))
    local head = frames.TalkingHeadRu
    assert(head:IsShown() and head.Model.displayID == 11740 and not head.Icon.visible)
    assert(head.Name.text == 'Howin Kindfeather', 'Imported outer brackets must not appear in the heading')
    assert(WowVoiceCatQuestSpeakers.npcs[270637][4] == '[Howin Kindfeather]', 'Source metadata must stay intact')
    WV:Silence()
end
quests[98246] = {questId=98246, npcID=123, displayID=456, name='Captured'}
assert(WV:GetReplaySpeaker(98246).speaker == quests[98246], 'Live speaker must take priority')
quests[98246] = nil
local previous = WowVoiceForeverSpeakers[98246]
WowVoiceForeverSpeakers[98246] = false
assert(not WV:GetReplaySpeaker(98246).speaker, 'Confirmed non-NPC starter must block fallback')
WowVoiceForeverSpeakers[98246] = {npcID=123, name='Other giver'}
local speaker = WV:GetReplaySpeaker(98246).speaker
assert(speaker.npcID == 123 and speaker.displayID == nil, 'Different NPC must not inherit a CatQuest model')
WowVoiceForeverSpeakers[98246] = previous
print('PASS: CatQuest giver fallback, 98245/98246 portraits without CatQuest, captured and non-NPC priority')

event('ADDON_LOADED')
local WV = WowVoice
TalkingHeadRuDB.debug = true
TalkingHeadRuDB.autoPlayAccept = true
questID = 2842
local title, description = 'Главный инженер Скути', 'Описание из диалога Совика'
GetTitleText = function() return title end
GetQuestText = function() return description end

-- Lua mocks have no secret-value type. Reject every attempted conversion or
-- split of these sentinel strings, including eagerly evaluated debug output.
local secretGUID, secretName, secretDisplay = 'restricted-guid', 'restricted-name', 987654321
function issecretvalue(value)
    return value == secretGUID or value == secretName or value == secretDisplay
end
local originalSplit, originalToString = strsplit, tostring
strsplit = function(separator, value)
    assert(not issecretvalue(value), 'attempt to split a secret value')
    return originalSplit(separator, value)
end
tostring = function(value)
    assert(not issecretvalue(value), 'attempt to stringify a secret value')
    return originalToString(value)
end
local npc, questnpc = secretGUID, secretGUID
local name = secretName
UnitGUID = function(unit)
    if unit == 'player' then return playerGUID end
    if unit == 'npc' then return npc end
    if unit == 'questnpc' then return questnpc end
    if unit == 'target' then return secretGUID end
end
UnitName = function(unit)
    if unit == 'player' then return 'Player' end
    return name
end

event('QUEST_DETAIL')
local head = frames.TalkingHeadRu
assert(head.visible and head.Name.text == 'Совик' and head.Model.creatureID == 3413)
assert(plays[#plays].file == 'Interface\\AddOns\\WowVoiceSounds\\2842a.ogg')
portraitEvent('QUEST_ACCEPTED', 2842)
local captured = questCache()[2842]
assert(captured.description == description and captured.npcID == nil and captured.name == nil)
WV:Silence()
assert(WV:ReplayQuest(2842))
assert(head.Name.text == 'Совик' and head.Model.creatureID == 3413)
WV:Silence()
for _, section in ipairs({'p', 'c'}) do
    local speaker = WV:CaptureQuestSpeaker(2842, section, title, description).speaker
    assert(not speaker.npcID and not speaker.name, 'Never infer the receiver from the giver')
end
assert(not WV:CaptureQuestSpeaker(999999, 'a', title, description).speaker.npcID)
assert(WV:Resolve('Дворфские экипировщики', 'a', '') == 179,
    'Legacy title resolution must also tolerate restricted identities')

-- Skip a restricted npc token, but still use an accessible questnpc token.
questnpc = 'Creature-0-1-0-1-999-0000000001'
name = 'Accessible NPC'
local live = WV:CaptureQuestSpeaker(2842, 'a', title, description).speaker
assert(live.npcID == 999 and live.name == name and live.displayID == npcDisplay)
-- Names and model display IDs may be restricted independently of the GUID.
name, npcDisplay = secretName, secretDisplay
live = WV:CaptureQuestSpeaker(2842, 'a', title, description).speaker
assert(live.npcID == 999 and live.name == nil and live.displayID == nil)
portraitEvent('QUEST_ACCEPTED', 2842)
assert(questCache()[2842] == live)

questnpc = 'GameObject-0-1-0-1-123-0000000001'
local object = WV:CaptureQuestSpeaker(2842, 'a', title, description).speaker
assert(object.objectID == 123 and not object.npcID)

-- Existing clients without the secret API still capture ordinary identities.
issecretvalue = nil
strsplit, tostring = originalSplit, originalToString
npc, questnpc, name, npcDisplay = 'Creature-0-1-0-1-658-0000000001', nil, 'Стен Крепкорук', 1234
local ordinary = WV:CaptureQuestSpeaker(179, 'a', title, description).speaker
assert(ordinary.npcID == 658 and ordinary.name == name and ordinary.displayID == 1234)
print('PASS: restricted NPC identity never reaches parsing, logging or saves; playback, metadata fallback, accessible tokens and older clients work')

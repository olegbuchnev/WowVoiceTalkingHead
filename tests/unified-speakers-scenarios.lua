event('ADDON_LOADED')
local WV, database = WowVoice, TalkingHeadRuSpeakers
TalkingHeadRuDB.questSpeakers = {[playerGUID]={}}
local quests = TalkingHeadRuDB.questSpeakers[playerGUID]
local giver = database.givers[179].npcID
local model = database.npcs[giver].displayID
assert(model and WV:GetReplaySpeaker(179).speaker.displayID == model)
assert(WV:GetReplaySpeaker(179).title == C_QuestLog.GetTitleForQuestID(179), 'Game title wins over imported metadata')

-- Live identity survives and only the rendered appearance is enriched. No
-- static fields enter saved observations, so later game captures can correct it.
local captured = {npcID=giver,name='Observed NPC'}
quests[179] = captured
assert(WV:GetReplaySpeaker(179).speaker == captured)
assert(WV:ReplayQuest(179))
local head = frames.TalkingHeadRu
assert(head.Model.displayID == model and head.Name.text == 'Observed NPC')
assert(captured.displayID == nil)
assert(WV:GetQuestQueuePortraitDisplay(captured) == model)
WV:Silence()
captured.displayID = 876543
WV:ReplayQuest(179)
assert(head.Model.displayID == 876543 and WV:GetQuestQueuePortraitDisplay(captured) == 876543)
WV:Silence()

-- Never borrow this quest's giver model for a different observed NPC.
captured.npcID, captured.displayID = 3413, nil
WV:ReplayQuest(179)
assert(head.Model.displayID == database.npcs[3413].displayID)
WV:Silence()
for _,record in ipairs({{itemID=123,icon=456},{objectID=123}}) do
    quests[179] = record
    assert(WV:GetReplaySpeaker(179).speaker == record)
    assert(not WV:GetQuestQueuePortraitDisplay(record))
end

-- Models observed on this character outrank defaults; conflicting variants
-- force loading by creature ID instead of choosing either captured appearance.
quests[179] = {npcID=giver}
quests[900001] = {npcID=giver,displayID=7777}
assert(WV:GetQuestQueuePortraitDisplay(quests[179]) == 7777)
quests[900002] = {npcID=giver,displayID=8888}
assert(not WV:GetQuestQueuePortraitDisplay(quests[179]))
quests[900001], quests[900002], quests[179] = nil,nil,nil

-- A late real model updates the same record and replaces the provisional model.
npcGUID, npcName = 'Creature-0-1-0-1-'..giver..'-0000000001', 'Live giver'
modelLoadsImmediately = false
local context = WV:CaptureQuestSpeaker(179,'a','Quest','Text')
portraitEvent('QUEST_ACCEPTED',179)
assert(quests[179] == context.speaker and not context.speaker.displayID)
WV:ReplayQuest(179)
frames.WowVoicePortraitProbe:CompleteLoad(765432)
assert(context.speaker.displayID == 765432 and head.Model.displayID == 765432)
WV:Silence()
modelLoadsImmediately = true

-- Missing live units use the correct role, and no finisher means no guess.
local guid = UnitGUID
UnitGUID = function(unit) if unit=='player' then return playerGUID end end
local completion = WV:CaptureQuestSpeaker(2842,'c','Quest','Completion')
assert(completion.speaker.npcID == database.finishers[2842].npcID)
assert(completion.speaker.npcID ~= database.givers[2842].npcID)
local finisher = database.finishers[2842]
database.finishers[2842] = nil
assert(not WV:CaptureQuestSpeaker(2842,'c','Quest','Completion').speaker.npcID)
database.finishers[2842] = finisher
UnitGUID = guid
print('PASS: unified live/default models, exact IDs, item/object exclusions, conflicting appearances, late captures, queue portraits and separate finishers')

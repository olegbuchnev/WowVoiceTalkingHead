event('ADDON_LOADED')
local WV = WowVoice
WowVoiceDB.autoPlayAccept = true
questID = 2842
local title, description = 'Главный инженер Скути', 'Описание из диалога Совика'
GetTitleText = function() return title end
GetQuestText = function() return description end

-- Gossip opens QUEST_DETAIL without a live npc token. The selected target is
-- unrelated and must not be used as evidence of who gives this quest.
local originalGUID = UnitGUID
UnitGUID = function(unit)
    if unit=='npc' or unit=='questnpc' then return nil end
    return originalGUID(unit)
end
npcGUID, npcName, npcDisplay = 'Creature-0-1-0-1-999-0000000001', 'Unrelated target', 7777
assert(WowVoiceForeverSpeakers[2842].npcID==3413)
event('QUEST_DETAIL')
local head = frames.WowVoiceTalkingHead
assert(head.visible and head.Name.text=='Совик' and head.Model.creatureID==3413)
assert(not head.Icon.visible and head.Title.text==title)
assert(plays[#plays].file=='Interface\\AddOns\\WowVoiceSounds\\2842a.ogg')
assert(not questCache()[2842], 'Viewing a quest must not persist an inferred giver')
portraitEvent('QUEST_ACCEPTED',2842)
local captured = questCache()[2842]
assert(captured.description==description and captured.npcID==nil)
WV:Silence()
assert(WV:ReplayQuest(2842))
assert(head.Name.text=='Совик' and head.Model.creatureID==3413)
assert(questCache()[2842]==captured and captured.npcID==nil)
WV:Silence()

-- Already accepted without QUEST_DETAIL: replay still restores the giver.
questCache()[2842] = nil
portraitEvent('QUEST_ACCEPTED',2842)
assert(WV:ReplayQuest(2842))
assert(head.Name.text=='Совик' and head.Model.creatureID==3413)
WV:Silence()

-- Only descriptions may infer the giver. Never use Sovik as the receiver.
for _, section in ipairs({'p','c'}) do
    local context = WV:CaptureQuestSpeaker(2842,section,title,description)
    assert(not context.speaker.npcID and not context.speaker.name)
end

-- Explicit exclusions, missing metadata and item/object starters stay neutral
-- or preserve their real identity even if the Classic metadata names an NPC.
local metadata = WowVoiceForeverSpeakers[2842]
WowVoiceForeverSpeakers[2842] = false
assert(not WV:CaptureQuestSpeaker(2842,'a',title,description).speaker.npcID)
WowVoiceForeverSpeakers[2842] = metadata
assert(not WV:CaptureQuestSpeaker(999999,'a',title,description).speaker.npcID)
C_Container = {
    GetContainerNumSlots=function() return 1 end,
    GetContainerItemQuestInfo=function() return {questID=2842} end,
    GetContainerItemInfo=function() return {itemID=123,iconFileID=456,itemName='Quest item'} end,
}
local item = WV:CaptureQuestSpeaker(2842,'a',title,description).speaker
assert(item.itemID==123 and not item.npcID and item.name=='Quest item')
assert(not questCache()[2842], 'Viewing an item quest must not persist it before acceptance')
C_Container = nil
UnitGUID = originalGUID
npcGUID = 'GameObject-0-1-0-1-123-0000000001'
local object = WV:CaptureQuestSpeaker(2842,'a',title,description).speaker
assert(object.objectID==123 and not object.npcID)

-- Real NPC captures still win over inferred metadata, including late models.
npcGUID = 'Creature-0-1-0-1-999-0000000001'
modelLoadsImmediately = false
local live = WV:CaptureQuestSpeaker(2842,'a',title,description).speaker
assert(live.npcID==999 and live.name==npcName)
portraitEvent('QUEST_ACCEPTED',2842)
frames.WowVoicePortraitProbe:CompleteLoad(8888)
assert(questCache()[2842]==live and live.displayID==8888)
print('PASS: gossip quest 2842 first briefing and replay recover Sovik; inferred identity stays transient; receiver, item, object and live captures preserved')

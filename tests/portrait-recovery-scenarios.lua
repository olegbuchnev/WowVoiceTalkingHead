event('ADDON_LOADED')
event('PLAYER_LOGIN')
local WV = WowVoice
TalkingHeadRuDB.questSpeakers = {}
local originalIndex = WowVoiceIndex
local function replay(id)
    WV:Silence()
    assert(WV:ReplayQuest(id))
    return frames.TalkingHeadRu
end

-- Real metadata resolves by quest ID even when the journal title differs.
local h = replay(179)
assert(h.Name.text == 'Стен Крепкорук' and h.Model.creatureID == 658)
assert(not h.Icon.visible and not questCache()[179])
replay(861)
assert(h.Name.text == 'Скорн Белое Облако' and h.Model.creatureID == 3052)
assert(not questCache()[861])
-- This wanted poster has a receiver but no NPC giver.
replay(176)
assert(h.Icon.visible and h.Model.alpha == 0 and h.Name.text == 'Описание задания')
local noIndex = WV:GetReplaySpeaker(999999)
assert(not noIndex.speaker)
print('PASS: old quests recover exact indexed givers, duplicate titles stay distinct, receiver is never substituted')

-- Partial old records retain their text and are not overwritten by inference.
local partial = {questId=179, title='Saved title', description='Saved description'}
questCache()[179] = partial
local context = WV:GetReplaySpeaker(179)
assert(context.speaker.npcID == 658 and context.title == partial.title and context.text == partial.description)
assert(questCache()[179] == partial and not partial.npcID)
questCache()[900001] = {npcID=658, displayID=7777}
replay(179)
assert(h.Model.displayID == 7777)
questCache()[900002] = {npcID=658, displayID=8888}
replay(179)
assert(h.Model.creatureID == 658 and h.Model.displayID == 10658)
local player = playerGUID
playerGUID = 'Player-1-RECOVERY'
replay(179)
assert(h.Model.displayID == 10658 and not questCache()[179])
playerGUID = player
questCache()[900001], questCache()[900002] = nil, nil

local saved = {npcID=999, displayID=4321, name='Captured Forever NPC'}
questCache()[179] = saved
replay(179)
assert(h.Model.displayID == 4321 and h.Name.text == saved.name)
assert(WV:GetReplaySpeaker(179).speaker == saved)
questCache()[179] = {objectID=12345}
replay(179)
assert(h.Icon.visible and h.Model.alpha == 0)
-- New game-object captures keep their type, even against conflicting metadata.
npcGUID = 'GameObject-0-1-0-1-12345-0000000099'
questID = 179
event('QUEST_DETAIL'); portraitEvent('QUEST_ACCEPTED',179)
assert(questCache()[179].objectID == 12345)
replay(179)
assert(h.Icon.visible and h.Model.alpha == 0)
questCache()[179] = nil
print('PASS: captured identity wins, partial records retain text, known appearances are unambiguous and character-local')

-- Missing/replaced metadata and ambiguous giver IDs cannot produce a wrong NPC.
WowVoiceIndex = nil
replay(179)
assert(h.Icon.visible)
WowVoiceIndex = {One={{q=179,i=658,n='First'}}, Two={{q=179,i=999,n='Second'}}}
replay(179)
assert(h.Icon.visible)
WowVoiceIndex = {One={{q=179,i=658,n='First'},{q=179,i=658,n='First'}}}
replay(179)
assert(h.Model.creatureID == 658 and not h.Icon.visible)
WowVoiceIndex = originalIndex

-- Model failure must not interrupt playback; asynchronous success reveals it.
local creature = h.Model.SetCreature
local display = h.Model.SetDisplayInfo
h.Model.SetCreature = function() error('Model unavailable') end
replay(179)
assert(h.Icon.visible and h.Model.alpha == 0 and h.visible)
h.Model.SetCreature = function() return false end
replay(179)
assert(h.Icon.visible and h.Model.alpha == 0)
h.Model.SetCreature = function(self,id) self.creatureID=id end
replay(179)
assert(h.Icon.visible and h.Model.alpha == 0)
h.Model:CompleteLoad(3333)
assert(not h.Icon.visible and h.Model.alpha == 1)
h.Model.SetCreature = creature
questCache()[179] = {npcID=658,displayID=7777}
h.Model.SetDisplayInfo = function() error('Display unavailable') end
replay(179)
assert(h.Model.creatureID == 658 and not h.Icon.visible)
h.Model.SetDisplayInfo = display
questCache()[179] = nil
WV:Silence(); restored('1','0.37')
print('PASS: absent/conflicting index, model errors and missing/delayed models preserve audio and fallback')

-- Recover an item only from an exact bag quest match, ahead of inferred NPCs.
local scans = 0
C_Container = {
    GetContainerNumSlots = function() scans=scans+1; return 2 end,
    GetContainerItemQuestInfo = function(bag,slot)
        return {questID=slot==1 and 999999 or 179}
    end,
    GetContainerItemInfo = function(bag,slot)
        assert(slot==2)
        return {itemID=10621,itemName='Recovered item',iconFileID=134939}
    end,
}
replay(179)
assert(h.Icon.visible and h.Icon.texture == 134939 and h.Name.text == 'Recovered item')
assert(questCache()[179].itemID == 10621 and not questCache()[179].npcID)
local before = scans
C_Container.GetContainerNumSlots = function() error('Known item must not rescan bags') end
replay(179)
assert(h.Icon.texture == 134939 and scans == before)
C_Container = nil
WV:Silence(); restored('1','0.37')
print('PASS: exact item recovery overrides inferred giver, persists after item disappears, playback restores Dialog')

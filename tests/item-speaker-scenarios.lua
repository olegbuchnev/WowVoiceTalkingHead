event('ADDON_LOADED')
WowVoiceDB.autoPlayAccept = true
event('PLAYER_LOGIN')
local WV = WowVoice
npcGUID = nil
NUM_BAG_SLOTS = 4
local scans = 0
local available = true
C_Container = {
    GetContainerNumSlots = function(bag) scans = scans + 1; return available and 2 or 0 end,
    GetContainerItemQuestInfo = function(bag, slot)
        if bag == 0 then return {isQuestItem=true,questID=99999} end
        if bag == 4 and slot == 2 then return {isQuestItem=true,questID=179} end
        return {isQuestItem=true}
    end,
    GetContainerItemInfo = function(bag, slot)
        assert(bag==4 and slot==2, 'must select exact quest ID, not just a quest item')
        return {itemID=10621,itemName='Свиток с рунами',iconFileID=134939}
    end,
}
command('debug on')
questID=179; event('QUEST_DETAIL')
local h=frames.WowVoiceTalkingHead
assert(h.Name.text=='Свиток с рунами' and h.Icon.texture==134939)
assert(h.Icon.visible and h.IconBorder.visible and h.Model.alpha==0)
assert(has('item=10621') and scans==5)
portraitEvent('QUEST_ACCEPTED',179)
local record=questCache()[179]
assert(record.itemID==10621 and record.icon==134939 and record.description==GetQuestText())
assert(not record.npcID and not record.displayID)
WV:Silence(); restored('1','0.37')
available=false
local before=scans
assert(WV:ReplayQuest(179))
assert(scans==before and h.Name.text==record.name and h.Icon.texture==134939)
-- An old asynchronous model notification must not cover the item icon.
h.Model:CompleteLoad(4321)
assert(h.Icon.visible and h.IconBorder.visible and h.Model.alpha==0)
WV:Silence(); restored('1','0.37')
print('PASS: exact bag quest match, item metadata saved, replay after item disappears, stale model ignored, Dialog restored')

-- Receiver remains an NPC and does not overwrite the cached starter.
npcGUID='Creature-0-1-0-1-999-0000000099'; npcName='Получатель'; npcDisplay=4321
event('QUEST_COMPLETE')
assert(h.Name.text==npcName and h.Model.displayID==4321)
assert(not h.Icon.visible and not h.IconBorder.visible and questCache()[179]==record)
portraitEvent('QUEST_TURNED_IN',179)
assert(not questCache()[179] and h.visible)
WV:Silence(); restored('1','0.37')
print('PASS: receiver NPC model, item cache removed on turn-in without stopping audio')

npcGUID=nil
-- Missing API and missing bag mapping use a neutral document for a quest
-- without an indexed NPC giver (176 is a wanted poster).
C_Container=nil
questID=176; event('QUEST_DETAIL'); portraitEvent('QUEST_ACCEPTED',176)
assert(h.Name.text=='Описание задания' and h.Icon.texture=='Interface\\Icons\\INV_Misc_Note_01')
assert(h.Icon.visible and not questCache()[176].itemID)
WV:Silence()
C_Container={GetContainerNumSlots=function() return 1 end,
    GetContainerItemQuestInfo=function() return {isQuestItem=true,questID=99999} end,
    GetContainerItemInfo=function() error('unrelated quest item must not be used') end}
event('QUEST_DETAIL')
assert(h.Name.text=='Описание задания' and h.Icon.texture=='Interface\\Icons\\INV_Misc_Note_01')
WV:Silence()
print('PASS: absent API and unrelated quest items use neutral fallback')

-- Save even while voice is disabled; optional metadata may be missing.
C_Container.GetContainerItemQuestInfo=function() return {questID=179} end
C_Container.GetContainerItemInfo=function() return {itemID=10621} end
command('off'); questID=179; event('QUEST_DETAIL'); portraitEvent('QUEST_ACCEPTED',179)
assert(questCache()[179].itemID==10621 and not h.visible)
command('on'); WV:ReplayQuest(179)
assert(h.Name.text=='Описание задания' and h.Icon.visible)
WV:Silence(); portraitEvent('QUEST_REMOVED',179)
assert(not questCache()[179] and questCache()[176])
command('debug off'); messages={}
event('QUEST_DETAIL'); portraitEvent('QUEST_ACCEPTED',179); WV:Silence()
assert(#messages==0)
print('PASS: capture while disabled, missing metadata, abandon isolation, quiet normal mode')-- Leave a complete item record for addon recreation below.
questCache()[179].name='Свиток с рунами'
questCache()[179].icon=134939

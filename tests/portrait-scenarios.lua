event('ADDON_LOADED')
WowVoiceDB.autoPlayAccept = true
event('PLAYER_LOGIN')
command('debug on')
local WV=WowVoice

-- Viewing is transient; accept commits the exact appearance for this character.
event('QUEST_DETAIL')
local head = frames.WowVoiceTalkingHead
assert(head.visible and head.Model.displayID==1234 and head.Model.animation==60)
assert(head.Name.text==npcName and head.Title.text==GetTitleText())
assert(not WowVoiceDB.questSpeakers or not questCache() or not questCache()[179])
portraitEvent('QUEST_ACCEPTED',179)
assert(questCache()[179].displayID==1234 and questCache()[179].npcID==658)
local first=questCache()[179]
WV:Silence()
assert(not head.visible)
restored('1','0.37')

-- Replay gets its identity from the character cache, never from the target.
npcGUID='Creature-0-1-0-1-999-0000000099'; npcName='Другой NPC'; npcDisplay=4321
GetQuestID=function() error('Journal replay must not read NPC quest ID') end
assert(WV:ReplayQuest(179))
assert(head.Model.displayID==1234 and head.Name.text==first.name)
assert(head.Close.scripts.OnClick)
head.Close.scripts.OnClick()
assert(not head.visible)
restored('1','0.37')
GetQuestID=function() return questID end

-- Receiver is the current NPC, never replaces the saved giver.
event('QUEST_COMPLETE')
assert(head.Model.displayID==4321 and questCache()[179]==first)
local stopsBefore=#stops
portraitEvent('QUEST_TURNED_IN',179)
portraitEvent('QUEST_REMOVED',179)
assert(not questCache()[179] and head.visible and #stops==stopsBefore)
tick(now+WowVoiceDur['179c']+WowVoiceDB.tail+0.01)
assert(head.visible and head.Model.animation==0)
now=now+1
head.scripts.OnUpdate()
assert(not head.visible)
restored('1','0.37')
print('PASS: live model, accept persistence, journal giver, different receiver, turn-in preserves audio until timer')

-- Shared NPC: independent quest records, abandon only removes that quest.
questID=179; event('QUEST_DETAIL'); portraitEvent('QUEST_ACCEPTED',179)
questID=861; event('QUEST_DETAIL'); portraitEvent('QUEST_ACCEPTED',861)
assert(questCache()[179]~=questCache()[861])
local saved861=questCache()[861]
portraitEvent('QUEST_REMOVED',179)
assert(not questCache()[179] and questCache()[861]==saved861)
WV:Silence()
playerGUID='Player-1-OTHER'
WV:ReplayQuest(861)
assert(head.Name.text=='Скорн Белое Облако' and head.Model.creatureID==3052)
assert(head.Model.displayID~=saved861.displayID and not questCache()[861])
playerGUID='Player-1-ABC'
WV:ReplayQuest(861)
assert(head.Name.text==saved861.name and head.Model.displayID==saved861.displayID)
print('PASS: per-quest/per-character isolation, abandoning one quest preserves another quest from same NPC')

-- Model loads after acceptance, mutating the saved record, without resurrecting removed quests.
modelLoadsImmediately=false
WV:Silence(); questID=179; event('QUEST_DETAIL'); portraitEvent('QUEST_ACCEPTED',179)
assert(questCache()[179].displayID==nil)
local probe=frames.WowVoicePortraitProbe
probe:CompleteLoad(7777)
assert(questCache()[179].displayID==7777 and head.Model.displayID==7777)
WV:Silence(); event('QUEST_DETAIL'); portraitEvent('QUEST_ACCEPTED',179)
portraitEvent('QUEST_REMOVED',179)
probe:CompleteLoad(8888)
assert(questCache()[179]==nil and head.visible and head.Model.displayID==8888)
WV:Silence()
-- Changing NPC before completion: old request must not persist into the next quest.
questID=179; event('QUEST_DETAIL'); portraitEvent('QUEST_ACCEPTED',179)
questID=861; npcDisplay=5678; event('QUEST_DETAIL'); portraitEvent('QUEST_ACCEPTED',861)
probe:CompleteLoad(5678)
assert(questCache()[179].displayID==nil and questCache()[861].displayID==5678)
print('PASS: asynchronous capture after accept, late load after removal, replacement of an unfinished capture')

-- No NPC: item/shared quest must not steal target's appearance.
WV:Silence(); questID=179
local oldGUID=UnitGUID
UnitGUID=function(unit) if unit=='npc' or unit=='questnpc' then return nil end return oldGUID(unit) end
event('QUEST_DETAIL'); portraitEvent('QUEST_ACCEPTED',179)
assert(questCache()[179].npcID==nil and not head.Icon.visible and head.Model.creatureID==658)
assert(head.Name.text=='Стен Крепкорук', 'Missing live NPC uses indexed giver, never the unrelated target')
UnitGUID=oldGUID
-- No audio: capture still works, but panel stays hidden on playback failure.
WV:Silence(); modelLoadsImmediately=true; soundOK=false; questID=97250
event('QUEST_DETAIL'); portraitEvent('QUEST_ACCEPTED',97250)
assert(questCache()[97250].displayID==npcDisplay and not head.visible)
restored('1','0.37')
soundOK=true
-- Disabled voice still captures NPC for subsequent replay.
command('off'); questID=179; event('QUEST_DETAIL'); portraitEvent('QUEST_ACCEPTED',179)
assert(questCache()[179].displayID==npcDisplay and not head.visible)
command('on')
print('PASS: item/shared quest avoids unrelated target, capture without audio or while voice is disabled')

-- The head stays visible during playback; real playback cannot be dragged.
WV:ReplayQuest(179)
local soundCount=#plays
now=now+2
assert(head.visible and #plays==soundCount)
head.scripts.OnUpdate()
assert(head.Progress.value>0)
local anchor=frames.WowVoiceTalkingHeadAnchor
local beforeDrag=WowVoiceDB.headPosition
head.scripts.OnDragStart(head)
assert(not anchor.moving)
head.scripts.OnDragStop(head)
assert(WowVoiceDB.headPosition==beforeDrag)
command('head reset'); assert(WowVoiceDB.headPosition==nil and anchor.points[1][1]=='BOTTOM')
command('diag'); assert(has('Portrait:'))
WV:Silence(); restored('1','0.37')
command('debug off'); messages={}
event('QUEST_DETAIL'); portraitEvent('QUEST_ACCEPTED',179); WV:Silence()
assert(#messages==0,'normal mode must be quiet')
-- Preserve cache for the separate simulated reload phase.
savedBeforeReload=questCache()[179].displayID
print('PASS: head visibility/reset, drag persistence, no sound restarts, diagnostics, quiet mode')

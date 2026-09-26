event('ADDON_LOADED')
local journal
for _,f in ipairs(allFrames) do
    if f~=frames.WowVoiceFrame and f.events.ADDON_LOADED and f.events.PLAYER_LOGIN then journal=f; break end
end
assert(journal,'journal watcher missing')
assert(#plays==0,'UI initialization played audio')

-- Simulate Blizzard UI loading after WowVoice, with the modern nested details panel.
QuestMapFrame=CreateFrame('Frame','QuestMapFrame')
local details=CreateFrame('Frame',nil,QuestMapFrame)
details.questID=861
details.BackFrame=CreateFrame('Frame',nil,details)
details.BackFrame.BackButton=CreateFrame('Button',nil,details.BackFrame)
QuestMapFrame.QuestsFrame={DetailsFrame=details}
QuestScrollFrame=CreateFrame('Frame','QuestScrollFrame')
local first=CreateFrame('Button',nil,QuestScrollFrame)
first.questID=179
first.Checkbox=CreateFrame('Frame',nil,first)
local missing=CreateFrame('Button',nil,QuestScrollFrame)
missing.questID=97250
missing.Checkbox=CreateFrame('Frame',nil,missing)
local active={first,missing}
QuestScrollFrame.titleFramePool={EnumerateActive=function()
    local i=0
    return function() i=i+1; return active[i] end
end}
function QuestLogQuests_Update() end
function QuestMapFrame_ShowQuestDetails(id) details.questID=id end
journal.scripts.OnEvent(journal,'ADDON_LOADED','Blizzard_WorldMap')
local function playFor(owner)
    for _,f in ipairs(allFrames) do if f.questOwner==owner then return f end end
end
local play=assert(playFor(first))
local noAudio=assert(playFor(missing))
local detailPlay=assert(playFor(details))
assert(play.alpha==1 and noAudio.alpha==0.4)
assert(first.Checkbox.points[1][4]==-26)
assert(play.points[1][2]==first.Checkbox)
assert(detailPlay.points[1][2]==details.BackFrame.BackButton)
assert(#plays==0,'opening journal automatically played audio')

-- NPC API must never determine a journal replay; it may be stale or inaccessible.
GetQuestID=function() error('Journal must not call NPC GetQuestID') end
play.scripts.OnClick(play)
assert(plays[#plays].file:find('179a.ogg',1,true) and plays[#plays].channel=='Master')
assert(cvars.Sound_EnableDialog=='0' and cvars.Sound_DialogVolume=='0')
local old=plays[#plays].handle
play.scripts.OnClick(play)
assert(#plays==2 and stops[#stops]==old,'manual replay incorrectly suppressed')

-- Reused row and newly selected details must use the current ID, not cached closure data.
first.questID=192
QuestLogQuests_Update()
play.scripts.OnClick(play)
assert(plays[#plays].file:find('192a.ogg',1,true))
QuestMapFrame_ShowQuestDetails(861)
detailPlay.scripts.OnClick(detailPlay)
assert(plays[#plays].file:find('861a.ogg',1,true))
QuestMapFrame_ShowQuestDetails(179)
detailPlay.scripts.OnClick(detailPlay)
assert(plays[#plays].file:find('179a.ogg',1,true))

-- Missing audio and disabled addon must leave an ongoing recording untouched.
local count,stopCount=#plays,#stops
noAudio.scripts.OnClick(noAudio)
assert(#plays==count and #stops==stopCount)
noAudio.scripts.OnEnter(noAudio)
assert(GameTooltip.lines[2]:find('нет записи',1,true))
WowVoiceDB.enabled=false
play.scripts.OnClick(play)
assert(#plays==count and #stops==stopCount)
WowVoiceDB.enabled=true
tick(now+40)
restored('1','0.37')

-- Reloading unrelated addons and refreshing the pooled list must not duplicate buttons/hooks.
local created=#allFrames
for i=1,5 do
    journal.scripts.OnEvent(journal,'ADDON_LOADED','OtherAddon')
    QuestLogQuests_Update()
end
assert(#allFrames==created)
assert(hookCounts.QuestLogQuests_Update==1 and hookCounts.QuestMapFrame_ShowQuestDetails==1)
-- Older direct details alias is also accepted without another button.
QuestMapFrame.DetailsFrame=details
QuestMapFrame.scripts.OnShow(QuestMapFrame)
assert(#allFrames==created)
print('PASS: lazy journal UI, list and details controls, current IDs on recycled rows, repeated manual playback')
print('PASS: no NPC quest API calls, no autoplay, missing audio and disabled addon preserve current playback')
print('PASS: Master/Dialog restoration, Classic duration, single hooks/buttons, both details layouts')

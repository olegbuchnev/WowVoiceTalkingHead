event('ADDON_LOADED')
local WV=WowVoice
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
first.Checkbox:SetPoint('TOPRIGHT',first,'TOPRIGHT',-4,-8)
local missing=CreateFrame('Button',nil,QuestScrollFrame)
missing.questID=999999
missing.Checkbox=CreateFrame('Frame',nil,missing)
missing.Checkbox:SetPoint('TOPRIGHT',missing,'TOPRIGHT',-4,-8)
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
assert(play.visible and play.alpha==0.7 and not noAudio.visible)
assert(missing.Checkbox.points[1][4]==-4,'missing audio must not reserve button space')
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
assert(not noAudio.visible)
-- Both reused list rows and the details button disappear and return as IDs change.
first.questID=999999
QuestLogQuests_Update()
assert(not play.visible and first.Checkbox.points[1][4]==-4)
QuestMapFrame_ShowQuestDetails(999999)
assert(not detailPlay.visible)
first.questID=179
QuestLogQuests_Update()
QuestMapFrame_ShowQuestDetails(179)
assert(play.visible and detailPlay.visible and first.Checkbox.points[1][4]==-26)
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

-- No tooltip setting or tooltip interactions remain; hover feedback still works.
command('options')
local panel=frames.WowVoiceOptionsPanel
assert(panel.PlayTooltips==nil)
play.scripts.OnEnter(play)
assert(not GameTooltip.visible and play.alpha==1)
count,stopCount=#plays,#stops
for _, control in ipairs({play,detailPlay,noAudio}) do
    control.scripts.OnEnter(control)
    assert(not GameTooltip.visible,'journal controls must not show tooltips')
    control.scripts.OnLeave(control)
end
assert(play.alpha==0.7,'hover feedback must reset')
assert(#plays==count and #stops==stopCount)
WowVoiceDB.playTooltips=true
event('ADDON_LOADED')
assert(WowVoiceDB.playTooltips==nil,'obsolete preference must be removed')
-- Hovering our controls must not touch another addon's tooltip.
GameTooltip:SetOwner(QuestMapFrame); GameTooltip:Show()
detailPlay.scripts.OnEnter(detailPlay)
detailPlay.scripts.OnLeave(detailPlay)
assert(GameTooltip.visible and GameTooltip:IsOwned(QuestMapFrame))
GameTooltip:Hide()
assert(frames.WowVoiceStopButton==nil)
print('PASS: no tooltip option or tooltips, preserved hover, obsolete setting cleanup, unrelated tooltips untouched')

first.questID = 90902
QuestLogQuests_Update()
assert(play.alpha == 0.7)
play.scripts.OnClick(play)
assert(plays[#plays].file:find('Interface\\AddOns\\CatQuest_Voices\\Sounds\\q\\', 1, true) == 1)
QuestMapFrame_ShowQuestDetails(90902)
detailPlay.scripts.OnClick(detailPlay)
assert(plays[#plays].file:find('Interface\\AddOns\\CatQuest_Voices\\Sounds\\q\\', 1, true) == 1)
WV:Silence()
print('PASS: supplemental journal list/details replay uses our existing controls')

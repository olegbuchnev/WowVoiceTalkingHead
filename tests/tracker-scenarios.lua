event('ADDON_LOADED')
local WV=WowVoice
assert(WowVoiceDB.trackerButtons==nil,'obsolete tracker preference is removed')
assert(#plays==0)

-- The tracker may load later than WowVoice. Use the same nested active-block
-- structure as Blizzard and EllesmereUI, without relying on NPC quest APIs.
QuestObjectiveTracker=CreateFrame('Frame',nil,UIParent)
local tracker=QuestObjectiveTracker
tracker.usedBlocks={QuestTemplate={}}
function tracker:Update() end
function tracker:FreeBlock(block)
    self.usedBlocks.QuestTemplate[block.id]=nil
    block:Hide()
end
local function block(id)
    local row=CreateFrame('Frame',nil,tracker)
    row.id=id
    row.HeaderText=row:CreateFontString(nil,'ARTWORK','QuestTitleFont')
    row.HeaderText:SetPoint('TOPLEFT',row,'TOPLEFT',0,0)
    tracker.usedBlocks.QuestTemplate[id]=row
    return row
end
local first,second,missing=block(179),block(192),block(999999)
second.poiButton=CreateFrame('Button',nil,second)
local function playFor(row)
    for _,f in ipairs(allFrames) do
        if f.parent==row and f.Icon and f.scripts.OnClick then return f end
    end
end
local events=frames.WowVoiceTrackerEvents
events.scripts.OnEvent(events,'ADDON_LOADED','Blizzard_ObjectiveTracker')
local play,other=assert(playFor(first)),assert(playFor(second))
assert(play.visible and other.visible and not playFor(missing))
assert(play.template==nil and play.width==18,'tracker controls must be compact and borderless')
assert(play.points[1][2]==first.HeaderText and play.points[1][4]<0)
assert(other.points[1][2]==second.poiButton,'leave room for Blizzard waypoint marker')
assert(first.HeaderText.point[4]==0,'tracker title must not move')
assert(first.scripts.OnClick==nil,'do not replace native header click scripts')
GetQuestID=function() error('tracker replay must use the block ID') end
play.scripts.OnClick(play)
assert(plays[#plays].file:find('179a.ogg',1,true))
assert(cvars.Sound_EnableDialog=='0')
local old=plays[#plays].handle
play.scripts.OnClick(play)
assert(#plays==2 and stops[#stops]==old,'repeated click restarts description')

-- Replay controls are always available, even with a stale saved opt-out.
command('options')
local panel=frames.WowVoiceOptionsPanel
assert(not panel.TrackerButtons and not panel.TrackerProgressPulse)
local count,stopCount=#plays,#stops
WowVoiceDB.trackerButtons=false
tracker:Update()
assert(play.visible and other.visible and #plays==count and #stops==stopCount)
event('ADDON_LOADED')
assert(WowVoiceDB.trackerButtons==nil)
tracker:Update()
assert(play.visible and other.visible)

-- A released block may be reused by another tracker. Keep its button hidden
-- until it belongs to the quest tracker again; never keep an old quest ID.
tracker:FreeBlock(first)
assert(not play.visible and not play.active)
first.id=861
first:Show()
assert(not play.visible)
tracker.usedBlocks.QuestTemplate[first.id]=first
tracker:Update()
assert(play.visible)
play.scripts.OnClick(play)
assert(plays[#plays].file:find('861a.ogg',1,true))
tracker:FreeBlock(first)
first.id=999998
tracker.usedBlocks.QuestTemplate[first.id]=first
tracker:Update()
assert(not play.visible,'recycling to a quest without audio must hide the button')

second.poiButton:Hide()
tracker:Update()
assert(other.points[1][2]==second.HeaderText,'Ellesmere can hide the stock marker')
WowVoiceDB.enabled=false
count,stopCount=#plays,#stops
other.scripts.OnClick(other)
assert(#plays==count and #stops==stopCount)
WowVoiceDB.enabled=true
local created=#allFrames
for i=1,5 do events.scripts.OnEvent(events,'ADDON_LOADED','OtherAddon'); tracker:Update() end
assert(#allFrames==created,'refreshes must reuse buttons')
assert(hookCounts[tostring(tracker)..'.Update']==1 and hookCounts[tostring(tracker)..'.FreeBlock']==1)
WV:Silence()
restored('1','0.37')
print('PASS: tracker replay, lazy loading, native layout, recycled blocks, missing audio, single hooks/buttons')
print('PASS: tracker controls always available, stale opt-out ignored and removed, audio/head settings preserved')

other.scripts.OnEnter(other)
assert(not GameTooltip.visible and panel.PlayTooltips==nil)
other.scripts.OnLeave(other)
other.scripts.OnEnter(other)
assert(not GameTooltip.visible and other.Icon.alpha==1,'tracker highlights without tooltips')
count=#plays
other.scripts.OnClick(other)
assert(#plays==count+1,'removing tooltips must not disable playback')
other.scripts.OnLeave(other)
assert(other.Icon.alpha==0.7)
GameTooltip:SetOwner(tracker); GameTooltip:Show()
other.scripts.OnEnter(other)
other:Hide()
assert(GameTooltip.visible and GameTooltip:IsOwned(tracker),'tracker controls must not touch unrelated tooltips')
GameTooltip:Hide()
WV:Silence()
print('PASS: tracker has no tooltips, retains highlight/playback and leaves unrelated tooltips alone')

local supplemental = block(90902)
tracker:Update()
local supplementalPlay = assert(playFor(supplemental))
assert(supplementalPlay.visible)
supplementalPlay.scripts.OnClick(supplementalPlay)
assert(plays[#plays].file:find('Interface\\AddOns\\CatQuest_Voices\\Sounds\\q\\', 1, true) == 1)
WV:Silence()
print('PASS: supplemental quests get tracker replay controls without CatQuest')

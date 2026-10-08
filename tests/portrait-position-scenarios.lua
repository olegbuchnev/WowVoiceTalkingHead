event('ADDON_LOADED')
local WV=WowVoice

-- A present but unpositioned Blizzard container must not strand the panel.
BottomManagedFrameContainer=CreateFrame('Frame',nil,UIParent)
BottomManagedFrameContainer:SetSize(573,1)
assert(BottomManagedFrameContainer:GetCenter()==nil)
command('options')
WV:GetHeadSettings()
local head,anchor=frames.TalkingHeadRu,frames.TalkingHeadRuAnchor
assert(anchor:GetCenter()~=nil and anchor:GetPoint()=='BOTTOM')
do
    local settings=WV:GetHeadSettings()
    assert(type(settings.x)=='number' and type(settings.y)=='number')
    assert(TalkingHeadRuDB.headPosition==nil)
end
assert(WV:ReplayQuest(179))
assert(head:IsVisible() and head.Model.portraitReady and anchor:GetCenter()~=nil)

-- A later valid layout is used on the next track. Losing it mid-track falls
-- back without restarting the recording or changing the automatic preference.
BottomManagedFrameContainer:SetPoint('BOTTOM',UIParent,'BOTTOM',0,180)
assert(WV:ReplayQuest(179))
assert(select(2,anchor:GetPoint())==BottomManagedFrameContainer)
local played,stopped=#plays,#stops
BottomManagedFrameContainer:ClearAllPoints()
assert(anchor:GetCenter()==nil)
head.scripts.OnUpdate()
assert(select(2,anchor:GetPoint())==UIParent and anchor:GetCenter()~=nil)
assert(#plays==played and #stops==stopped and TalkingHeadRuDB.headPosition==nil)

-- Simulate GetCenter remaining nil until the client's next layout pass.
local getCenter=anchor.GetCenter
anchor.GetCenter=function() return nil,nil end
TalkingHeadRuDB.headPosition={'CENTER','CENTER',123,-200}
local settings=WV:GetHeadSettings()
assert(settings.x==123 and settings.y==-200)
assert(TalkingHeadRuDB.headPosition[3]==123 and TalkingHeadRuDB.headPosition[4]==-200)
TalkingHeadRuDB.headPosition={'BOTTOMLEFT','BOTTOMLEFT',20,30}
settings=WV:GetHeadSettings()
assert(settings.x==20+head:GetWidth()/2-UIParent:GetWidth()/2)
assert(settings.y==30+head:GetHeight()/2-UIParent:GetHeight()/2)
WV:ResetHeadPosition()
assert(TalkingHeadRuDB.headPosition==nil)
settings=WV:GetHeadSettings()
assert(type(settings.x)=='number' and type(settings.y)=='number')
anchor.GetCenter=getCenter
assert(WV:ToggleHeadPreview())
assert(head:IsVisible() and anchor:GetCenter()~=nil)
WV:HideHeadPreview()
print('PASS: unpositioned managed container, visible playback, lost layout recovery, pending GetCenter, saved offsets and preview safety')

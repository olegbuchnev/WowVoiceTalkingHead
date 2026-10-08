event('ADDON_LOADED')
local WV=WowVoice
local function near(actual,expected)
    assert(math.abs(actual-expected)<0.00001,tostring(actual)..' ~= '..expected)
end

-- Any addon can hide the normal UI before the first track starts.
UIParent.scale=0.75
UIParent:SetAlpha(0)
UIParent:Hide()
SetUIVisibility(false)
assert(WV:ReplayQuest(179))
local head=frames.TalkingHeadRu
local anchor=frames.TalkingHeadRuAnchor
assert(anchor:GetParent()==nil)
local function visibleTogether()
    assert(head:IsVisible() and head.Background:IsVisible()
        and head.TextScroll:IsVisible() and head.Close:IsVisible())
    near(head:GetEffectiveAlpha(),1)
    near(head.Model.modelAlpha,1)
end
visibleTogether()
near(anchor:GetEffectiveScale(),0.75)
local point={anchor:GetPoint()}
local sounds,stopped=#plays,#stops
head.Model:CompleteLoad(10658)
visibleTogether()
now=now+2
head.scripts.OnUpdate()
assert(head.Progress.value>0 and #plays==sounds and #stops==stopped)

-- Independent visibility applies to both hidden and fading UI.
do
    for _,alpha in ipairs({0,0.4,1}) do
        UIParent:SetAlpha(alpha)
        head.scripts.OnUpdate()
        visibleTogether()
        head.Model:CompleteLoad(10658)
        visibleTogether()
    end
end
UIParent:Show()
SetUIVisibility(true)
visibleTogether()
assert(#plays==sounds and #stops==stopped,'UI changes must not restart audio')
local restoredPoint={anchor:GetPoint()}
for i=1,5 do assert(point[i]==restoredPoint[i], 'UI visibility changed panel position') end
UIParent.scale=0.9
local scaleEvents=frames.WowVoiceHeadScaleEvents
scaleEvents.scripts.OnEvent(scaleEvents,'UI_SCALE_CHANGED')
near(anchor:GetEffectiveScale(),0.9)
near(head:GetEffectiveScale(),0.9*head:GetScale())

-- Natural completion fades the entire independent panel while UIParent is hidden.
UIParent:Hide()
UIParent:SetAlpha(0)
SetUIVisibility(false)
local started=now
tick(started+WowVoiceDur['179a']+TalkingHeadRuDB.tail+0.01)
restored('1','0.37')
now=now+0.5
head.scripts.OnUpdate()
near(head.Background.alpha,0.5)
near(head.Model.modelAlpha,0.5)
now=now+1
head.scripts.OnUpdate()
assert(not head:IsShown())
head.Model:CompleteLoad(10658)
near(head.Model.modelAlpha,0,'late loads must not reveal a dismissed model')

-- Close and silent preview work while the rest of the UI stays hidden.
assert(WV:ReplayQuest(179))
visibleTogether()
stopped=#stops
head.Close.scripts.OnClick()
assert(not head:IsShown() and #stops==stopped+1)
WV:ToggleHeadPreview()
visibleTogether()
WV:HideHeadPreview()
head.Model:CompleteLoad(10658)
near(head.Model.modelAlpha,0)
assert(WV:ReplayQuest(179))
WV:Silence()
assert(not head:IsShown())
head.Model:CompleteLoad(10658)
near(head.Model.modelAlpha,0)
UIParent:Show(); UIParent:SetAlpha(1); SetUIVisibility(true)
assert(not head:IsShown())
print('PASS: independent whole-panel visibility, early/late models, scale/position, continuous audio, natural completion, close, preview')

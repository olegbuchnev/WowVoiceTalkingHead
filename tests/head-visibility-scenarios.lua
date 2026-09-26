event('ADDON_LOADED')
local WV=WowVoice
local function near(actual,expected)
    assert(math.abs(actual-expected)<0.00001,tostring(actual)..' ~= '..expected)
end

-- Dialogue UI can hide the game UI before the very first quest starts.
SetUIVisibility(false)
assert(WV:ReplayQuest(179))
local head=frames.WowVoiceTalkingHead
assert(head.Model.portraitReady and head.Model.modelAlpha==0)
local sounds,stopped=#plays,#stops
head.Model:CompleteLoad(10658)
assert(head.Model.modelAlpha==0,'late loads must not reveal hidden geometry')
now=now+2
head.scripts.OnUpdate()
assert(head.Progress.value>0 and #plays==sounds and #stops==stopped)
SetUIVisibility(true)
near(head.Model.modelAlpha,1)
assert(#plays==sounds and #stops==stopped,'showing UI must not restart audio')

-- Parent fades must affect the model exactly once, including the final fade.
for _,preset in ipairs({'retail','classic','ellesmere'}) do
    WV:SetHeadPreset(preset)
    UIParent:SetAlpha(0.4)
    head.scripts.OnUpdate()
    near(head.Model.modelAlpha,0.4)
    near(head.Background.alpha,1)
    UIParent:SetAlpha(0)
    head.Model:CompleteLoad(10658)
    near(head.Model.modelAlpha,0)
    UIParent:SetAlpha(1)
    head.scripts.OnUpdate()
    near(head.Model.modelAlpha,1)
end
UIParent:Hide()
near(head.Model.modelAlpha,0)
UIParent:Show()
near(head.Model.modelAlpha,1)

WV:FinishTalkingHead()
now=now+0.5
UIParent:SetAlpha(0.4)
head.scripts.OnUpdate()
near(head.Background.alpha,0.5)
near(head.Model.modelAlpha,0.2)
SetUIVisibility(false)
near(head.Model.modelAlpha,0)
now=now+1
SetUIVisibility(true)
near(head.Model.modelAlpha,0,'an expired fade must not flash on return')
head.scripts.OnUpdate()
assert(not head.visible)
UIParent:SetAlpha(1)

-- Playback can finish while UIParent is hidden and OnUpdate is suspended.
assert(WV:ReplayQuest(179))
local started=now
UIParent:Hide()
tick(started+WowVoiceDur['179a']+WowVoiceDB.tail+0.01)
restored('1','0.37')
now=now+2
UIParent:Show()
near(head.Model.modelAlpha,0)
head.scripts.OnUpdate()
assert(not head.visible)

SetUIVisibility(false)
WV:ToggleHeadPreview()
near(head.Model.modelAlpha,0)
SetUIVisibility(true)
near(head.Model.modelAlpha,1)
WV:HideHeadPreview()
head.Model:CompleteLoad(10658)
near(head.Model.modelAlpha,0)
print('PASS: external UI fades/hiding, early and late model loads, continuous audio, hidden completion and preview visibility')

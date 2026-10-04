event('ADDON_LOADED')
local WV=WowVoice
local function near(actual, expected)
    assert(math.abs(actual-expected)<0.00001, tostring(actual)..' ~= '..expected)
end
local function advance(t)
    tick(t)
    local h=frames.WowVoiceTalkingHead
    if h and h.visible then h.scripts.OnUpdate() end
end
local function start()
    assert(WV:ReplayQuest(179))
    return frames.WowVoiceTalkingHead,now
end

local function opacity(h, expected, modelReady)
    -- Frame opacity alone does not exercise the 3D model's opacity API.
    near(h.alpha,1)
    near(h.Portrait.alpha or 1,1)
    for _, part in ipairs({'Background','PortraitBackground','PortraitOverlay',
        'Icon','IconBorder','Name','TextScroll','Progress','Close'}) do
        near(h[part].alpha,expected)
    end
    near(h.Model.modelAlpha,modelReady==false and 0 or expected)
end

-- No entrance or mid-playback fades; only the final second fades all parts.
do
    local h,t=start()
    assert(h.visible and h.alpha==1 and h.Model.alpha==1)
    opacity(h,1)
    for _, elapsed in ipairs({0.375,0.625,0.875,1.15,1.5,WowVoiceDur['179a']/2}) do
        advance(t+elapsed); opacity(h,1)
    end

    -- Audio stops/restores Dialog first; the model idles while fading for 1s.
    local sound=plays[#plays].handle
    advance(t+WowVoiceDur['179a']+WowVoiceDB.tail+0.01)
    local ended=now
    assert(h.visible and h.Model.displayID>0 and h.Model.animation==0 and not h.Model.talkAnimation)
    assert(stops[#stops]==sound)
    restored('1','0.37')
    advance(ended+0.5); opacity(h,0.5)
    advance(ended+0.999); assert(h.visible); opacity(h,0.001)
    advance(ended+1); assert(not h.visible and h.Model.displayID==0)
    near(h.Model.modelAlpha,0)
end

-- Dismissal is immediate even after the audio has ended; it cancels the tail.
for _, closing in ipairs({false,true}) do
    for _, button in ipairs({'cross','right'}) do
        local h,t=start()
        advance(t+(closing and WowVoiceDur['179a']+WowVoiceDB.tail+0.01 or 0.3))
        local count=#stops
        if button=='cross' then h.Close.scripts.OnClick()
        else h.scripts.OnClick(h,'RightButton') end
        assert(not h.visible and h.Model.displayID==0)
        assert(#stops==count+(closing and 0 or 1))
        restored('1','0.37')
        advance(now+2); assert(not h.visible)
    end
end

-- New audio/preview during a fade appears immediately, with no stale close.
local h,t=start()
advance(t+WowVoiceDur['179a']+WowVoiceDB.tail+0.01)
advance(now+0.5)
local nextStart=now
assert(WV:ReplayQuest(861))
opacity(h,1)
advance(nextStart+0.8); assert(h.visible and h.Model.creatureID==3052)
advance(nextStart+1.6); near(h.Close.alpha,1)
WV:FinishTalkingHead()
WV:ToggleHeadPreview()
local previewTime=now
opacity(h,1)
advance(previewTime+2); assert(h.visible and h.Model.unit=='player'); opacity(h,1)
h.scripts.OnClick(h,'RightButton'); assert(not h.visible)

-- A delayed model appears fully opaque and cannot revive a finished panel.
-- Missing models fade their document icon instead.
local setCreature=h.Model.SetCreature
h.Model.SetCreature=function() end
local saved=WowVoiceDB.questSpeakers
WowVoiceDB.questSpeakers={}
h,t=start()
advance(t+0.375)
assert(h.Icon.visible and h.Model.alpha==0); opacity(h,1,false)
h.Model:CompleteLoad(10658)
assert(not h.Icon.visible and h.Model.alpha==1); opacity(h,1)
advance(t+WowVoiceDur['179a']+WowVoiceDB.tail+0.01)
h.Model:CompleteLoad(10658)
assert(h.Model.animation==0 and not h.Model.talkAnimation)
advance(now+0.5); opacity(h,0.5)
WV:Silence(); assert(not h.visible)
h.Model:CompleteLoad(10658); assert(not h.visible)
h.Model.SetCreature=setCreature
WowVoiceDB.questSpeakers=saved
print('PASS: instant appearance, no mid-playback fades, synchronized model/UI fade, immediate close, replacement, preview and late model safety')

-- A reused completed bar has no visible fill at the start of the next line,
-- even when the native renderer has not yet updated its hidden geometry.
for _, afterFade in ipairs({false, true}) do
    h,t=start()
    advance(t+WowVoiceDur['179a']+WowVoiceDB.tail+0.01)
    near(h.Progress.value,1)
    if afterFade then advance(now+2) end
    local show, staleFill = h.Show, false
    function h:Show()
        staleFill = staleFill or self.Progress:IsShown()
        return show(self)
    end
    assert(WV:ReplayQuest(861))
    h.Show=show
    assert(not staleFill and not h.Progress:IsShown(), 'new head must not reveal the old progress texture')
    near(h.Progress.value,0)
    advance(now+0.1)
    assert(h.Progress:IsShown() and h.Progress.value>0 and h.Progress.value<0.1)
    WV:Silence()
end
print('PASS: completed progress stays hidden at zero when a new head starts, during and after fade')

-- Client trace: preparing the SECOND head takes ~2 ms. Its first positive
-- progress is set before OnUpdate, while the old native fill was still full.
-- Exercise that nonzero interval instead of only the frozen mock clock.
for _, afterFade in ipairs({false, true}) do
    h,t=start()
    advance(t+WowVoiceDur['179a']+WowVoiceDB.tail+0.01)
    near(h.Progress.Fill:GetWidth(), h.Progress:GetWidth())
    if afterFade then advance(now+2) end
    local clock, show, barShow = WV.PlaybackTime, h.Show, h.Progress.Show
    local preparationTime, checked = 0, false
    WV.PlaybackTime = function() return clock()+preparationTime end
    function h:Show()
        show(self)
        preparationTime = 0.002
    end
    function h.Progress:Show()
        if self:GetValue()>0 then
            checked = true
            assert(self.Fill:GetWidth()<1, 'second head must not reveal the previous full fill before its first update')
        end
        return barShow(self)
    end
    assert(WV:ReplayQuest(861))
    assert(checked and h.Progress:GetValue()>0, 'must exercise nonzero progress during synchronous preparation')
    h.Show, h.Progress.Show, WV.PlaybackTime = show, barShow, clock
    advance(now+0.2)
    near(h.Progress.Fill:GetWidth(), h.Progress:GetWidth()*h.Progress:GetValue())
    WV:Silence()
end
print('PASS: second head has correct fill before its first frame, including nonzero preparation time and reuse during/after fade')

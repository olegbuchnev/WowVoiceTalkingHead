local WV=WowVoice
WV:ResetHeadSettings()
command('options')
WV:RefreshHeadOptions()
local panel=frames.WowVoiceOptionsPanel
local slider,input=panel.ScaleSlider,panel.ScaleInput
local head,anchor=frames.WowVoiceTalkingHead,frames.WowVoiceTalkingHeadAnchor
local function assertTextScaling(smooth)
    for _,text in ipairs({head.Name,head.Body,head.TextMeasure}) do
        assert(text:GetSmoothScaling()==smooth,'smooth glyph scaling must only be active during dragging')
        local _,size=text:GetFont()
        assert(size==(text==head.Name and 18 or 13),'native font sizes must be retained')
    end
end
assertTextScaling(false)
assert(slider.value==100 and input:GetText()=='100')
assert(slider.minValue==50 and slider.maxValue==150 and slider.valueStep==1 and not slider.obeyStep)
local played,stopped=#plays,#stops
WV:ToggleHeadPreview()
for _,percent in ipairs({50,87,100,150}) do
    slider:SetValue(percent)
    assert(head:GetScale()==percent/100 and WowVoiceDB.headScale==percent/100)
    assert(input:GetText()==tostring(percent))
    assert(math.abs(anchor:GetWidth()-head:GetWidth()*percent/100)<0.0001)
    assert(anchor:GetHeight()==head:GetHeight()*percent/100)
    assert(WowVoiceDB.headPosition==nil,'scaling must retain the automatic action-bar anchor')
end
assert(#plays==played and #stops==stopped,'changing scale must not play audio')
-- Dragging must never call the model/text layout path until release.
local setHeadScale,mouseDownApi=WV.SetHeadScale,IsMouseButtonDown
local scaleCalls,mouseDown=0,false
WV.SetHeadScale=function(self,scale,temporary)
    if not temporary then scaleCalls=scaleCalls+1 end
    return setHeadScale(self,scale,temporary)
end
IsMouseButtonDown=function(button) return button=='LeftButton' and mouseDown end
local scrollPlan,scrollOffset,progress=head.scrollPlan,head.TextScroll.scroll,head.Progress.value
local cameraRefreshes=head.Model.cameraRefreshes
local modelSize,bodyWidth=head.Model.SetSize,head.Body.SetWidth
local geometryWrites=0
head.Model.SetSize=function(self,...) geometryWrites=geometryWrites+1; return modelSize(self,...) end
head.Body.SetWidth=function(self,...) geometryWrites=geometryWrites+1; return bodyWidth(self,...) end
mouseDown=true
-- Native track clicks may deliver a value before OnMouseDown.
slider:SetValue(120)
slider.scripts.OnMouseDown(slider,'LeftButton')
local snapshot,capture=frames.WowVoiceHeadScaleSnapshot,frames.WowVoiceHeadScaleCapture
local freezeWrites=geometryWrites
geometryWrites=0
assertTextScaling(true)
local capturedScale=head.Model:GetEffectiveScale()
assert(not snapshot:IsShown() and not capture.captures,'capture must wait for native rendering')
capture:RenderFrame()
assert(not capture.captures,'one frame is too early for a snapshot')
capture:RenderFrame()
assert(snapshot:IsShown() and capture.captures==1 and capture.maxSnapshots==1)
assert(not capture:IsShown() and snapshot:GetScale()==1.2,'hide the original and apply the latest slider value when ready')
assert(head.Model:GetKeepModelOnHide(),'the hidden source must retain the captured model')
for _,percent in ipairs({110,80,112}) do
    slider:SetValue(percent)
    now=now+2
    snapshot.scripts.OnUpdate(snapshot)
    slider.scripts.OnUpdate(slider)
    WV:RefreshHeadOptions()
    assert(input:GetText()==tostring(percent) and slider.value==percent)
    assert(snapshot:GetScale()==percent/100 and head:GetScale()==1.5 and WowVoiceDB.headScale==1.5 and scaleCalls==0,
        'dragging must scale the captured texture, never the live panel')
    assert(head:GetParent()==capture and head.Model:GetEffectiveScale()==capturedScale)
    assert(capture.captures==1 and snapshot.Texture.snapshotID==1,'reuse one immutable capture throughout the drag')
    assert(math.abs(anchor:GetWidth()-head:GetWidth()*percent/100)<0.0001)
    assert(head.Model:GetPaused() and head.scrollPlan==scrollPlan and geometryWrites==0)
    assert(head.TextScroll.scroll==scrollOffset and head.Progress.value==progress,
        'the current text and progress must freeze while dragging')
    assert(head.Model.cameraRefreshes==cameraRefreshes,'dragging must not refresh the camera')
end
mouseDown=false
slider.scripts.OnMouseUp(slider,'LeftButton')
slider.scripts.OnUpdate(slider)
assert(head:GetScale()==1.12 and scaleCalls==1,'release must apply only the final value once')
assertTextScaling(false)
assert(head:GetParent()==anchor and not snapshot:IsShown() and capture.snapshotID==nil,
    'release must restore the live panel and free the snapshot')
assert(not head.Model:GetKeepModelOnHide(),'restore the original model retention setting')
assert(not head.Model:GetPaused() and geometryWrites==2+freezeWrites,'release must restore text and rebuild once')
assert(head.TextScroll.scroll==scrollOffset and head.Progress.value==progress,'preview clock must resume from the frozen frame')
head.Model.SetSize,head.Body.SetWidth=modelSize,bodyWidth
mouseDown=true
slider.scripts.OnMouseDown(slider,'LeftButton')
slider:SetValue(90)
mouseDown=false
slider.scripts.OnUpdate(slider) -- release outside the control, without OnMouseUp
slider.scripts.OnMouseUp(slider,'LeftButton')
assert(head:GetScale()==0.9 and scaleCalls==2,'outside release must apply exactly once')
mouseDown=true
slider.scripts.OnMouseDown(slider,'LeftButton')
slider:SetValue(110); slider:SetValue(90)
mouseDown=false
slider.scripts.OnMouseUp(slider,'LeftButton')
assert(scaleCalls==2,'returning to the saved percentage must not rebuild the model')
assertTextScaling(false)
mouseDown=true
slider.scripts.OnMouseDown(slider,'LeftButton')
slider:SetValue(130)
panel:Hide()
mouseDown=false
panel:Show()
slider.scripts.OnUpdate(slider)
assert(head:GetScale()==0.9 and WowVoiceDB.headScale==0.9 and scaleCalls==2)
assert(not head.Model:GetPaused(),'closing options must unpause the model')
assertTextScaling(false)
assert(head:GetParent()==anchor and not snapshot:IsShown() and capture.snapshotID==nil)
assert(slider.value==90 and input:GetText()=='90','closing options must cancel a pending drag')
WV.SetHeadScale,IsMouseButtonDown=setHeadScale,mouseDownApi
WV:ToggleHeadPreview()
-- Capture failures must restore the tree and still resize while dragging.
for _,mode in ipairs({'error','empty','apply-failed'}) do
    snapshotMode=mode
    WV:BeginHeadScalePreview()
    assert(WV:SetHeadScale(1.2,true))
    for i=1,6 do capture:RenderFrame() end
    assert(head:GetParent()==anchor and head:GetScale()==1.2 and not snapshot:IsShown())
    assert(head.Model:GetPaused() and WowVoiceDB.headScale==0.9)
    local refreshes=head.Model.cameraRefreshes
    local rectUpdates=head.TextScroll.scrollRectUpdates
    local frozenOffset,frozenPlan=head.TextScroll:GetVerticalScroll(),head.scrollPlan
    local setText,setFont,setWidth=head.Body.SetText,head.Body.SetFont,head.Body.SetWidth
    local function noTextRebuild() error('dragging must not rebuild text or its line layout') end
    head.Body.SetText,head.Body.SetFont,head.Body.SetWidth=noTextRebuild,noTextRebuild,noTextRebuild
    local zoom,position,rotation=head.Model.SetPortraitZoom,head.Model.SetPosition,head.Model.SetRotation
    local function noCameraReset() error('live drag must preserve the configured camera') end
    head.Model.SetPortraitZoom,head.Model.SetPosition,head.Model.SetRotation=noCameraReset,noCameraReset,noCameraReset
    for _,scale in ipairs({0.8,0.6,0.7,0.7}) do assert(WV:SetHeadScale(scale,true)) end
    assert(head:GetScale()==1.2 and head.Model.cameraRefreshes==refreshes,'slider events must be coalesced before rendering')
    head.scripts.OnUpdate(head)
    assert(head:GetScale()==0.7 and head.Model.cameraRefreshes==refreshes+1,'apply the latest scale with exactly one camera refresh per frame')
    assert(head.TextScroll.scrollRectUpdates==rectUpdates+1 and head.TextScroll:GetVerticalScroll()==frozenOffset
        and head.scrollPlan==frozenPlan,'update native clipping once while preserving the frozen text position')
    WV:SetHeadScale(0.7,true)
    head.scripts.OnUpdate(head)
    head.scripts.OnUpdate(head)
    assert(head.Model.cameraRefreshes==refreshes+1,'unchanged percentages must not reset the camera')
    assert(head.TextScroll.scrollRectUpdates==rectUpdates+1,'unchanged percentages must not invalidate text clipping')
    head.Body.SetText,head.Body.SetFont,head.Body.SetWidth=setText,setFont,setWidth
    head.Model.SetPortraitZoom,head.Model.SetPosition,head.Model.SetRotation=zoom,position,rotation
    WV:EndHeadScalePreview(true)
    assertTextScaling(false)
    assert(not head.Model:GetPaused() and capture.snapshotID==nil and head:GetScale()==0.9)
    assert(not capture.scripts.OnUpdate,'failed/cancelled capture must stop retrying')
end
snapshotMode='apply-nil'
WV:BeginHeadScalePreview()
WV:SetHeadScale(1.1,true)
capture:RenderFrame(); capture:RenderFrame()
assert(snapshot:IsShown() and snapshot:GetScale()==1.1 and not capture:IsShown(),
    'clients with no ApplySnapshot return value must still show the captured texture')
WV:EndHeadScalePreview(true)
snapshotMode=nil
-- Fractional drag positions must reach rendering even within one displayed percent.
for _,mode in ipairs({'empty','apply-nil'}) do
    snapshotMode=mode
    WV:SetHeadScale(0.9)
    slider.scripts.OnMouseDown(slider,'LeftButton')
    slider:SetValue(90.1)
    for i=1,6 do capture:RenderFrame() end
    local visual=mode=='empty' and head or snapshot
    assert(math.abs(visual:GetScale()-0.901)<0.000001 and input:GetText()=='90')
    slider:SetValue(90.4)
    visual.scripts.OnUpdate(visual)
    assert(math.abs(visual:GetScale()-0.904)<0.000001 and WowVoiceDB.headScale==0.9,
        'sub-percent changes must render without writing the saved scale')
    slider.scripts.OnMouseUp(slider,'LeftButton')
    assert(head:GetScale()==0.9 and slider.value==90 and WowVoiceDB.headScale==0.9,
        'release must remove fractional preview scale even when the saved percent is unchanged')
    slider.scripts.OnMouseDown(slider,'LeftButton')
    slider:SetValue(90.6)
    for i=1,6 do capture:RenderFrame() end
    slider.scripts.OnMouseUp(slider,'LeftButton')
    assert(head:GetScale()==0.91 and WowVoiceDB.headScale==0.91 and input:GetText()=='91',
        'release must commit the nearest whole percent')
    assertTextScaling(false)
end
snapshotMode=nil
WV:BeginHeadScalePreview()
local lateCapture=capture.scripts.OnUpdate
WV:EndHeadScalePreview(true)
lateCapture(capture)
assert(head:GetParent()==anchor and not snapshot:IsShown() and not capture.scripts.OnUpdate,
    'release before capture must not allow a late callback to replace the live panel')
local function enter(text)
    input:SetFocus()
    input:SetText(text)
    input.scripts.OnEnterPressed(input)
end
enter('87')
assertTextScaling(false)
assert(slider.value==87 and head:GetScale()==0.87 and not input.focus)
for _,text in ipairs({'','49','151','abc','87.5','1e2'}) do
    enter(text)
    assert(head:GetScale()==0.87 and WowVoiceDB.headScale==0.87 and input.focus)
    assert(panel.Status:GetText()~='')
end
input.scripts.OnEscapePressed(input)
assert(input:GetText()=='87' and not input.focus)
input:SetFocus(); input:SetText('120'); input:ClearFocus()
assert(input:GetText()=='87' and head:GetScale()==0.87,'leaving the field cancels uncommitted text')

-- Saved coordinates are in UIParent units, even when the UI itself is scaled.
UIParent.scale=0.75
local scaleEvents=frames.WowVoiceHeadScaleEvents
scaleEvents.scripts.OnEvent(scaleEvents,'UI_SCALE_CHANGED')
assert(WV:ApplyHeadSettings({width=570,height=155,scale=1,x=123,y=-200}))
local pivotX,pivotY=WV:GetHeadAnchorPosition()
local function samePivot()
    local x,y=WV:GetHeadAnchorPosition()
    assert(math.abs(x-pivotX)<0.00001 and math.abs(y-pivotY)<0.00001)
end
slider:SetValue(150)
local settings=WV:GetHeadSettings()
samePivot(); assert(settings.scale==1.5)
WV:BeginHeadScalePreview()
assert(WV:SetHeadScale(0.8,true))
settings=WV:GetHeadSettings()
-- The temporary transform is applied on the next render.
head.scripts.OnUpdate(head)
samePivot(); assert(settings.scale==0.8)
WV:EndHeadScalePreview(true)
settings=WV:GetHeadSettings()
samePivot(); assert(settings.scale==1.5,'cancel must restore scale and position')
assert(head:GetEffectiveScale()==0.75*1.5)
assert(head.Model:GetEffectiveScale()==head:GetEffectiveScale())
assert(WV:ApplyHeadSettings({width=570,height=155,scale=0.5,x=10000,y=10000}))
WV:SetHeadScale(1.5)
settings=WV:GetHeadSettings()
assert(settings.x+anchor:GetWidth()/2-13*settings.scale<=UIParent:GetWidth()/2)
assert(settings.x-anchor:GetWidth()/2+15*settings.scale>=-UIParent:GetWidth()/2)
assert(settings.y+anchor:GetHeight()/2-15*settings.scale<=UIParent:GetHeight()/2)
assert(settings.y-anchor:GetHeight()/2>=-UIParent:GetHeight()/2)
pivotX,pivotY=WV:GetHeadAnchorPosition()
panel.Buttons.resetScale.scripts.OnClick()
settings=WV:GetHeadSettings()
samePivot(); assert(settings.scale==1)
assert(slider.value==100 and input:GetText()=='100')
WV:SetHeadScale(1.25)
panel.Buttons.reset.scripts.OnClick()
assert(WowVoiceDB.headPosition==nil and head:GetScale()==1.25,'position reset must preserve scale')
panel:Hide()
panel:Show()
assert(input:GetText()=='125' and slider.value==125 and not head:IsShown())
assert(WV:ReplayQuest(179))
assert(head:GetScale()==1.25,'normal playback must use the saved preview scale')
local before=#plays
slider:SetValue(110)
assert(head:GetScale()==1.1 and #plays==before,'live scaling must not restart playback')
local playbackProgress,stopCount=head.Progress.value,#stops
WV:BeginHeadScalePreview()
assert(WV:SetHeadScale(1.2,true))
capture:RenderFrame(); capture:RenderFrame()
assert(snapshot:IsShown() and not capture:IsShown())
now=now+3
snapshot.scripts.OnUpdate(snapshot)
assert(head.Progress.value==playbackProgress and #plays==before and #stops==stopCount,
    'freezing visuals must not stop or restart real audio')
WV:EndHeadScalePreview(true)
assert(head:GetScale()==1.1 and head.Progress.value>playbackProgress and not head.Model:GetPaused(),
    'real playback must catch up to the audio clock after release')
WV:BeginHeadScalePreview()
WV:SetHeadScale(0.8,true)
capture:RenderFrame(); capture:RenderFrame()
WV:Silence()
assert(not head.Model:GetPaused() and head:GetScale()==1.1,'stopping playback must clear temporary scale and pause')
assert(not snapshot:IsShown() and head:GetParent()==anchor,'stopping audio must remove the visible snapshot')
UIParent:SetSize(700,400)
local ok,reason=WV:SetHeadScale(1.5)
assert(not ok and reason and WowVoiceDB.headScale==1.1,'oversized panels must leave settings unchanged')
UIParent:SetSize(1920,1080)
UIParent.scale=1
WV:ResetHeadSettings()
-- Freeze measured line boundaries, including UTF-8, formatting and paragraphs.
WV:ToggleHeadPreview()
local originalBody,originalName=head.Body:GetText(),head.Name:GetText()
local bodySource='Привет мир друг\n\nЭто |cffff0000красный|r текст |Hquest:1|hссылка|h'
local bodyFrozen='Привет мир \nдруг\n\nЭто |cffff0000красный|r \nтекст |Hquest:1|hссылка|h'
local nameSource,nameFrozen='Очень длинное имя','Очень \nдлинное имя'
nativeWordWrap=true
local measurementReads=0
local getMeasureHeight=head.ScaleTextMeasure.GetStringHeight
head.ScaleTextMeasure.GetStringHeight=function(self)
    measurementReads=measurementReads+1
    return getMeasureHeight(self)
end
for _,mode in ipairs({'empty','apply-nil'}) do
    snapshotMode=mode
    WV:SetHeadScale(1)
    head.Body:SetText(bodySource); head.Body:SetWidth(78)
    head.Name:SetText(nameSource); head.Name:SetWidth(108)
    local bodyWidth,nameWidth=head.Body:GetWidth(),head.Name:GetWidth()
    local bodyHeight,nameHeight=head.Body:GetStringHeight(),head.Name:GetStringHeight()
    local plan,offset=head.scrollPlan,head.TextScroll:GetVerticalScroll()
    WV:BeginHeadScalePreview()
    assert(head.Body:GetText()==bodyFrozen and head.Name:GetText()==nameFrozen,
        'preview must retain whole-word wraps, blank paragraphs and color/link markup')
    assert(head.Body:CanWordWrap() and head.Body:GetWidth()>bodyWidth,
        'multiline rendering must remain enabled with room for each frozen line')
    assert(head.Body:GetStringHeight()==bodyHeight and head.Name:GetStringHeight()==nameHeight,
        'beginning a drag must preserve the original line count, never collapse to one line')
    local reads=measurementReads
    for i=1,6 do capture:RenderFrame() end
    for _,scale in ipairs({0.711,1.343,0.928}) do
        WV:SetHeadScale(scale,true)
        local visual=mode=='empty' and head or snapshot
        visual.scripts.OnUpdate(visual)
        assert(head.Body:GetText()==bodyFrozen and head.Name:GetText()==nameFrozen and measurementReads==reads,
            'scaling must reuse the captured lines without measuring or reformatting them')
        assert(head.scrollPlan==plan and head.TextScroll:GetVerticalScroll()==offset)
    end
    WV:EndHeadScalePreview(mode=='empty')
    assert(head.Body:GetText()==bodySource and head.Name:GetText()==nameSource,
        'commit and cancellation must restore the exact original text')
    assert(head.Body:CanWordWrap() and head.Body:CanNonSpaceWrap())
    assert(head.Body:GetWidth()==(mode=='empty' and bodyWidth or head:GetWidth()-194)
        and head.Name:GetWidth()==(mode=='empty' and nameWidth or head:GetWidth()-194))
    assert(head:GetScale()==(mode=='empty' and 1 or 0.93))
    assertTextScaling(false)
end
-- Invalid measurement and one-line rendering must leave the original intact.
for _,measureHeight in ipairs({function() error('not supported') end,
    function(self) if self:GetWidth()>1000 then return self.fontSize end; return getMeasureHeight(self) end}) do
    head.Body:SetWidth(78)
    head.ScaleTextMeasure.GetStringHeight=measureHeight
    WV:BeginHeadScalePreview()
    assert(head.Body:GetText()==bodySource and head.Body:CanWordWrap() and head.Body:GetWidth()==78,
        'failed validation must never replace a multiline source with a single line')
    WV:EndHeadScalePreview(true)
end
head.ScaleTextMeasure.GetStringHeight=getMeasureHeight
local getBodyHeight=head.Body.GetStringHeight
head.Body.GetStringHeight=function(self)
    if self:GetWidth()>1000 then return self.fontSize end
    return getBodyHeight(self)
end
WV:BeginHeadScalePreview()
assert(head.Body:GetText()==bodySource and head.Body:GetWidth()==78,
    'a renderer that collapses even a verified candidate must roll back immediately')
WV:EndHeadScalePreview(true)
head.Body.GetStringHeight=getBodyHeight
nativeWordWrap=nil
head.Body:SetText(originalBody); head.Name:SetText(originalName)
snapshotMode=nil
WV:HideHeadPreview()
WV:ResetHeadSettings()
-- Vertex previews preserve native glyph metrics, then transform the entire text
-- viewport by precisely the panel's scale ratio (including fractional values).
local oldEnum=Enum
Enum={FontStringScaleAnimationMode={FontSize=0,Vertex=1}}
WV:ToggleHeadPreview()
for _,cancel in ipairs({false,true}) do
    UIParent.scale=0.75
    frames.WowVoiceHeadScaleEvents.scripts.OnEvent()
    WV:SetHeadScale(1.12)
    head.TextScroll:SetVerticalScroll(17)
    local baseScale=head:GetScale()
    local fontScale=head.Body:GetEffectiveScale()
    local source,name=head.Body:GetText(),head.Name:GetText()
    local width,plan=head.Body:GetWidth(),head.scrollPlan
    local captures,rectUpdates=capture.captures,head.TextScroll.scrollRectUpdates
    local namePoint,scrollPoint={head.Name:GetPoint()},{head.TextScroll:GetPoint()}
    local scrollWidth,scrollHeight=head.TextScroll:GetWidth(),head.TextScroll:GetHeight()
    local contentWidth,contentHeight=head.TextContent:GetWidth(),head.TextContent:GetHeight()
    local modes={head.Name:GetScaleAnimationMode(),head.Body:GetScaleAnimationMode()}
    local modelWidth,modelHeight=head.Model:GetWidth(),head.Model:GetHeight()
    local modelPoint={head.Model:GetPoint()}
    local modelScale=head.Model:GetEffectiveScale()
    local cameraCount=head.Model.cameraRefreshes
    local originalMethods={}
    for _,region in ipairs({head.Name,head.Body,head.TextMeasure}) do
        for _,method in ipairs({'SetText','SetFont','SetWidth'}) do
            originalMethods[#originalMethods+1]={region,method,region[method]}
            region[method]=function() error('vertex preview must never rewrite or remeasure glyphs') end
        end
    end
    WV:BeginHeadScalePreview()
    local layer=head.TextScaleLayer
    assert(layer:IsShown() and layer.ignoreParentScale and head:GetParent()==anchor)
    assert(head.NameLayer:GetParent()==layer and head.TextScroll:GetParent()==layer)
    assert(head.Name:GetScaleAnimationMode()==1 and head.Body:GetScaleAnimationMode()==1)
    assertTextScaling(false)
    for step,scale in ipairs({1.111,0.803,1.499,0.957}) do
        WV:SetHeadScale(scale,true)
        head.scripts.OnUpdate(head)
        local ratio=scale/baseScale
        assert(math.abs(head.Body:GetEffectiveScale()-fontScale)<0.000001
            and math.abs(head.Name:GetEffectiveScale()-fontScale)<0.000001,
            'font rasterization scale must stay fixed while the panel scale changes')
        assert(layer.Group.playing and layer.Group.looping=='REPEAT'
            and layer.Transform.from[1]==ratio and layer.Transform.to[1]==ratio
            and layer.Transform.from[2]==ratio and layer.Transform.to[2]==ratio,
            'both axes must use the exact same constant transform, without integer font rounding')
        assert(layer.Transform.origin[1]=='TOPLEFT' and layer.Transform.origin[2]==0)
        assert(head.Body:GetText()==source and head.Name:GetText()==name and head.Body:GetWidth()==width)
        assert(head.scrollPlan==plan and head.TextScroll:GetVerticalScroll()==17*ratio
            and head.TextScroll.scrollRectUpdates==rectUpdates+step,
            'the native scroll offset must track the scaled glyph position')
        local screenScale=head:GetEffectiveScale()
        local fixedScale=head.TextScroll:GetEffectiveScale()
        local function same(a,b) return math.abs(a-b)<0.000001 end
        -- Actual native anchoring/clipping uses fixedScale, independent of the
        -- animation. Compare screen rectangles with the desired panel-relative
        -- rectangle; this catches the observed stationary offset/overflow bug.
        assert(same(head.Name.point[4]*fixedScale,namePoint[4]*screenScale)
            and same(head.Name.point[5]*fixedScale,namePoint[5]*screenScale),
            'the title offset must shrink and grow proportionally with the panel')
        local point=head.TextScroll.points[1]
        assert(same(point[4]*fixedScale,scrollPoint[4]*screenScale)
            and same(point[5]*fixedScale,scrollPoint[5]*screenScale)
            and same(head.TextScroll:GetWidth()*fixedScale,scrollWidth*screenScale)
            and same(head.TextScroll:GetHeight()*fixedScale,scrollHeight*screenScale),
            'native clipping must follow all four edges of the scaled viewport')
        assert(same(head.TextContent:GetHeight()*fixedScale,contentHeight*screenScale)
            and same(head.TextContent:GetWidth()*fixedScale,contentWidth*screenScale)
            and same(head.TextScroll:GetVerticalScroll()*fixedScale,17*screenScale),
            'content extent and scroll offset must use the same screen scale as the viewport')
        assert(capture.captures==captures and head.Model:GetEffectiveScale()==modelScale
            and head.Model.cameraRefreshes==cameraCount,
            'portrait resizing must keep native scale fixed without captures or camera refreshes')
        local point=head.Model.points[1]
        assert(same(point[4]*modelScale,modelPoint[4]*screenScale)
            and same(point[5]*modelScale,modelPoint[5]*screenScale)
            and same(head.Model:GetWidth()*modelScale,modelWidth*screenScale)
            and same(head.Model:GetHeight()*modelScale,modelHeight*screenScale),
            'the model viewport must match the scaled portrait rectangle on every side')
    end
    local plays=layer.Group.plays
    WV:SetHeadScale(0.957,true); head.scripts.OnUpdate(head)
    assert(layer.Group.plays==plays,'duplicate input must not restart the transform')
    for _,entry in ipairs(originalMethods) do entry[1][entry[2]]=entry[3] end
    WV:EndHeadScalePreview(cancel)
    assert(not layer:IsShown() and not layer.Group.playing)
    assert(head.NameLayer:GetParent()==head and head.TextScroll:GetParent()==head)
    assert(head.Name:GetScaleAnimationMode()==modes[1] and head.Body:GetScaleAnimationMode()==modes[2])
    assert(head.Name:GetText()==name and head.Body:GetText()==source)
    assert(head:GetScale()==(cancel and 1.12 or 0.96))
    if cancel then
        assert(head.TextScroll:GetWidth()==scrollWidth and head.TextScroll:GetHeight()==scrollHeight
            and head.TextContent:GetWidth()==contentWidth and head.TextContent:GetHeight()==contentHeight,
            'cancellation must restore native viewport and content dimensions')
    end
    assert(head.Name.point[2]==namePoint[2] and head.TextScroll.points[1][2]==scrollPoint[2])
    assert(head.Body:GetEffectiveScale()==head:GetEffectiveScale())
    assert(not head.Model:IsIgnoringParentScale() and head.Model:GetScale()==1
        and head.Model:GetWidth()==modelWidth and head.Model:GetHeight()==modelHeight
        and head.Model.points[1][4]==modelPoint[4] and head.Model.points[1][5]==modelPoint[5],
        'commit and cancellation must restore the original model scale, dimensions and anchor')
end
WV:BeginHeadScalePreview()
WV:SetHeadScale(0.83,true); head.scripts.OnUpdate(head)
panel:Hide()
assert(not head.TextScaleLayer.Group.playing and not head.TextScaleLayer:IsShown()
    and head.TextScroll:GetParent()==head,'closing options must restore the normal text tree')
panel:Show()
assert(WV:ReplayQuest(179))
WV:BeginHeadScalePreview()
WV:SetHeadScale(0.76,true); head.scripts.OnUpdate(head)
WV:Silence()
assert(not head.TextScaleLayer.Group.playing and head.NameLayer:GetParent()==head,
    'stopping playback must release the vertex preview')
-- Starting a drag from an idle panel must open the silent preview automatically.
local originalStart,originalMouse=WV.StartTalkingHead,IsMouseButtonDown
local starts,held=0,false
WV.StartTalkingHead=function(self,...)
    starts=starts+1
    return originalStart(self,...)
end
IsMouseButtonDown=function(button) return button=='LeftButton' and held end
local playsBefore,stopsBefore=#plays,#stops
assert(not head:IsShown())
held=true
slider:SetValue(115.4) -- Native value callback may precede the mouse-down callback.
slider.scripts.OnMouseDown(slider,'LeftButton')
head.scripts.OnUpdate(head)
assert(head:IsShown() and starts==1 and head.Model:GetPaused() and math.abs(head:GetScale()-1.154)<0.000001,
    'the first slider event must show and freeze a silent preview exactly once')
assert(#plays==playsBefore and #stops==stopsBefore,'automatic preview must not start audio')
held=false
slider.scripts.OnMouseUp(slider,'LeftButton')
assert(head:IsShown() and not head.Model:GetPaused() and WowVoiceDB.headScale==1.15,
    'release must retain the panel during its fade and commit the saved scale')
held=true
slider.scripts.OnMouseDown(slider,'LeftButton')
slider:SetValue(126.2); head.scripts.OnUpdate(head)
assert(starts==1,'dragging an existing test must not toggle it off or restart it')
panel:Hide(); held=false
assert(not head:IsShown() and WowVoiceDB.headScale==1.15 and not head.TextScaleLayer.Group.playing,
    'closing options must cancel a drag and close the automatically opened test')
panel:Show()
assert(WV:ReplayQuest(179))
local realText,realStarts=head.Body:GetText(),starts
playsBefore,stopsBefore=#plays,#stops
held=true
slider.scripts.OnMouseDown(slider,'LeftButton')
slider:SetValue(107.2); head.scripts.OnUpdate(head)
held=false
slider.scripts.OnUpdate(slider)
panel:Hide()
assert(starts==realStarts and head.Body:GetText()==realText and head:IsShown()
    and #plays==playsBefore and #stops==stopsBefore,
    'automatic preview must reuse real playback and leave it running when options close')
WV:Silence()
WV.StartTalkingHead,IsMouseButtonDown=originalStart,originalMouse
panel:Show()
-- Exercise the reported order on one native PlayerModel: test -> NPC -> test.
local model=head.Model
local clearModel,refreshCamera=model.ClearModel,model.RefreshCamera
local clears=0
model.ClearModel=function(self,...)
    clears=clears+1
    return clearModel(self,...)
end
model.RefreshCamera=function(self,...)
    assert(not self:GetDoBlend(),'camera refresh must not inherit a model transition')
    return refreshCamera(self,...)
end
local traceMessages=#messages
for index,kind in ipairs({'test','briefing','test'}) do
    if kind=='test' then WV:ToggleHeadPreview() else assert(WV:ReplayQuest(179)) end
    assert(head.Model==model and model.portraitReady)
    if kind=='test' then assert(model.unitBlend==false,'SetUnit must explicitly disable native blending') end
    local display,clearCount=model:GetDisplayInfo(),clears
    local playCount,stopCount=#plays,#stops
    -- Model loading can leave native blend state behind. The drag must reset it.
    model:SetDoBlend(true)
    WV:BeginHeadScalePreview()
    assert(not model:GetDoBlend() and model:GetPaused())
    -- Speaker capture and model warm-up may both finish during the same drag.
    WV:RefreshTalkingHeadModel()
    WV:RefreshTalkingHeadModel()
    model:SetDoBlend(true)
    model.scripts.OnModelLoaded(model)
    for _,scale in ipairs({1.01,0.97,1.14}) do
        WV:SetHeadScale(scale,true)
        head.scripts.OnUpdate(head)
        assert(clears==clearCount and model:GetDisplayInfo()==display and model.portraitReady,
            'late identity refresh must not clear or replace a frozen portrait')
        assert(model.modelAlpha>0 and not model:GetDoBlend() and model:GetPaused())
    end
    assert(#plays==playCount and #stops==stopCount,'portrait work must not alter playback')
    WV:EndHeadScalePreview(index==3)
    assert(clears==clearCount+1 and model.portraitReady and not model:GetPaused(),
        'release or cancellation must coalesce late model refreshes into one load')
    assert(not model:GetDoBlend())
end
assert(#messages==traceMessages,'scale diagnostics must not spam chat while dragging')
WV:HeadScaleDiagnostics()
assert(#messages==traceMessages+3,'diagnostics must retain only the last three drags')
for index,kind in ipairs({'test','NPC','test'}) do
    local row=messages[traceMessages+index]
    assert(row:find('Scale['..index..'] '..kind,1,true))
    assert(row:find('cam=0/full=0 view=3 load=1 reload=2',1,true),
        'diagnostics must distinguish camera refreshes, model events and deferred reload requests')
    assert(row:find('alpha0=0 hidden=0 unready=0 ids=0 unpaused=0 blend=0',1,true),
        'normal drag must report no visibility, identity or pause changes')
end
model.ClearModel,model.RefreshCamera=clearModel,refreshCamera
WV:HideHeadPreview()
Enum=oldEnum
UIParent.scale=1
frames.WowVoiceHeadScaleEvents.scripts.OnEvent()
WV:ResetHeadSettings()
print('PASS: fixed glyph metrics, proportional vertex transforms, frozen clipping, restoration, cancel and playback cleanup')
print('PASS: automatic silent slider preview, native callback ordering, reuse, cancellation and uninterrupted real playback')
print('PASS: test/NPC/test model reuse, explicit non-blended camera updates and deferred asynchronous identity reloads')
print('PASS: frozen word wraps, UTF-8/markup, multiline preservation, exact restoration and failed-render rollback')
print('PASS: whole-panel scale, slider/input synchronization, validation, cancel, screen bounds, independent resets and playback persistence')
print('PASS: render-delayed snapshot, hidden original, latest requested scale, live failure fallback, cancellation and audio clock continuity')
print('PASS: live drag coalesces events per frame, skips duplicate scales and preserves camera zoom/position/rotation')

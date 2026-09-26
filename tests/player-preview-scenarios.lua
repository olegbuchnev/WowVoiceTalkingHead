event('ADDON_LOADED')
local WV=WowVoice
local previousEUI=EllesmereUI
EllesmereUI={}
assert(WV:GetHeadPreset()=='retail','Retail is the default even when EllesmereUI is installed')
EllesmereUI=previousEUI
command('options')
assert(frames.WowVoiceOptionsPanel.Presets.retail.template=='UIRadioButtonTemplate',
    'clients without modern radio atlases keep the stock control')
playerDisplayID=0
assert(WV:ToggleHeadPreview())
local head=frames.WowVoiceTalkingHead
local anchor=frames.WowVoiceTalkingHeadAnchor
assert(anchor.points[1][2]==UIParent and anchor.points[1][3]=='BOTTOM'
    and anchor.points[1][4]==0 and anchor.points[1][5]==96,
    'clients without the managed container use the Retail XML fallback')

local bottomContainer=CreateFrame('Frame',nil,UIParent)
bottomContainer:SetSize(573,1)
bottomContainer:SetPoint('BOTTOM',UIParent,'BOTTOM',0,150)
BottomManagedFrameContainer=bottomContainer
WV:ResetHeadPosition()
local initialY=WV:GetHeadSettings().y
bottomContainer:ClearAllPoints()
bottomContainer:SetPoint('BOTTOM',UIParent,'BOTTOM',0,210)
assert(WV:GetHeadSettings().y==initialY+60 and WV:GetHeadSettings().x==0,
    'default follows the bottom action-bar boundary as Blizzard moves it')
for _, preset in ipairs({'classic','ellesmere','retail'}) do
    WV:SetHeadPreset(preset)
    assert(WowVoiceDB.headPosition==nil and anchor.points[1][2]==bottomContainer,
        'changing appearance must retain the automatic default anchor')
end
WV:HideHeadPreview()
assert(WowVoiceDB.headPosition==nil,'closing an unmoved preview must not freeze the default position')
WV:ToggleHeadPreview()
assert(WV:ApplyHeadSettings({width=570,height=155,scale=1,x=123,y=-200,enabled=true}))
bottomContainer:ClearAllPoints()
bottomContainer:SetPoint('BOTTOM',UIParent,'BOTTOM',0,260)
assert(WV:GetHeadSettings().x==123 and WV:GetHeadSettings().y==-200,
    'a saved position takes priority over the managed default')
WV:ResetHeadPosition()
assert(WowVoiceDB.headPosition==nil and anchor.points[1][2]==bottomContainer,
    'position reset restores the managed default')
BottomManagedFrameContainer=nil
WV:ResetHeadPosition()
print('PASS: Retail default anchor follows action bars, saved positions win, reset and preview preserve defaults')
local function checkStopLayout()
    local close,progress=head.Close,head.Progress
    local closeLeft=head.width+close.points[1][4]-close.width
    assert(close.visible and close.points[1][1]=='TOPRIGHT')
    assert(head.Name.point[4]+head.Name.width<=closeLeft+2,'name must leave room for close artwork')
    assert(progress.points[1][4]==8 and progress.width==head.width-16,'progress spans the bottom with equal insets')
    local progressTop=head.height-progress.points[1][5]-progress.height
    assert(-head.Model.points[1][5]+head.Model.height<progressTop,'portrait must clear progress')
    assert(-head.TextScroll.points[1][5]+head.TextScroll.height<progressTop,'text must clear progress')
    assert(head.Name.point[4]==head.TextScroll.points[1][4],'name aligns with quest text')
    assert(head.Model.points[1][4]+head.Model.width<head.Name.point[4],'portrait stays left of the heading')
    assert(head.Model.points[1][5]-head.Name.point[5]==4,'heading sits four units below the model top as in Retail')
end
assert(head.width==570 and head.height==155 and head:GetScale()==1,'default panel must be 570x155 at 100% scale')
checkStopLayout()
assert(head.Model:GetDisplayInfo()==0 and head.Model.alpha==1 and not head.Icon.visible)
assert(head.Model.camera==nil and head.Model.zoom==1 and head.Model.animation==60)
WV:HideHeadPreview()
playerModelEvent=false
assert(WV:ToggleHeadPreview())
assert(head.Model.alpha==1 and not head.Icon.visible,'cached player must not remain transparent')
WV:HideHeadPreview()
playerModelEvent=true; modelLoadsImmediately=false
assert(WV:ToggleHeadPreview())
head.Model:CompleteLoad(0)
assert(head.Model.alpha==1 and not head.Icon.visible and head.Model.animation==60)
WV:HideHeadPreview()
head.Model:CompleteLoad(0)
assert(not head.visible,'late model callback must not reopen stopped test')
playerSetUnitSuccess=false
assert(WV:ToggleHeadPreview())
assert(head.Model.alpha==0 and head.Icon.visible,'failed SetUnit retains placeholder')
WV:HideHeadPreview()
assert(#plays==0 and #stops==0)
restored('1','0.37')
print('PASS: player displayID=0, cached/no-event and asynchronous model, late callback, failed SetUnit, silent preview')

playerSetUnitSuccess, modelLoadsImmediately = true, true
WV:ToggleHeadPreview()
local cameraRefreshes=head.Model.cameraRefreshes
local previousSize=head.Model.width
for _, dimensions in ipairs({{360,600,1},{1000,140,1},{470,160,2},{1000,600,.5}}) do
    assert(WV:ApplyHeadSettings({width=dimensions[1],height=dimensions[2],scale=dimensions[3],
        x=10000,y=10000,enabled=true}))
    local model=head.Model
    assert(model.width==model.height and model.width<=128,'portrait aspect must stay square at size extremes')
    local left,top=model.points[1][4],-model.points[1][5]
    assert(left>=0 and top>=0 and left+model.width<=140)
    assert(head.Name.point[4]==152,'header must align with the text column')
    assert(head.Name.width+head.Name.point[4]==head.width-42,'header reserves the close corner')
    local nameTop=-head.Name.point[5]
    assert(nameTop==top+4,'portrait must remain beside the header')
    assert(top+model.height<=head.height-14,'portrait must not overlap progress')
    assert(-head.TextScroll.points[1][5]>nameTop+head.Name.height,'quest text must remain below the header')
    checkStopLayout()
    assert(model.cameraRefreshes==cameraRefreshes+(model.width~=previousSize and 1 or 0),
        'refresh camera only when the portrait viewport changes')
    cameraRefreshes=model.cameraRefreshes
    previousSize=model.width
    local settings=WV:GetHeadSettings()
    assert(math.abs(settings.x)+dimensions[1]*dimensions[3]/2<=UIParent:GetWidth()/2)
    assert(math.abs(settings.y)+dimensions[2]*dimensions[3]/2<=UIParent:GetHeight()/2)
end
WV:HideHeadPreview()
assert(#plays==0 and #stops==0)
print('PASS: portrait aspect, camera refresh, header/content/button separation and screen bounds at extreme sizes/scales')

-- Full speaker names must fit the header, including wrapped names at minimum size.
for _, name in ipairs({'Джорн Заклинатель Небес',string.rep('Long speaker name ',10)}) do
    WV:StartTalkingHead({questId=179,section='a',speaker={name=name,npcID=3387},text='Quest text'},now+60,60)
    assert(WV:ApplyHeadSettings({width=360,height=140,scale=1,x=0,y=0,enabled=true}))
    assert(head.Name.text==name)
    assert(head.Name.point[4]==head.TextScroll.points[1][4])
    assert(head.Name.point[4]+head.Name.width==head.width-42)
    assert(head.Name.height>=head.Name:GetStringHeight(),'header must not truncate wrapped names')
    local headerBottom=-head.Name.point[5]+head.Name.height
    local modelTop=-head.Model.points[1][5]
    local textTop=-head.TextScroll.points[1][5]
    assert(modelTop==-head.Name.point[5]-4 and modelTop+head.Model.height<=head.height-14)
    assert(textTop>headerBottom and textTop+head.TextScroll.height<=head.height-14)
    checkStopLayout()
end
WV:StopTalkingHead()
print('PASS: long speaker names wrap above the text without moving the portrait or overlapping content')

-- Retail decorations must disappear when switching to another preset.
WV:SetHeadPreset('retail')
WV:ToggleHeadPreview()
assert(head.backdrop==nil and head.RetailBackground.visible and head.PortraitBackground.visible)
assert(head.PortraitOverlay.visible and head.PortraitOverlay.frameLevel>head.Model:GetFrameLevel())
assert(head.Close.visible and head.Stop==nil)
checkStopLayout()
assert(-head.Model.points[1][5]+head.Model.height/2+head.PortraitOverlay.height/2<=head.height-4,
    'Retail ornament must clear progress')
assert(head.Model.width==head.Model.height and head.Model.width>72)
assert(head.Name.point[4]==head.TextScroll.points[1][4])
assert(head.Model.points[1][4]+head.Model.width<head.Name.point[4])
assert(head.Name.point[4]+head.Name.width<=head.width-42,'title leaves room for close')
assert(head.PortraitOverlay.width>head.Model.width,'ornament surrounds the model')
head.Close.scripts.OnClick()
assert(not head.visible and #plays==0 and #stops==0,'Retail close ends silent preview')
WV:StartTalkingHead({questId=179,section='a',speaker={name=string.rep('Long name ',20),itemID=42},
    text=string.rep('Quest text ',80)},now+60,60)
assert(head.Icon.visible and head.PortraitOverlay.visible)
assert(head.Name.height>=head.Name:GetStringHeight())
assert(-head.TextScroll.points[1][5]>=-head.Name.point[5]+head.Name.height)
assert(-head.TextScroll.points[1][5]+head.TextScroll.height<=head.height-14)
WV:SetHeadPreset('ellesmere')
assert(not head.RetailBackground.visible and not head.PortraitBackground.visible and not head.PortraitOverlay.visible)
assert(head.Close.visible and head.Close.Glyph.visible and head.backdrop)
assert(not head.Close.Stock.visible and not head.Close.Highlight.visible,
    'Ellesmere close hides all stock artwork')
assert(head.Close.normalTexture==nil and head.Close.pushedTexture==nil and head.Close.highlightTexture==nil,
    'close must not populate native texture slots that can retain stock artwork')
assert(head.Close.Glyph.atlas=='uitools-icon-close' and head.Close.Glyph.width==14)
assert(head.Close.Glyph.vertexColor[4]==0.75)
head.Close.scripts.OnEnter()
assert(head.Close.Glyph.vertexColor[4]==1)
head.Close.scripts.OnLeave()
assert(head.Close.Glyph.vertexColor[4]==0.75)
checkStopLayout()
WV:StopTalkingHead()
for _,preset in ipairs({'classic','ellesmere','retail'}) do
    WV:SetHeadPreset(preset)
    WV:ToggleHeadPreview()
    assert(head.Name.fontObject=='QuestTitleFont' and head.Body.fontObject=='QuestFont')
    for _, pair in ipairs({{head.Name,'QuestTitleFont'},{head.Body,'QuestFont'}}) do
        local reference=head:CreateFontString(nil,'OVERLAY',pair[2])
        local file,size,flags=reference:GetFont()
        local actualFile,actualSize,actualFlags=pair[1]:GetFont()
        assert(actualFile==file and actualSize==size and actualFlags==flags,
            'all styles must match native quest font families, sizes and flags')
    end
    assert(head.TextMeasure.fontFile==head.Body.fontFile and head.TextMeasure.fontSize==head.Body.fontSize,
        'scroll measurement must use the displayed quest font')
    assert(head.TextScroll.height%head.Body.fontSize==0,'only whole quest-font lines should be visible')
    checkStopLayout()
    assert(head.Close.Glyph.visible==(preset=='ellesmere'))
    assert(head.Close.Stock.visible==(preset~='ellesmere'))
    head.Close.scripts.OnEnter()
    head.Close.scripts.OnMouseDown()
    assert(head.Close.Highlight.visible==(preset~='ellesmere'))
    assert(head.Close.Highlight.blendMode=='ADD','stock hover glow must not cover the cross with black pixels')
    assert(head.Close.Stock.visible==(preset~='ellesmere'))
    head.Close.scripts.OnMouseUp()
    head.Close.scripts.OnLeave()
    assert(not head.Close.Highlight.visible)
    head.Close.scripts.OnClick()
    assert(not head.visible and #plays==0 and #stops==0,'every close ends silent preview')
end
print('PASS: Retail composition, portrait ornament, wrapped title, item fallback, close control and theme cleanup')

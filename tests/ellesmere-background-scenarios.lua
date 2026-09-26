local WV=WowVoice
WV:SetHeadPreset('ellesmere')
WV:ToggleHeadPreview()
local head=frames.WowVoiceTalkingHead
local function tick()
    now=now+1
    head.scripts.OnUpdate()
end
local function fallback()
    assert(not head.EllesmereBackground.visible and not head.EllesmereShade.visible)
    assert(head.Background.backdropColor[1]==0.06 and head.Background.backdropColor[4]==0.95)
end
fallback()
local sounds, stopped=#plays,#stops
local style, color='modern',{0.2,0.3,0.4,0.6}
local reads=0
local skin={
    GetStyle=function(key) assert(key=='tp:WowVoice'); reads=reads+1; return style end,
    GetModernBG=function() return color[1],color[2],color[3],color[4] end,
}
-- The integration can load after the preview, without a reload or audio restart.
EllesmereUI={_ModuleNS={EllesmereUIBlizzardSkin={WSkin=skin}}}
tick()
assert(head.Background.backdropColor[1]==0.2 and head.Background.backdropColor[4]==0.6)
local previousReads=reads
head.scripts.OnUpdate()
assert(reads==previousReads,'do not inspect optional addon settings every frame')
color={0.5,0.6,0.7,0}
tick()
assert(head.Background.backdropColor[1]==0.5 and head.Background.backdropColor[4]==0,'zero opacity must be preserved')
style='eui'
tick()
assert(head.EllesmereBackground.visible and head.EllesmereShade.visible)
assert(head.Background.backdropColor[4]==0 and head.EllesmereShade.color[4]==0.62)
local uv=head.EllesmereBackground.texCoord
assert(uv[1]==0.25 and uv[2]==1 and uv[3]>0 and uv[4]<0.75,'wide window crops the atlas vertically')
assert(WV:ApplyHeadSettings({width=360,height=600,scale=1,x=0,y=0,enabled=true}))
uv=head.EllesmereBackground.texCoord
assert(uv[1]>0.25 and uv[2]<1 and uv[3]==0 and uv[4]==0.75,'tall window crops horizontally')
WV:SetHeadPreset('ellesmere')
missingTexture=head.EllesmereBackground.texture
tick()
style='off'; tick(); fallback()
style='eui'; tick(); fallback()
missingTexture=nil
tick()
assert(head.EllesmereBackground.visible,'a previously missing texture can recover')
for _,preset in ipairs({'classic','retail'}) do
    WV:SetHeadPreset(preset)
    tick()
    assert(not head.EllesmereBackground.visible and not head.EllesmereShade.visible)
end
WV:SetHeadPreset('ellesmere')
style='modern'
for _,bad in ipairs({{0.1,0.2,0.3}, {0.1,0.2,0.3,2}, {'bad',0,0,1}, {0/0,0,0,1}}) do
    color=bad; tick(); fallback()
end
skin.GetStyle=function() error('incompatible optional addon') end
tick(); fallback()
skin.GetStyle=function() return 'modern' end
skin.GetModernBG=function() error('unavailable color') end
tick(); fallback()
EUI_CLIENT_BLOCKED=true
tick(); fallback()
EUI_CLIENT_BLOCKED=nil
EllesmereUI=nil
tick(); fallback()
assert(head.visible and head.mouseEnabled and #plays==sounds and #stops==stopped)
WV:HideHeadPreview()
print('PASS: Ellesmere background sync, live changes, late load, opacity, atlas crop, missing media/API and invalid-data fallback')

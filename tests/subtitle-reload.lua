event('ADDON_LOADED')
event('PLAYER_LOGIN')
assert(questCache()[179].description==savedSubtitle)
assert(WowVoice:ReplayQuest(179))
local head=frames.WowVoiceTalkingHead
assert(head.Body.text==savedSubtitle and head.TextScroll.scroll==0)
local anchor=frames.WowVoiceTalkingHeadAnchor
assert(anchor.points[1][1]=='CENTER' and anchor.points[1][4]==0 and anchor.points[1][5]==-250)
assert(head.width==500 and head.height==140 and head.scale==1)
assert(head.RetailBackground.visible and head.PortraitOverlay.visible)
WowVoice:Silence()
print('PASS: saved description, dimensions and exact position survive simulated reload')

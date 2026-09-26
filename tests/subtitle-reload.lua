event('ADDON_LOADED')
event('PLAYER_LOGIN')
assert(questCache()[179].description==savedSubtitle)
assert(WowVoice:ReplayQuest(179))
local head=frames.WowVoiceTalkingHead
assert(head.Body.text==savedSubtitle and head.TextScroll.scroll==0)
local anchor=frames.WowVoiceTalkingHeadAnchor
assert(anchor.points[1][1]=='CENTER' and anchor.points[1][4]==0 and anchor.points[1][5]==-250)
assert(head.width==570 and head.height==155 and head.scale==1)
assert(WowVoice:GetHeadPreset()=='classic')
assert(head.Background.backdrop.bgFile=='Interface\\DialogFrame\\UI-DialogBox-Background')
WowVoice:Silence()
print('PASS: saved description, preset and exact position survive simulated reload')

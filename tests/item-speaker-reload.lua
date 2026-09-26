event('ADDON_LOADED'); event('PLAYER_LOGIN')
C_Container=nil
assert(questCache()[179].itemID==10621)
assert(WowVoice:ReplayQuest(179))
local h=frames.WowVoiceTalkingHead
assert(h.Name.text=='Свиток с рунами' and h.Icon.texture==134939 and h.Icon.visible)
assert(h.Model.alpha==0 and h.Body.text==GetQuestText())
WowVoice:Silence(); restored('1','0.37')
print('PASS: item ID, name, icon and description survive addon recreation; replay needs no bag API')
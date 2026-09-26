event('ADDON_LOADED')
event('PLAYER_LOGIN')
assert(questCache()[179].displayID==savedBeforeReload)
assert(WowVoice:ReplayQuest(179))
local head=frames.WowVoiceTalkingHead
assert(head.visible and head.Model.displayID==savedBeforeReload)
WowVoice:Silence()
print('PASS: saved appearance survives recreation of all addon frames/state and replays after simulated reload')

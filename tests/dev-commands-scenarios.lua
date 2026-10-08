event('ADDON_LOADED')
local WV = WowVoice
local calls = {}
WV.Playback.Play = function(_, path, duration) calls[#calls+1] = {path, duration} end
WV.Playback.Stop = function(_, reason) calls[#calls+1] = reason end
command('test 179')
assert(calls[1][1] == WV:SoundPath(179, 'a') and calls[1][2] == WowVoiceDur['179a'])
command('stoptest')
assert(calls[2][1] == WV:SoundPath(179, 'a') and calls[2][2] == 60)
local stopDriver = allFrames[#allFrames]
stopDriver.scripts.OnUpdate(stopDriver, 3.1)
assert(calls[3] == 'stoptest')
local reminderID
WV.TestQuestReminder = function(_, id) reminderID = id end
command('remindertest 179'); assert(reminderID == 179)
command('remindertest off'); assert(reminderID == false)
command('debug on'); assert(TalkingHeadRuDB.debug)
command('debug off'); assert(not TalkingHeadRuDB.debug)
assert(SLASH_WOWVOICELOCALDEBUG2 == '/wvdebug')
local opened = 0
WV.OpenOptions = function() opened = opened + 1 end
command('options'); assert(opened == 1, 'The local wrapper must delegate public commands')
print('PASS: local developer commands retain test, delayed stop, reminder, debug and public command delegation')

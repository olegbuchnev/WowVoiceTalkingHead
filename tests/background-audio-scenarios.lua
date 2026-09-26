event('ADDON_LOADED')
local WV = WowVoice
local music, musicStops, musicOK = {}, 0, true
function PlayMusic(file)
    music[#music+1] = {file=file, enabled=cvars.Sound_EnableMusic,
        volume=cvars.Sound_MusicVolume, dialog=cvars.Sound_EnableDialog,
        dialogVolume=cvars.Sound_DialogVolume}
    return musicOK
end
function StopMusic() musicStops=musicStops+1 end
local setCVar = SetCVar
function SetCVar(key, value)
    assert(key~='Sound_EnableSoundWhenGameIsInBG', 'addon must never override background sound')
    setCVar(key,value)
end
local function settings(enabled, volume)
    assert(cvars.Sound_EnableMusic==enabled and cvars.Sound_MusicVolume==volume,
        'original music settings must be restored')
    restored('1','0.37')
end
local _, duration = WV:SoundPath(179,'a')
assert(WowVoiceDB.channel=='auto')

-- Music starts even when the user disabled it or set its volume to zero.
-- A replacement keeps the original settings; finish/close/logout restore them.
for _, enabled in ipairs({'0','1'}) do
    for _, ending in ipairs({'timer','close','logout'}) do
        cvars.Sound_EnableSoundWhenGameIsInBG='0'
        cvars.Sound_EnableMusic,cvars.Sound_MusicVolume=enabled,'0'
        local before=#plays
        assert(WV:ReplayQuest(179))
        local first=music[#music]
        assert(first.file==WV:SoundPath(179,'a') and first.enabled=='1' and first.volume=='1.0')
        assert(first.dialog=='0' and first.dialogVolume=='0')
        assert(#plays==before, 'background-off selects Music')
        tick(now+2)
        assert(WV:ReplayQuest(179))
        if ending=='timer' then tick(now+duration+0.051)
        elseif ending=='close' then WV:Silence()
        else event('PLAYER_LOGOUT') end
        settings(enabled,'0')
    end
end

-- Changing the preference never restarts the current recording. The next
-- recording switches channels, with no leftover Master handle or music stream.
cvars.Sound_EnableMusic,cvars.Sound_MusicVolume='0','0.42'
cvars.Sound_EnableSoundWhenGameIsInBG='1'
assert(WV:ReplayQuest(179))
local master=plays[#plays]
assert(master.channel=='Master' and master.dialog=='0')
assert(cvars.Sound_EnableMusic=='0' and cvars.Sound_MusicVolume=='0.42')
local count,musicCount,stopCount=#plays,#music,#stops
cvars.Sound_EnableSoundWhenGameIsInBG='0'
tick(now+1)
assert(#plays==count and #music==musicCount and #stops==stopCount)
assert(WV:ReplayQuest(179))
assert(stops[#stops]==master.handle and #music==musicCount+1)
count,musicCount=#plays,#music
cvars.Sound_EnableSoundWhenGameIsInBG='1'
tick(now+1)
assert(#plays==count and #music==musicCount)
local beforeMusicStop=musicStops
assert(WV:ReplayQuest(179))
assert(#plays==count+1 and musicStops==beforeMusicStop+1)
assert(cvars.Sound_EnableMusic=='0' and cvars.Sound_MusicVolume=='0.42')
WV:Silence()
settings('0','0.42')

-- Explicit overrides remain available. Existing duck opt-out is independent.
command('channel music')
WowVoiceDB.ducknpc=false
assert(WV:ReplayQuest(179))
assert(music[#music].dialog=='1' and music[#music].dialogVolume=='0.37')
WV:Silence()
settings('0','0.42')
WowVoiceDB.ducknpc=true
command('channel sound')
cvars.Sound_EnableSoundWhenGameIsInBG='0'
count=#plays
assert(WV:ReplayQuest(179) and #plays==count+1)
WV:Silence()
command('channel auto')

-- Explicit PlayMusic failure restores both channels and does not mark heard.
musicOK=false
assert(not WV:ReplayQuest(192))
settings('0','0.42')
assert(not WV:HasQuestAudio(192))
assert(not WowVoiceDB.listenedQuests[playerGUID][192])
assert(not frames.WowVoiceTicker.visible)
musicOK=true
assert(WV:ReplayQuest(179))
musicOK=false
assert(not WV:ReplayQuest(179))
settings('0','0.42')
assert(not frames.WowVoiceTicker.visible)
musicOK=true
WV:SetQuestAudioAvailable(179,true)

-- The legacy cvar stop's delayed callback must neither re-enable music after
-- stopping, nor disable a new recording that began during its delay.
command('stopmode cvar')
assert(WV:ReplayQuest(179))
WV:Silence()
tick(now+0.3)
settings('0','0.42')
assert(WV:ReplayQuest(179))
WV:Silence()
assert(WV:ReplayQuest(179))
tick(now+0.3)
assert(cvars.Sound_EnableMusic=='1')
WV:Silence()
tick(now+0.3)
settings('0','0.42')
command('stopmode silence')

-- Older PlayMusic implementations return no status; nil is not failure.
musicOK=nil
assert(WV:ReplayQuest(179))
WV:Silence()
settings('0','0.42')
print('PASS: automatic background routing, per-line selection, both channel transitions, NPC ducking, explicit overrides, music restoration and failure cleanup')

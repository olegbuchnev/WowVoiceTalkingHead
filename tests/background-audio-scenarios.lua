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
assert(TalkingHeadRuDB.channel=='auto')

-- Music starts even when the user disabled it or set its volume to zero.
-- A replacement keeps the original settings; finish/close/logout restore them.
for _, enabled in ipairs({'0','1'}) do
    for _, ending in ipairs({'timer','close','logout'}) do
        cvars.Sound_EnableSoundWhenGameIsInBG='0'
        cvars.Sound_EnableMusic,cvars.Sound_MusicVolume=enabled,'0'
        local before=#plays
        assert(WV:ReplayQuest(179))
        local first=music[#music]
        assert(first.file==WV:SoundPath(179,'a') and first.enabled=='1' and tonumber(first.volume)==0.37)
        assert(first.dialog=='0' and first.dialogVolume=='0')
        assert(#plays==before, 'background-off selects Music')
        tick(now+2)
        assert(WV:ReplayQuest(179))
        if ending=='timer' then tick(now+duration+0.051)
        elseif ending=='close' then WV:Silence()
        else event('PLAYER_LOGOUT') end
        assert(music[#music].file == 'Interface\\AddOns\\TalkingHeadRu\\Media\\silence.ogg',
            'all Music stop paths must use our bundled silence, never an external voice-pack file')
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
TalkingHeadRuDB.ducknpc=false
assert(WV:ReplayQuest(179))
assert(music[#music].dialog=='1' and music[#music].dialogVolume=='0.37')
WV:Silence()
settings('0','0.42')
TalkingHeadRuDB.ducknpc=true
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
assert(not TalkingHeadRuDB.listenedQuests[playerGUID][192])
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

-- Both transports use the original Dialog slider. Master must multiply,
-- never replace the user's Master value, and repeated lines must not compound.
local function near(key, expected)
    assert(math.abs(tonumber(cvars[key])-expected)<0.000001, key..' expected '..expected..', got '..tostring(cvars[key]))
end
musicOK=true
for _, background in ipairs({'0','1'}) do
    for _, masterVolume in ipairs({'0','0.2','0.5','1'}) do
        for _, dialogVolume in ipairs({'0','0.3','1'}) do
            for _, ending in ipairs({'timer','close','logout','failure'}) do
                cvars.Sound_EnableSoundWhenGameIsInBG=background
                cvars.Sound_MasterVolume=masterVolume
                cvars.Sound_DialogVolume=dialogVolume
                cvars.Sound_EnableMusic,cvars.Sound_MusicVolume='0','0.42'
                for line=1,3 do
                    assert(WV:ReplayQuest(179))
                    near('Sound_MasterVolume', tonumber(masterVolume)*(background=='1' and tonumber(dialogVolume) or 1))
                    near('Sound_MusicVolume', background=='1' and 0.42 or tonumber(dialogVolume))
                    assert(cvars.Sound_EnableMusic==(background=='1' and '0' or '1'))
                end
                if ending=='timer' then tick(now+duration+0.051)
                elseif ending=='close' then WV:Silence()
                elseif ending=='logout' then event('PLAYER_LOGOUT')
                else
                    soundOK,musicOK=false,false
                    assert(not WV:ReplayQuest(179))
                    soundOK,musicOK=true,true
                    WV:SetQuestAudioAvailable(179,true)
                end
                assert(cvars.Sound_MasterVolume==masterVolume)
                assert(cvars.Sound_DialogVolume==dialogVolume)
                assert(cvars.Sound_MusicVolume=='0.42' and cvars.Sound_EnableMusic=='0')
            end
        end
    end
end

-- Mid-line manual adjustments survive close and also survive a replacement.
-- Only settings still carrying the addon's value are restored.
for _, background in ipairs({'0','1'}) do
    for _, replace in ipairs({false,true}) do
        cvars.Sound_EnableSoundWhenGameIsInBG=background
        cvars.Sound_MasterVolume,cvars.Sound_DialogVolume='0.5','0.3'
        cvars.Sound_EnableMusic,cvars.Sound_MusicVolume='1','0.42'
        assert(WV:ReplayQuest(179))
        SetCVar('Sound_MasterVolume','0.7')
        SetCVar('Sound_MusicVolume','0.6')
        SetCVar('Sound_EnableMusic','0')
        SetCVar('Sound_DialogVolume','0.4')
        SetCVar('Sound_EnableDialog','1')
        if replace then
            assert(WV:ReplayQuest(179))
            near('Sound_MasterVolume',background=='1' and 0.28 or 0.7)
            near('Sound_MusicVolume',background=='1' and 0.6 or 0.4)
        end
        WV:Silence()
        assert(cvars.Sound_MasterVolume=='0.7' and cvars.Sound_MusicVolume=='0.6')
        assert(cvars.Sound_EnableMusic=='0')
        restored('1','0.4')
    end
end

-- Legacy delayed restoration must not undo settings changed after stopping.
command('stopmode cvar')
cvars.Sound_EnableSoundWhenGameIsInBG='0'
assert(WV:ReplayQuest(179))
WV:Silence()
SetCVar('Sound_EnableMusic','1')
tick(now+0.3)
assert(cvars.Sound_EnableMusic=='1')
command('stopmode silence')

-- Explicit relative attenuation works the same way in either transport,
-- and opting out of NPC suppression does not bypass Dialog volume matching.
TalkingHeadRuDB.ducknpc=false
command('volume 0.5')
for _, background in ipairs({'0','1'}) do
    cvars.Sound_EnableSoundWhenGameIsInBG=background
    cvars.Sound_MasterVolume,cvars.Sound_DialogVolume='0.5','0.3'
    assert(WV:ReplayQuest(179))
    near('Sound_MasterVolume',background=='1' and 0.075 or 0.5)
    if background=='0' then near('Sound_MusicVolume',0.15) end
    restored('1','0.3')
    WV:Silence()
end
print('PASS: Dialog-relative Master/Music volume, zero and low sliders, consecutive playback, all stop/failure paths, manual settings and multiplier')

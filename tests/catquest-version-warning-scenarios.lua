local WV, S = WowVoice, WowVoiceAudioSources
local mode = catquestWarningTestMode
local older = mode == 'old-login' or mode == 'old-late'
local loaded = mode ~= 'absent' and mode ~= 'old-late'
local version = older and '0.2.2' or mode == 'newer' and '0.5.0'
    or mode == 'double-digit' and '0.10.0' or mode == 'unknown' and 'nightly' or WowVoiceCatQuestAudio.sourceVersion
if mode == 'missing' then version = nil end
local metadata, isLoaded = C_AddOns.GetAddOnMetadata, C_AddOns.IsAddOnLoaded
C_AddOns.GetAddOnMetadata = function(name, field)
    if name == 'CatQuest_Voices' and field == 'Version' then return version end
    return metadata and metadata(name, field)
end
C_AddOns.IsAddOnLoaded = function(name)
    if name == 'CatQuest_Voices' then return loaded end
    return isLoaded(name)
end
local function notices()
    local count = 0
    for _, text in ipairs(messages) do
        if text:find('Обновите CatQuest Voices до версии ', 1, true) then count = count + 1 end
    end
    return count
end
event('ADDON_LOADED')
WV:RefreshAudioSources()
assert(notices() == 0, 'version recommendations belong only in the options tooltip')
local sounds, stopped = #plays, #stops
event('PLAYER_LOGIN')
if mode == 'old-late' then
    assert(notices() == 0, 'an absent optional pack must not produce an update notice')
    loaded = true
    frames.WowVoiceFrame.scripts.OnEvent(frames.WowVoiceFrame, 'ADDON_LOADED', 'CatQuest_Voices')
end
assert(notices() == 0, 'library versions must not produce a chat notice: '..mode)
if older then
    assert(S.Status().updated and S.Status().outdated)
    assert(WV:SetSharedQuestVoice('catquest'))
    assert(S.Resolve(99162, 'a') and WV:HasQuestAudio(99162), 'compatible recordings remain usable')
elseif loaded then assert(not S.Status().outdated) end
WV:OpenOptions()
local warning = frames.WowVoiceOptionsPanel.AudioSourceWarning
if older then
    assert(warning:IsShown() and warning.title == 'Устаревшая озвучка CatQuest')
    assert(warning.message:find('Обновите CatQuest Voices до версии ' .. WowVoiceCatQuestAudio.sourceVersion, 1, true))
    assert(not warning.message:find('Обновление WowVoice TalkingHead', 1, true))
elseif mode == 'newer' or mode == 'double-digit' then
    assert(warning:IsShown() and warning.message:find('Обновление WowVoice TalkingHead', 1, true))
    assert(warning.message:find('включая новые и изменённые записи', 1, true))
    assert(warning.message:find('Голова и очередь могут завершаться позже звука', 1, true))
elseif mode == 'current' or mode == 'absent' then
    assert(not warning:IsShown())
elseif mode == 'missing' or mode == 'unknown' then
    assert(warning:IsShown() and warning.title == 'Непроверенная озвучка CatQuest')
end
for _ = 1, 3 do
    WV:RefreshAudioSources()
    event('PLAYER_LOGIN')
    frames.WowVoiceFrame.scripts.OnEvent(frames.WowVoiceFrame, 'ADDON_LOADED', 'CatQuest_Voices')
end
assert(notices() == 0, 'refresh, settings and load events must not produce chat notices')
assert(#plays == sounds and #stops == stopped, 'the version notice must not start or stop audio')
if older then assert(WV:GetSharedQuestVoice() == 'catquest') end
print('PASS: CatQuest Voices version tooltip: '..mode..', correct update target, no chat notices and unchanged playback')

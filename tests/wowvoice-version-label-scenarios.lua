local WV = WowVoice
local originalMetadata = C_AddOns.GetAddOnMetadata
local originalLoaded = C_AddOns.IsAddOnLoaded
local pack = {Version='0.1.0', Title='WowVoice Sounds'}
local packLoaded, playerInstalled = true, true
local playerVersion = '1.0.2'
C_AddOns.GetAddOnMetadata = function(name, key)
    if name == 'WowVoiceSounds' then return pack and pack[key] end
    if name == 'WowVoice' then
        return playerInstalled and key == 'Version' and playerVersion or nil
    end
    return originalMetadata(name, key)
end
C_AddOns.IsAddOnLoaded = function(name)
    if name == 'WowVoice' then return false end
    if name == 'WowVoiceSounds' then return packLoaded end
    return originalLoaded(name)
end
event('ADDON_LOADED')
command('options')
local panel = frames.WowVoiceOptionsPanel
local label = panel.VersionLabels.WowVoiceSounds
assert(label:GetText() == '1.0.2', 'read the real upstream TOC version even with its player disabled')
playerVersion = '1.0.3'
panel:Hide()
panel:Show()
assert(label:GetText() == '1.0.3', 'new upstream versions must display without a mapping update')
packLoaded = false
WV:RefreshAudioSources()
assert(label:GetText() == '1.0.3', 'disabling the installed sound pack does not change its release label')
packLoaded = true
pack.Version = '0.2.0'
WV:RefreshAudioSources()
assert(label:GetText() == '1.0.3', 'display the addon version, not the internal sound-pack version')
playerInstalled = false
WV:RefreshAudioSources()
assert(label:GetText() == 'версия не указана', 'do not invent an addon version when only sounds are installed')
assert(WV:ReplayQuest(179), 'standalone sounds must work without the upstream addon or its version')
WV:Silence()
pack.Version = '1.0.3-forever.1'
WV:RefreshAudioSources()
assert(label:GetText() == '1.0.1', 'keep the legacy bundled source label')
pack['X-Source-Version'] = '1.0.4'
WV:RefreshAudioSources()
assert(label:GetText() == '1.0.4', 'explicit source metadata remains supported')
pack = {Title='WowVoice Sounds'}
WV:RefreshAudioSources()
assert(label:GetText() == 'версия не указана')
pack, packLoaded = nil, false
playerInstalled = true
WV:RefreshAudioSources()
assert(label:GetText() == 'не установлен', 'the upstream player alone must not masquerade as an installed sound library')
assert(panel.VersionLabels.AudioSource:GetText() == WowVoiceCatQuestAudio.sourceVersion, 'CatQuest keeps its own version')
print('PASS: real WowVoice TOC version with disabled player, automatic updates, standalone/absent sounds, legacy metadata and independent playback')

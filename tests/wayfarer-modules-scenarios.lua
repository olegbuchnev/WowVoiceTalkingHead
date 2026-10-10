event('ADDON_LOADED')
local WV, W, C = WowVoice, WowVoiceWayfarerSource, WowVoiceComparison
local names = {'Wayfarer_Voices_Alliance', 'Wayfarer_Voices_Horde', 'Wayfarer_Voices_Shared'}
local loaded = {Wayfarer=true}
C_AddOns.IsAddOnLoaded = function(name) return loaded[name] == true end
C_AddOns.GetAddOnMetadata = function() return '3.1.0' end
Wayfarer = {Packs={list={}}}
WowVoiceWayfarerAudio = {schemaVersion=1,packs={}}
for index, name in ipairs(names) do
    Wayfarer.Packs.list[index] = {name=name,format=1,model='v4',q={
        [99000+index]={a={d=3}}, [99010]={a={d=4}}, [99020+index]={c={d=2}},
    }}
    WowVoiceWayfarerAudio.packs[name] = {entries={
        [tostring(99000+index)..'a']={}, ['99010a']={}, [tostring(99020+index)..'c']={},
    }}
end
WV:SetVoicePriority({'wowvoice','catquest','wayfarer'})
WV:OpenOptions()
frames.WowVoiceOptionsPanel:SetSize(620, 640)
WV:OpenVoiceComparison('990')
local options, catalogue = frames.WowVoiceOptionsPanel, frames.WowVoiceLocalDebugPanel
local function tile(id)
    catalogue.QuestID:SetText(tostring(id))
    for _, row in ipairs(catalogue.Suggestions.Rows) do
        if row.questID == id then return row.PlayButtons.wayfarer end
    end
    error('Missing Wayfarer catalogue entry: '..id)
end
local function warningRow()
    for _, row in ipairs(options.VoicePriorityRows) do
        if row.sourceID == 'wayfarer' then return row end
    end
end
for mask = 0, 7 do
    local missingCount = 0
    for index, name in ipairs(names) do
        loaded[name] = math.floor(mask / 2^(index-1)) % 2 == 1
        if not loaded[name] then missingCount = missingCount + 1 end
    end
    WV:RefreshAudioSources()
    assert(#W.MissingPacks() == missingCount)
    local warning = warningRow()
    assert(warning.Warning.visible == (missingCount > 0))
    assert(warning.available == (mask > 0))
    if missingCount > 0 then
        warning.scripts.OnEnter(warning)
        assert(GameTooltip.visible and GameTooltip:IsOwned(warning))
        for _, name in ipairs(names) do
            assert((GameTooltip.lines[2]:find(name,1,true) ~= nil) == not loaded[name])
        end
        warning.scripts.OnLeave(warning)
        assert(not GameTooltip.visible)
    end
    for index, name in ipairs(names) do
        local id = 99000 + index
        assert(W.QuestIDs(true,true)[id] and C.Known(id,'wayfarer'))
        assert((W.QuestIDs(false,true)[id] == true) == loaded[name])
        assert(W.PacksForQuest(id,'a')[1] == name)
        local recording = C.Resolve(id,'wayfarer')
        assert((recording ~= nil) == loaded[name])
        if recording then assert(recording.packName == name and recording.path:find(name,1,true)) end
        local button = tile(id)
        assert(button.motionWhileDisabled, 'Unavailable recordings still explain their module on hover')
        assert(button:IsShown() and button:IsEnabled() == loaded[name])
        assert(button.UnavailableMark.visible == not loaded[name])
        button.scripts.OnEnter(button)
        assert(GameTooltip.visible and GameTooltip.lines[2]:find(name,1,true))
        button.scripts.OnLeave(button)
        if not loaded[name] then
            local before = #plays
            button.scripts.OnClick(button)
            assert(#plays == before, 'Missing modules must be disabled before playback is attempted')
        end
        assert(not W.QuestIDs(true,true)[99020+index], 'Completion-only quests are not descriptions')
    end
    assert(tile(99010):IsEnabled() == (mask > 0), 'Any loaded copy makes a shared recording available')
end
-- Source-specific replacement: an update removes/adds only its own records.
loaded[names[2]] = false
Wayfarer.Packs.list[1].q[99001] = nil
Wayfarer.Packs.list[1].q[99099] = {a={d=3}}
WV:RefreshAudioSources()
assert(not W.Known(99001) and not W.QuestIDs(true,true)[99001])
assert(W.Known(99002) and W.QuestIDs(true,true)[99002] and not W.Resolve(99002,'a'))
assert(W.Known(99099) and C.Resolve(99099,'wayfarer').packName == names[1])
-- Stale registries cannot make failed or incompatible packs playable.
C_AddOns.DoesAddOnHaveLoadError = function(name) return name == names[3] end
WV:RefreshAudioSources()
assert(not tile(99003):IsEnabled() and #W.MissingPacks() == 2)
C_AddOns.DoesAddOnHaveLoadError = nil
Wayfarer.Packs.list[3].format = 2
WV:RefreshAudioSources()
assert(not tile(99003):IsEnabled() and #W.MissingPacks() == 2)
Wayfarer.Packs.list[3].format = 1
loaded.Wayfarer = false
WV:RefreshAudioSources()
assert(#W.MissingPacks() == 3 and not tile(99003):IsEnabled())
loaded.Wayfarer = true
WV:RefreshAudioSources()
assert(tile(99003):IsEnabled(), 'Late loads must refresh an already-open catalogue')
WV:SetVoicePriority({'wayfarer','catquest','wowvoice'})
assert(options.VoicePriorityRows[1].Warning.visible and not options.VoicePriorityRows[3].Warning.visible,
    'Warning follows the Wayfarer card when priorities change')
print('Wayfarer module availability, provenance and catalogue scenarios passed')

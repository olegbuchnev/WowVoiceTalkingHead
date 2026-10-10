local WV, W = WowVoice, WowVoiceWayfarerSource
local oldMetadata, oldLoaded = C_AddOns.GetAddOnMetadata, C_AddOns.IsAddOnLoaded
local oldWayfarer, oldAudio = Wayfarer, WowVoiceWayfarerAudio
local name = 'Wayfarer_Voices_Alliance'
local installed, loaded = {}, {}
local versions = {Wayfarer='0.7.0', [name]='3.1.0'}
C_AddOns.GetAddOnMetadata = function(addon, field)
    if addon:match('^Wayfarer') then
        if not installed[addon] then return nil end
        if field == 'Title' then return addon end
        if field == 'Version' then return versions[addon] end
        return nil
    end
    return oldMetadata and oldMetadata(addon,field)
end
C_AddOns.IsAddOnLoaded = function(addon)
    if addon:match('^Wayfarer') then return loaded[addon] == true end
    return oldLoaded(addon)
end
local pack = {name=name,format=1,version='3.1.0',model='v4',q={[179]={a={d=3}}}}
Wayfarer = {Packs={list={pack}}}
WowVoiceWayfarerAudio = {schemaVersion=1,packs={[name]={version='3.1.0',model='v4',entries={
    ['179a']={voice='',speaker=0,audio={d={file='q/179-a.ogg',duration=3.123,indexDuration=3}}}
}}}}
event('ADDON_LOADED'); WV:OpenOptions()
local panel = frames.WowVoiceOptionsPanel
local label, warning = panel.VersionLabels.Wayfarer, panel.WayfarerSourceWarning
assert(label:GetText() == 'не установлен' and not warning:IsShown())
installed.Wayfarer, installed[name], loaded.Wayfarer, loaded[name] = true,true,true,true
local messagesBefore, playsBefore, stopsBefore = #messages,#plays,#stops
local priority = table.concat(WV:GetVoicePriority(), ',')
local function refresh()
    WV:RefreshAudioSources()
    assert(#messages == messagesBefore and #plays == playsBefore and #stops == stopsBefore,
        'compatibility hints cannot print, start or stop audio')
    assert(table.concat(WV:GetVoicePriority(), ',') == priority)
end
refresh()
assert(label:GetText() == '0.7.0' and not warning:IsShown())
assert(W.Resolve(179,'a').verified)
versions.Wayfarer = '0.6.0'; refresh()
assert(warning:IsShown() and warning.title == 'Устаревшая версия Wayfarer')
assert(warning.message:find('Обновите Wayfarer до версии 0.7.0.',1,true))
assert(not warning.message:find('завершаться позже',1,true), 'core update alone cannot invalidate audio measurements')
for _, version in ipairs({'0.8.0','0.10.0','nightly',''}) do
    versions.Wayfarer = version; refresh()
    assert(warning:IsShown() and warning.title == 'Непроверенная версия Wayfarer')
    assert(warning.message:find('Обновление TalkingHead Ru',1,true))
    assert(W.Resolve(179,'a').verified)
end
versions.Wayfarer = nil; refresh()
assert(label:GetText() == 'версия не указана' and warning:IsShown())
versions.Wayfarer = '0.7.0'
versions[name], pack.version = '3.2.0', '3.2.0'; refresh()
assert(label:GetText() == '0.7.0' and warning:IsShown())
assert(warning.message:find(name .. ': установлена 3.2.0; проверена 3.1.0.',1,true))
assert(warning.message:find('завершаться позже звука',1,true))
assert(not W.Resolve(179,'a').verified and W.Resolve(179,'a').duration == 3.25)
versions[name], pack.version = '3.0.0', '3.0.0'; refresh()
assert(warning.message:find('Обновите ' .. name .. ' до версии 3.1.0.',1,true))
loaded[name] = false; refresh()
assert(not warning:IsShown(), 'disabled packs cannot cause a compatibility warning')
versions[name], pack.version, loaded[name] = '3.1.0', '3.1.0', true
local extra = 'Wayfarer_Voices_New'
installed[extra], loaded[extra], versions[extra] = true,true,'1.0.0'
pack.name = extra; refresh()
assert(warning.message:find(extra .. ': установлена 1.0.0; проверена нет данных.',1,true))
pack.name, loaded[extra] = name,false
refresh(); assert(not warning:IsShown() and warning.message == nil)
versions.Wayfarer = '0.8.0'
panel:Hide(); panel:Show()
assert(label:GetText() == '0.8.0' and warning:IsShown(), 'reopening must refresh the version')
loaded.Wayfarer = false; refresh()
assert(label:GetText() == '0.8.0' and not warning:IsShown(), 'installed version remains readable while disabled')
Wayfarer, WowVoiceWayfarerAudio = oldWayfarer, oldAudio
C_AddOns.GetAddOnMetadata, C_AddOns.IsAddOnLoaded = oldMetadata, oldLoaded
WV:RefreshAudioSources()
print('PASS: Wayfarer core/pack versions, older/newer/unknown/missing versions, partial/new/disabled packs, estimates, reopen and silent isolated warnings')

event('ADDON_LOADED')
local WV, S = WowVoice, WowVoiceAudioSources
local upstream = CatQuestVoicePack
local loaded = {CatVoices=true, CatQuest_Voices=true, WowVoiceSounds=true}
local auditedVersion = WowVoiceCatQuestAudio.sourceVersion
local version = auditedVersion
C_AddOns.IsAddOnLoaded = function(name) return loaded[name] == true end
C_AddOns.GetAddOnMetadata = function(name, field)
    if name == 'CatQuest_Voices' and field == 'Version' then return version end
end
local sex = 2
UnitSex = function() return sex end
local prefix = 'Interface\\AddOns\\CatQuest_Voices\\Sounds\\q\\'
-- Stale manually installed CatVoices and preferences must never affect selection.
WowVoiceCatVoicePack = {schemaVersion=1,sourceVersion='0.2.2',entries={['99162a']={file='99162.ogg',duration=1}}}
WowVoiceDB.audioSource = 'bundled'
event('ADDON_LOADED')
assert(WowVoiceDB.audioSource == nil and S.Status().id == 'catquest')
assert(WV:SoundPath(99162,'a') == prefix .. '99162.ogg')
assert(WV:SoundPath(179,'a'):find('WowVoiceSounds',1,true))
assert(S.QuestIDs()[99162])
for _, variant in ipairs({{2,'m',42.481708},{3,'f',38.629833}}) do
    sex = variant[1]
    local file, seconds = WV:SoundPath(98430,'a')
    assert(file == prefix .. '98430_' .. variant[2] .. '.ogg' and seconds == variant[3])
    assert(WV:ReplayQuest(98430))
    local handle = plays[#plays].handle
    tick(now + seconds - .1)
    assert(stops[#stops] ~= handle)
    tick(now + .1 + WowVoiceDB.tail + .01)
    assert(stops[#stops] == handle)
end
assert(WV:SoundPath(98430,'p') == nil and not WV:HasQuestAudio(99080))
local file, seconds = WV:SoundPath(99080,'c')
assert(file == prefix .. '99080_t_f.ogg' and seconds == 33.259542)
CatQuestVoicePack.quests[98430].d = 40
assert(WV:HasQuestAudio(98430) and S.Resolve(98430,'a').duration == 40.25)
assert(not S.Resolve(98430,'a').verified, 'a changed live record cannot inherit an exact snapshot timer')
CatQuestVoicePack.quests[98430].d = 42.5
CatQuestVoicePack.quests[99080] = {t={d=1}}
assert(WV:SoundPath(99080,'c') == prefix .. '99080_t.ogg')
assert(S.Resolve(99080,'c').duration == 1.25 and not S.Resolve(99080,'c').verified)
CatQuestVoicePack.quests[99080] = nil
version = '0.4.0'
assert(S.Status().updated and WV:HasQuestAudio(98430) and WV:HasQuestAudio(179))
assert(S.Resolve(98430, 'a').duration == 42.75, 'updated packs use the live maximum plus rounding/index-error allowance')
assert(S.Resolve(99080, 'c') == nil, 'JSON-only recovery is limited to its audited release')
version = auditedVersion
loaded.CatQuest_Voices = false
WV:Silence()
assert(S.Status() == nil and not WV:HasQuestAudio(99162))
local before = #plays
questID = 99162
WowVoiceDB.autoPlayAccept = true
event('QUEST_DETAIL'); event('QUEST_PROGRESS'); event('QUEST_COMPLETE')
assert(WV:ReplayQuest(99162))
assert(#plays == before and frames.WowVoiceTalkingHead:IsShown(), 'Absent audio keeps the silent presentation')
WV.questQueue:Clear()
messages = {}; event('PLAYER_LOGIN')
assert(not has('Не все звуковые паки'))
assert(WV:ReplayQuest(179))
WV:Silence()
loaded.CatQuest_Voices = true
local revision = WV.audioRevision
frames.WowVoiceFrame.scripts.OnEvent(frames.WowVoiceFrame,'ADDON_LOADED','CatQuest_Voices')
assert(WV.audioRevision > revision and WV:HasQuestAudio(99162))
soundOK = false
assert(not WV:ReplayQuest(99162) and not WV:HasQuestAudio(99162))
soundOK = true
WV:RefreshAudioSources()
-- Texts are retained in our addon, including sex variants and game-text priority.
C_QuestLog.GetLogIndexForQuestID = function() return nil end
GetQuestLogQuestText = function() error('No selected quest') end
for _, variant in ipairs({{2,'Приветствую, юный герой.'},{3,'Приветствую, юный героиня.'}}) do
    sex = variant[1]
    assert(WV:ReplayQuest(99108))
    assert(frames.WowVoiceTalkingHead.Body:GetText():find(variant[2],1,true))
    WV:Silence()
end
assert(S.Text(99108,'c'):find('героиня',1,true))
assert(S.Text(99108,'p') == nil and S.Text(nil,'a') == nil)
assert(S.Text(99080,'c') == nil)
WV:StartTalkingHead({questId=99108, section='a', text='Captured game text'},now+40,40)
assert(frames.WowVoiceTalkingHead.Body:GetText() == 'Captured game text')
WV:StopTalkingHead()
loaded.CatQuest_Voices = false; CatQuestVoicePack = nil
assert(S.Text(99108,'a'):find('героиня',1,true))
CatQuestVoicePack = upstream; loaded.CatQuest_Voices = true
command('options')
local panel = frames.WowVoiceOptionsPanel
assert(not panel.AudioStatus and not panel.Buttons.source_catquest and not panel.Buttons.source_bundled)
assert(panel.AudioSourceCaption:GetText() == 'Озвучка CatQuest:')
assert(panel.VersionLabels.AudioSource:GetText() == auditedVersion)
loaded.CatQuest_Voices = false; WV:RefreshAudioSources()
assert(panel.VersionLabels.AudioSource:GetText() == 'недоступна')
loaded.CatQuest_Voices = true; version = '0.4.0'
local colors
panel.VersionLabels.AudioSource.SetTextColor = function(self, ...) colors = {...} end
WV:RefreshAudioSources()
assert(S.Status().updated and panel.VersionLabels.AudioSource:GetText() == '0.4.0')
assert(colors[1] == 1 and colors[2] == .82)
local warning = panel.AudioSourceWarning
assert(warning:IsShown())
warning.scripts.OnEnter(warning)
assert(GameTooltip:IsOwned(warning) and GameTooltip.visible)
assert(GameTooltip.lines[1]:find('Непроверенная озвучка',1,true))
assert(GameTooltip.lines[2]:find('0.4.0',1,true) and GameTooltip.lines[2]:find(auditedVersion,1,true))
version = auditedVersion; WV:RefreshAudioSources()
assert(S.Status().id == 'catquest' and not warning:IsShown() and not GameTooltip.visible)
-- Saved preference applies to all normal playback, with stage-specific fallback.
assert(WV:GetSharedQuestVoice() == 'wowvoice')
local choices = panel.SharedVoiceButtons
for _, choice in pairs(choices) do
    assert(not choice.template and choice.Border.texture == 'Interface\\CHARACTERFRAME\\TempPortraitAlphaMask')
    assert(choice.Label.parent == choice and choice.Label.point[1] == 'LEFT' and choice.Label.point[5] == 0,
        'Radio captions must share the button vertical center and click target')
    assert(not choice.scripts.OnEnter and not choice.scripts.OnLeave, 'Radio choices must not own a tooltip')
end
assert(panel.SharedVoiceTooltip:GetWidth() == 22, 'Help tooltip must have a small explicit target')
choices.catquest.scripts.OnClick(choices.catquest)
assert(WV:GetSharedQuestVoice() == 'catquest' and choices.catquest:GetChecked())
assert(WV:SoundPath(179, 'a') == prefix .. '179.ogg')
assert(WV:SoundPath(179, 'c') == prefix .. '179_t.ogg')
assert(WV:ClassicSoundPath(179, 'a'):find('WowVoiceSounds', 1, true))
assert(WV:SoundPath(99162, 'a') == prefix .. '99162.ogg')
local classicOnly
for key in pairs(WowVoiceDur) do
    if key:match('a$') and not WowVoiceCatQuestAudio.entries[key] then classicOnly = tonumber(key:match('^(%d+)')); break end
end
assert(classicOnly and WV:SoundPath(classicOnly, 'a'):find('WowVoiceSounds', 1, true))
assert(WV:ReplayQuest(179) and plays[#plays].file == prefix .. '179.ogg')
local activeHandle, playCount = plays[#plays].handle, #plays
assert(WV:SetSharedQuestVoice('wowvoice'))
assert(#plays == playCount and stops[#stops] ~= activeHandle, 'preference switch interrupted current audio')
assert(WV:ReplayQuest(179) and plays[#plays].file:find('WowVoiceSounds', 1, true))
WV:Silence()
assert(WV:SetSharedQuestVoice('catquest'))
soundOK = false
assert(not WV:ReplayQuest(179) and not WV:HasQuestAudio(179))
soundOK = true
WV:SetSharedQuestVoice('wowvoice')
assert(WV:HasQuestAudio(179), 'failed CatQuest audio poisoned WowVoice availability')
WV:SetSharedQuestVoice('catquest')
event('ADDON_LOADED')
assert(WV:GetSharedQuestVoice() == 'catquest', 'saved preference lost on initialization')
loaded.CatQuest_Voices = false; WV:RefreshAudioSources()
assert(not choices.catquest:IsEnabled() and not choices.wowvoice:IsEnabled())
assert(choices.wowvoice:GetChecked() and not choices.catquest:GetChecked())
assert(WowVoiceDB.sharedQuestVoice == 'wowvoice', 'Unavailable source must reset the saved preference')
assert(not WV:SetSharedQuestVoice('catquest'))
assert(WV:SoundPath(179, 'a'):find('WowVoiceSounds', 1, true))
local hint = panel.SharedVoiceTooltip
hint.scripts.OnEnter(hint)
assert(GameTooltip.visible and GameTooltip.lines[2]:find('установите', 1, true))
hint.scripts.OnLeave(hint)
loaded.CatQuest_Voices = true; version = '0.4.0'; WV:RefreshAudioSources()
assert(choices.catquest:IsEnabled() and WV:SoundPath(179, 'a'):find('WowVoiceSounds', 1, true))
assert(WV:SetSharedQuestVoice('catquest'))
WV:RefreshAudioSources()
assert(WV:GetSharedQuestVoice() == 'catquest', 'a newer library must not reset a saved source choice')
local savedQuests = CatQuestVoicePack.quests
CatQuestVoicePack.quests = false; WV:RefreshAudioSources()
assert(not S.Status() and not choices.catquest:IsEnabled() and warning:IsShown())
assert(colors[1] == 1 and colors[2] == .25)
assert(WV:GetSharedQuestVoice() == 'wowvoice', 'an invalid live index still falls back')
CatQuestVoicePack.quests = savedQuests
version = auditedVersion; WV:RefreshAudioSources()
assert(choices.catquest:IsEnabled() and choices.wowvoice:GetChecked())
assert(WV:GetSharedQuestVoice() == 'wowvoice', 'Restored library must not silently reselect CatQuest')
assert(WV:SetSharedQuestVoice('catquest'))
assert(WV:SoundPath(179, 'a') == prefix .. '179.ogg')
questID = 179; WV:Silence(); event('QUEST_DETAIL')
assert(plays[#plays].file == prefix .. '179.ogg')
WV:Silence(); event('QUEST_COMPLETE')
assert(plays[#plays].file == prefix .. '179_t.ogg')
WV:Silence(); WV:SetSharedQuestVoice('wowvoice')
-- Stale metadata/globals must not override absence or incomplete/failed loading.
local originalLoaded = C_AddOns.IsAddOnLoaded
local originalExists, originalError = C_AddOns.DoesAddOnExist, C_AddOns.DoesAddOnHaveLoadError
C_AddOns.DoesAddOnExist = function(name) return name ~= 'CatQuest_Voices' end
WowVoiceDB.sharedQuestVoice = 'catquest'
WV:RefreshAudioSources()
assert(CatQuestVoicePack.quests and originalLoaded('CatQuest_Voices'))
assert(not S.Status() and not choices.catquest:IsEnabled() and not WV:SetSharedQuestVoice('catquest'))
assert(WowVoiceDB.sharedQuestVoice == 'wowvoice' and choices.wowvoice:GetChecked())
assert(WV:SoundPath(179, 'a'):find('WowVoiceSounds', 1, true))
C_AddOns.DoesAddOnExist = function() return true end
C_AddOns.IsAddOnLoaded = function(name) return true, name ~= 'CatQuest_Voices' end
WV:RefreshAudioSources()
assert(not S.Status() and not choices.catquest:IsEnabled())
C_AddOns.IsAddOnLoaded = function() return true, true end
C_AddOns.DoesAddOnHaveLoadError = function(name) return name == 'CatQuest_Voices' end
WV:RefreshAudioSources()
assert(not S.Status() and not choices.catquest:IsEnabled())
C_AddOns.DoesAddOnExist, C_AddOns.DoesAddOnHaveLoadError = originalExists, originalError
C_AddOns.IsAddOnLoaded = originalLoaded
WV:RefreshAudioSources()
assert(S.Status() and choices.catquest:IsEnabled())
-- An options refresh alone must also show/save the fallback, without a full source refresh.
assert(WV:SetSharedQuestVoice('catquest'))
loaded.CatQuest_Voices = false
WV:RefreshAudioSourceOptions()
assert(WowVoiceDB.sharedQuestVoice == 'wowvoice' and choices.wowvoice:GetChecked())
loaded.CatQuest_Voices = true; WV:RefreshAudioSources()
print('PASS: external-only supplement, stale CatVoices ignored, silent head when absent, Classic independent, exact timings, text, compatibility and late loading')

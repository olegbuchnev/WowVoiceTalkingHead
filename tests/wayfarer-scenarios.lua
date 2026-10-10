event('ADDON_LOADED')
local S, W, C = WowVoiceAudioSources, WowVoiceWayfarerSource, WowVoiceComparison
local count = 0
for _ in pairs(W.QuestIDs(true, true)) do count = count + 1 end
assert(count == 3358 and not W.Status() and not W.Resolve(5, 'a'))
assert(C.Known(5, 'wayfarer') and not C.SourceAvailable('wayfarer'))
local name = 'Wayfarer_Voices_Alliance'
local pack = {name=name, format=1, version='3.1.0', model='v4', q={
    [179]={a={m=3,f=4,tm={{0,'Male text'}},tf={{0,'Female text'}}},p={d=2}},
    [99997]={a={d=2,t={{0,'Wayfarer only'}}}},
    [99998]={c={d=2}},
    [99996]={a={f=5,tf={{0,'Single variant'}}}},
}}
local loaded = {WowVoiceSounds=true, CatQuest_Voices=true, Wayfarer=true, [name]=true}
local version, sex = '3.1.0', 2
C_AddOns.IsAddOnLoaded = function(addon) return loaded[addon] == true end
C_AddOns.GetAddOnMetadata = function(addon, field)
    if field == 'Version' then return addon == name and version or WowVoiceCatQuestAudio.sourceVersion end
end
UnitSex = function() return sex end
Wayfarer = {Packs={list={pack}}, db={voiceModel='v4',enabled=true}}
WowVoiceWayfarerAudio = {schemaVersion=1,packs={[name]={version=version,model='v4',entries={
    ['179a']={voice='',speaker=0,audio={
        m={file='q/179-a-m.ogg',duration=3.123,indexDuration=3},
        f={file='q/179-a-f.ogg',duration=4.234,indexDuration=4}}}
}}}}
local record = W.Resolve(179,'a')
assert(record.verified and record.duration == 3.123 and record.path:find('179-a-m.ogg',1,true))
sex = 3; record = W.Resolve(179,'a')
assert(record.verified and record.duration == 4.234 and W.Text(179,'a') == 'Female text')
assert(S.Text(179,'a','wayfarer') == S.Text(179,'a'), 'voice selection cannot replace imported text')
sex = 2
assert(W.Resolve(99996,'a').variant == 'f')
assert(W.Resolve(179,'p') and not W.Resolve(179,'c') and not W.Resolve(-1,'a'))
assert(W.QuestIDs(false)[99998] and not W.QuestIDs(false,true)[99998])
assert(C.Known(99997,'wayfarer') and not C.Known(99998,'wayfarer'))
assert(not C.Known(5,'wayfarer'), 'Loaded index must replace the offline catalogue')
assert(S.QuestIDs()[99997] and C.QuestIDs()[99997])
assert(WowVoice:SetSharedQuestVoice('wayfarer'))
event('ADDON_LOADED')
assert(TalkingHeadRuDB.sharedQuestVoice == 'wayfarer')
assert(WowVoice:SoundPath(179,'a'):find(name,1,true))
assert(WowVoice:HasQuestAudio(99997) and not WowVoice:HasQuestAudio(99998))
assert(WowVoice:SoundPath(179,'c'):find('WowVoiceSounds',1,true), 'Stage fallback must use existing libraries')
assert(WowVoice:SetSharedQuestVoice('wowvoice'))
assert(C.Play(179,'wayfarer') and plays[#plays].file:find(name,1,true))
assert(WowVoice:GetSharedQuestVoice() == 'wowvoice', 'Preview must preserve preference')
WowVoice:Silence()
version='3.2.0'; record=W.Resolve(179,'a')
assert(not record.verified and record.duration == 3.25 and record.cues[1][2] == 'Male text')
version='3.1.0'; pack.q[179].a.m=8
assert(not W.Resolve(179,'a').verified and W.Resolve(179,'a').duration == 8.25)
pack.q[179].a.m=3; pack.format=2
assert(not W.Status() and not W.Resolve(179,'a'))
pack.format=1; loaded[name]=false
assert(not W.Status(), 'Stale registry must not count disabled packs')
loaded[name]=true; loaded.Wayfarer=false
assert(not W.Status(), 'Core dependency must be loaded')
loaded.Wayfarer=true; loaded.WowVoiceSounds=false; loaded.CatQuest_Voices=false
assert(WowVoice:GetSharedQuestVoice() == 'wayfarer' and WowVoice:ReplayQuest(99997))
WowVoice:Silence()
command('options')
local options = frames.WowVoiceOptionsPanel
assert(WowVoice:GetSharedQuestVoice() == 'wayfarer' and options.VoicePriorityRows[1].sourceID == 'wowvoice')
loaded.WowVoiceSounds=true; WowVoice:RefreshAudioSources()
for _, row in ipairs(options.VoicePriorityRows) do
    if row.sourceID == 'wayfarer' then assert(row.available) end
    if row.sourceID == 'catquest' then assert(not row.available) end
end
local registered = {QUEST_DETAIL=true,QUEST_PROGRESS=true,QUEST_COMPLETE=true,GOSSIP_SHOW=true}
local core = {}
function core:IsEventRegistered(event) return registered[event] end
function core:UnregisterEvent(event) registered[event]=nil end
function core:RegisterEvent(event) registered[event]=true end
Wayfarer.Core=core
WowVoice:UpdateCatQuestIntegration()
assert(not registered.QUEST_DETAIL and not registered.QUEST_PROGRESS and not registered.QUEST_COMPLETE)
assert(registered.GOSSIP_SHOW and Wayfarer.db.enabled)
command('off'); assert(registered.QUEST_DETAIL and registered.QUEST_COMPLETE)
command('on'); assert(not registered.QUEST_DETAIL)
event('PLAYER_LOGOUT'); assert(registered.QUEST_DETAIL and registered.QUEST_COMPLETE)
print('PASS: Wayfarer exact/estimated timing, genders, stages, offline/live catalog, preview, fallback, settings and reversible quest takeover')

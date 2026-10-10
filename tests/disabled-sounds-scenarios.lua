event('ADDON_LOADED')
local WV, S, Q = WowVoice, WowVoiceAudioSources, WowVoice.questQueue
local loaded = {WowVoiceSounds=true, CatQuest_Voices=true}
C_AddOns.IsAddOnLoaded = function(name) return loaded[name] == true end
TalkingHeadRuDB.sharedQuestVoice = 'wowvoice'
local prefix = 'Interface\\AddOns\\CatQuest_Voices\\Sounds\\q\\'
local classicOnly
for key in pairs(WowVoiceDur) do
    if key:match('a$') and not WowVoiceCatQuestAudio.entries[key] then
        classicOnly = tonumber(key:match('^(%d+)')); break
    end
end
assert(classicOnly and WV:HasQuestAudio(classicOnly))

-- Journal and tracker offer only available recordings.
QuestObjectiveTracker = CreateFrame('Frame', nil, UIParent)
local blocks, trackerButtons, journalButtons = {}, {}, {}
QuestScrollFrame = CreateFrame('Frame')
local rows = {}
for _, id in ipairs({179, classicOnly}) do
    local block = CreateFrame('Frame', nil, QuestObjectiveTracker)
    block.id = id
    block.HeaderText = block:CreateFontString(nil, 'ARTWORK', 'QuestTitleFont')
    blocks[id] = block
    local row = CreateFrame('Frame', nil, QuestScrollFrame)
    row.questID = id
    row.Checkbox = CreateFrame('Frame', nil, row)
    row.Checkbox:SetPoint('TOPRIGHT', row, 'TOPRIGHT', -4, -8)
    rows[#rows+1] = row
end
QuestObjectiveTracker.usedBlocks = {QuestTemplate=blocks}
function QuestObjectiveTracker:Update() end
function QuestObjectiveTracker:FreeBlock() end
QuestScrollFrame.titleFramePool = {EnumerateActive=function()
    local index = 0
    return function() index=index+1; return rows[index] end
end}
frames.WowVoiceTrackerEvents.scripts.OnEvent(frames.WowVoiceTrackerEvents, 'ADDON_LOADED')
WV:RefreshJournalButtons()
for _, frame in ipairs(allFrames) do
    for _, row in ipairs(rows) do
        if frame.questOwner == row then journalButtons[row.questID] = frame end
    end
    for id, block in pairs(blocks) do
        if frame.parent == block and frame.Icon then trackerButtons[id] = frame end
    end
end
assert(journalButtons[classicOnly]:IsShown() and trackerButtons[classicOnly]:IsShown())

loaded.WowVoiceSounds = false
CatQuestDB = {autoDetail=true, autoProgress=true, autoComplete=true, autoBooks=true, lore=true}
messages = {}
event('PLAYER_LOGIN')
assert(not has('Не загружена основная база'), 'CatQuest alone is a valid audio installation')
assert(WV:IsCatQuestAutoplaySuppressed() and CatQuestDB.autoBooks and CatQuestDB.lore)
assert(WV:GetSharedQuestVoice() == 'catquest' and TalkingHeadRuDB.sharedQuestVoice == 'wowvoice')
assert(not WV:SetSharedQuestVoice('wowvoice'), 'a disabled pack cannot be selected')
assert(WV:HasQuestAudio(179) and not WV:HasQuestAudio(classicOnly))
assert(journalButtons[179]:IsShown() and trackerButtons[179]:IsShown())
assert(not journalButtons[classicOnly]:IsShown() and not trackerButtons[classicOnly]:IsShown())
for _, section in ipairs({'a','p','c'}) do
    assert(WV:ClassicSoundPath(179, section) == nil)
    assert(WV:SoundPath(classicOnly, section) == nil)
end
assert(WV:SoundPath(179, 'a') == prefix .. '179.ogg')
assert(WV:SoundPath(179, 'c') == prefix .. '179_t.ogg')
assert(WV:SoundPath(179, 'p') == nil, 'missing CatQuest progress must not use disabled WowVoice')
assert(not WowVoiceComparison.Resolve(179, 'wowvoice'))
assert(WowVoiceComparison.Resolve(179, 'catquest'))

command('options')
local panel = frames.WowVoiceOptionsPanel
local function voiceRow(id)
    for _, row in ipairs(panel.VoicePriorityRows) do if row.sourceID == id then return row end end
end
assert(panel.VoicePriorityRows[1].sourceID == 'wowvoice')
assert(voiceRow('catquest').available and not voiceRow('wowvoice').available)
assert(voiceRow('wowvoice').unavailableMessage:find('WowVoiceSounds', 1, true))

local before = #plays
assert(not WV:ReplayQuest(classicOnly) and #plays == before and not frames.TalkingHeadRu:IsShown())
Q:Clear()
assert(WV:ReplayQuest(179) and plays[#plays].file == prefix .. '179.ogg')
assert(frames.TalkingHeadRu:IsShown())
Q:Clear()
questID = 179
event('QUEST_DETAIL')
assert(plays[#plays].file == prefix .. '179.ogg' and Q.current.context.questId == 179)
Q:Clear()
before = #plays
event('QUEST_PROGRESS')
assert(#plays == before and not Q.current and Q:Count() == 0)
Q:Clear()
event('QUEST_COMPLETE')
assert(plays[#plays].file == prefix .. '179_t.ogg')
Q:Clear()
before = #plays
questID = classicOnly
event('QUEST_DETAIL'); event('QUEST_PROGRESS'); event('QUEST_COMPLETE')
assert(#plays == before and not Q.current and not frames.TalkingHeadRu:IsShown())
Q:Clear()

-- Records queued before reload resolve their current source at playback time.
local unavailable = {context={questId=classicOnly, section='a', speaker={npcID=1}}}
local shared = {context={questId=179, section='a', speaker={npcID=658}}}
Q:Add(unavailable); Q:Add(shared)
assert(not Q:Start(unavailable) and unavailable.status == 'failed' and #plays == before)
assert(Q:Start(shared) and plays[#plays].file == prefix .. '179.ogg')
Q:Clear()

-- Background-off music playback and stopping cannot touch the disabled pack.
local music = {}
function PlayMusic(file)
    assert(not file:find('WowVoiceSounds', 1, true))
    music[#music+1] = file
    return true
end
local musicStops = 0
function StopMusic() musicStops = musicStops + 1 end
cvars.Sound_EnableSoundWhenGameIsInBG = '0'
cvars.Sound_EnableMusic, cvars.Sound_MusicVolume = '0', '0.42'
assert(WV:ReplayQuest(179) and music[#music] == prefix .. '179.ogg')
local _, duration = WV:SoundPath(179, 'a')
tick(now + duration + TalkingHeadRuDB.tail + 0.01)
assert(#music == 2 and music[2] == 'Interface\\AddOns\\TalkingHeadRu\\Media\\silence.ogg',
    'CatQuest-only playback must use the same bundled silence without changing stop mode')
assert(musicStops == 1 and cvars.Sound_EnableMusic == '0' and cvars.Sound_MusicVolume == '0.42')
Q:Clear()
tick(now + 0.3)
assert(cvars.Sound_EnableMusic == '0')
cvars.Sound_EnableSoundWhenGameIsInBG = '1'
tick(now + 1)
frames.TalkingHeadRu.scripts.OnUpdate()

-- Neither source loaded: stale indexes/globals cannot enable sound, but the UI works.
loaded.CatQuest_Voices = false
WV:RefreshAudioSources()
assert(not WV:HasQuestAudio(179) and WV:SoundPath(179, 'a') == nil)
assert(not journalButtons[179]:IsShown() and not trackerButtons[179]:IsShown())
before = #plays
assert(not WV:ReplayQuest(179) and #plays == before and not frames.TalkingHeadRu:IsShown())
Q:Clear()
assert(voiceRow('catquest').unavailableMessage:find('CatQuest_Voices', 1, true))

-- Modern loading/error/existence checks must reject stale primary metadata.
loaded.CatQuest_Voices, loaded.WowVoiceSounds = true, true
local isLoaded = C_AddOns.IsAddOnLoaded
C_AddOns.IsAddOnLoaded = function(name) return true, name ~= 'WowVoiceSounds' end
assert(WV:ClassicSoundPath(179, 'a') == nil and WV:SoundPath(179, 'a') == prefix .. '179.ogg')
C_AddOns.IsAddOnLoaded = isLoaded
C_AddOns.DoesAddOnHaveLoadError = function(name) return name == 'WowVoiceSounds' end
assert(WV:ClassicSoundPath(179, 'a') == nil)
C_AddOns.DoesAddOnHaveLoadError = nil
C_AddOns.DoesAddOnExist = function(name) return name ~= 'WowVoiceSounds' end
assert(WV:ClassicSoundPath(179, 'a') == nil)
C_AddOns.DoesAddOnExist = nil

WV:RefreshAudioSources()
assert(TalkingHeadRuDB.sharedQuestVoice == 'wowvoice' and WV:GetSharedQuestVoice() == 'wowvoice')
assert(voiceRow('wowvoice').available and panel.VoicePriorityRows[1].sourceID == 'wowvoice')
assert(WV:SoundPath(179, 'a'):find('WowVoiceSounds', 1, true))
assert(WV:HasQuestAudio(classicOnly) and journalButtons[classicOnly]:IsShown() and trackerButtons[classicOnly]:IsShown())
print('PASS: disabled/missing/failed primary pack, CatQuest-only playback, queue, journal/tracker, options, music and source restoration')

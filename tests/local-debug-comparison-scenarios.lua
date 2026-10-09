local C, panel = WowVoiceComparison, WowVoiceLocalDebugPanel
local popup = panel.Suggestions
local loadedAPI, metadataAPI, sexAPI = C_AddOns.IsAddOnLoaded, C_AddOns.GetAddOnMetadata, UnitSex
local loaded = {WowVoiceSounds=true, CatVoices=true, CatQuest_Voices=true}
local auditedVersion = WowVoiceCatQuestAudio.sourceVersion
local version = auditedVersion
C_AddOns.IsAddOnLoaded = function(name) return loaded[name] == true end
C_AddOns.GetAddOnMetadata = function(name, field)
    if name == 'CatQuest_Voices' and field == 'Version' then return version end
end
CatQuestVoicePack = {quests={
    [179]={d=30.7,v='dwarf-male'},
    [6]={d=23.3,g=1,v='human-male'},
    [98246]={d=28.9,v='dwarf-male'},
}}
for id, entry in pairs(CatQuestVoicePack.quests) do
    local texts = WowVoiceQuestTexts.entries[id .. 'a']
    entry.c = entry.g and {m={{0,texts.male}},f={{0,texts.female}}} or {x={{0,texts.common}}}
end
local function tile(id)
    WV:RefreshAudioSources()
    panel.QuestID:SetText(tostring(id))
    for _, row in ipairs(popup.Rows) do if row.questID == id then return row end end
    error('Missing comparison tile: ' .. id)
end
local function click(row, source)
    local button = row.PlayButtons[source]
    button.scripts.OnClick(button)
end
local row = tile(179)
assert(WV:SetSharedQuestVoice('catquest'))
click(row, 'wowvoice')
assert(plays[#plays].file == WV:ClassicSoundPath(179, 'a'), 'Explicit WowVoice preview followed CatQuest preference')
click(row, 'catquest')
assert(plays[#plays].file == 'Interface\\AddOns\\CatQuest_Voices\\Sounds\\q\\179.ogg')
WV:Silence()
WV:SetSharedQuestVoice('wowvoice')
assert(row:GetHeight() == 52 and popup.columns == 8)
assert(row.PlayButtons.wowvoice:IsEnabled() and row.PlayButtons.catquest:IsEnabled())
assert(row.PlayButtons.wowvoice.Icon.texture == 'Interface\\AddOns\\TalkingHeadRu\\Media\\Play.tga')
assert(not row.PlayButtons.wowvoice.backdrop and not row.PlayButtons.catquest.backdrop, 'Play buttons must have no frames')
assert(row.PlayButtons.wowvoice.Icon.vertexColor[3] == 1 and row.PlayButtons.catquest.Icon.vertexColor[1] == 1)
local results, startCount = popup.matches, #plays
local listened = TalkingHeadRuDB.listenedQuests and TalkingHeadRuDB.listenedQuests[playerGUID]
local deadline = listened and listened[179]
local lastKey = WV.lastKey
click(row, 'wowvoice')
local previous = plays[#plays].handle
assert(plays[#plays].file == WV:SoundPath(179, 'a'))
click(row, 'catquest')
assert(#plays == startCount + 2 and stops[#stops] == previous)
assert(plays[#plays].file == 'Interface\\AddOns\\CatQuest_Voices\\Sounds\\q\\179.ogg')
assert(frames.TalkingHeadRu.Name.text == WV:GetReplaySpeaker(179).speaker.name)
assert(frames.TalkingHeadRu.Body.text == WowVoiceAudioSources.Text(179, 'a'))
assert(WV.lastKey == lastKey and (listened and listened[179]) == deadline, 'A/B must not change regular playback/cooldowns')
assert(panel.QuestID:GetText() == '179' and popup.matches == results)
assert(row.PlayButtons.catquest.SelectedMark.visible and not row.PlayButtons.wowvoice.SelectedMark.visible)
assert(not row.Selection, 'Source selection must not outline the tile')
assert(row.PlayButtons.catquest.SelectedMark.texture == 'Interface\\AddOns\\TalkingHeadRu\\Media\\PlaySelected.tga')
local started, sound = now, plays[#plays].handle
tick(started + 30)
assert(stops[#stops] ~= sound, 'CatQuest must not use the shorter Classic timer')
tick(started + 30.738 + TalkingHeadRuDB.tail + .01)
assert(stops[#stops] == sound, 'CatQuest must stop using its own duration')
WV:Silence()
for _, sex in ipairs({2,3}) do
    UnitSex = function() return sex end
    local recording = C.Resolve(6, 'catquest')
    assert(recording.path:find(sex == 3 and '6_f.ogg' or '6_m.ogg', 1, true))
    assert(recording.duration == (sex == 3 and 23.324292 or 23.25375))
end
UnitSex = sexAPI
-- Failed CatQuest playback cannot hide a working Classic recording.
soundOK = false
row = tile(179)
click(row, 'catquest')
assert(not row.PlayButtons.catquest:IsEnabled() and row.PlayButtons.wowvoice:IsEnabled())
assert(row.PlayButtons.catquest.UnavailableMark.visible and not row.PlayButtons.wowvoice.UnavailableMark.visible)
assert(row.PlayButtons.catquest.Icon.vertexColor[1] == 1 and row.PlayButtons.catquest.Icon.vertexColor[4] == 0.4,
    'failed recordings retain their source hue with a visible unavailable mark')
assert(WV:HasQuestAudio(179))
soundOK = true
click(row, 'wowvoice')
assert(plays[#plays].file:find('179a.ogg', 1, true))
WV:Silence()
-- Missing external library keeps its offline catalogue and disabled controls.
local classicCount, catquestCount, union = 0, 0, {}
for key in pairs(WowVoiceDur) do
    local id = tonumber(key:match('^(%d+)a$'))
    if id then classicCount = classicCount + 1; union[id] = true end
end
for key in pairs(WowVoiceCatQuestAudio.entries) do
    local id = tonumber(key:match('^(%d+)a$'))
    if id then catquestCount = catquestCount + 1; union[id] = true end
end
local unionCount = 0
for _ in pairs(union) do unionCount = unionCount + 1 end
local offlineSummary = string.format('WowVoice: %d    CatQuest: %d    Всего без повторов: %d',
    classicCount, catquestCount, unionCount)
local function checkOffline(row)
    assert(row.PlayButtons.catquest:IsShown() and not row.PlayButtons.catquest:IsEnabled())
    assert(row.PlayButtons.catquest.UnavailableMark.visible)
    assert(panel.SourceLegend.catquest.Caption:GetText() == 'CatQuest — недоступна')
    for _, element in ipairs(panel.CatQuestLegend) do assert(element.visible) end
    assert(panel.CatalogSummary:GetText() == offlineSummary)
end
local existsAPI, errorAPI = C_AddOns.DoesAddOnExist, C_AddOns.DoesAddOnHaveLoadError
C_AddOns.DoesAddOnExist = function(name) return name ~= 'CatQuest_Voices' end
row = tile(179)
assert(CatQuestVoicePack.quests and loaded.CatQuest_Voices, 'Keep stale index and loaded flag for this regression')
checkOffline(row)
assert(not WowVoiceOptionsPanel.SharedVoiceButtons.catquest:IsEnabled())
C_AddOns.DoesAddOnExist = existsAPI
local fullLoadedAPI = C_AddOns.IsAddOnLoaded
C_AddOns.IsAddOnLoaded = function(name) return loaded[name] == true, name ~= 'CatQuest_Voices' end
row = tile(179)
checkOffline(row)
C_AddOns.IsAddOnLoaded = fullLoadedAPI
C_AddOns.DoesAddOnHaveLoadError = function(name) return name == 'CatQuest_Voices' end
row = tile(179)
checkOffline(row)
C_AddOns.DoesAddOnHaveLoadError = errorAPI
loaded.CatQuest_Voices = false
row = tile(179)
checkOffline(row)
panel.QuestID:SetText('')
assert(popup.matchCount == unionCount)
for _, cell in ipairs(popup.Rows) do assert(not cell.PlayButtons.catquest:IsEnabled()) end
row = tile(179)
local before = #plays
click(row, 'catquest')
assert(#plays == before, 'Disabled comparison button must do nothing')
row = tile(98246)
assert(row.PlayButtons.catquest:IsShown() and not row.PlayButtons.catquest:IsEnabled()
    and not row.PlayButtons.wowvoice:IsShown(), 'CatQuest-only quests stay discoverable offline')

-- Both libraries disabled: two distinct colors/marks, permanent legend and no
-- playback even if a stale external index remains in memory.
loaded.WowVoiceSounds = false
CatQuestVoicePack.quests[999997] = {d=10}
row = tile(179)
checkOffline(row)
assert(not C.QuestIDs()[999997], 'disabled CatQuest must use our snapshot, not stale external records')
assert(row.PlayButtons.wowvoice:IsShown() and not row.PlayButtons.wowvoice:IsEnabled())
assert(row.PlayButtons.wowvoice.UnavailableMark.visible)
assert(row.PlayButtons.wowvoice.Icon.vertexColor[3] == 1
    and row.PlayButtons.catquest.Icon.vertexColor[1] == 1)
assert(panel.SourceLegend.wowvoice.Caption:GetText() == 'WowVoice — недоступна')
before = #plays
click(row, 'wowvoice'); click(row, 'catquest')
assert(#plays == before)
local tooltip = GameTooltip
GameTooltip = setmetatable({}, {__index = function() error('Catalogue must not access tooltips') end})
for _, source in ipairs({'wowvoice', 'catquest'}) do
    local button = row.PlayButtons[source]
    button.scripts.OnEnter(button); button.scripts.OnLeave(button)
    assert(not panel.SourceLegend[source].Marker.scripts.OnEnter, 'legend status is inline, not a tooltip')
end
GameTooltip = tooltip
CatQuestVoicePack.quests[999997] = nil
loaded.WowVoiceSounds = true
WV:Silence()
local classicOnly
for key in pairs(WowVoiceDur) do
    local id = tonumber(key:match('^(%d+)a$'))
    if id and not WowVoiceCatQuestAudio.entries[id .. 'a'] then classicOnly = id; break end
end
row = tile(assert(classicOnly))
assert(row.PlayButtons.wowvoice:IsShown() and not row.PlayButtons.catquest:IsShown(),
    'Absent CatQuest recording must leave the right side empty')
loaded.CatVoices = false
loaded.CatQuest_Voices = true
version = '0.6.0'
row = tile(179)
assert(row.PlayButtons.catquest:IsEnabled(), 'An updated pack keeps compatible comparison recordings')
version = auditedVersion
row = tile(179)
assert(row.PlayButtons.catquest:IsEnabled())
assert(not row.PlayButtons.catquest.UnavailableMark.visible and row.PlayButtons.catquest.Icon.vertexColor[4] == 1)
assert(panel.SourceLegend.catquest.Caption:GetText() == 'CatQuest')
for _, element in ipairs(panel.CatQuestLegend) do assert(element.visible) end
assert(panel.CatalogSummary:GetText():find('CatQuest:', 1, true))
assert(tile(98246).PlayButtons.catquest:IsEnabled(), 'Restored library must restore its quests')
CatQuestVoicePack.quests[179].d = 999
row = tile(179)
assert(row.PlayButtons.catquest:IsEnabled() and C.Resolve(179, 'catquest').duration == 999.25,
    'Changed metadata must use the live timer')
CatQuestVoicePack = nil
row = tile(179)
checkOffline(row)
C_AddOns.IsAddOnLoaded, C_AddOns.GetAddOnMetadata, UnitSex = loadedAPI, metadataAPI, sexAPI
WV:RefreshAudioSources()
print('PASS: A/B playback, offline catalogues/counts, source-colored unavailable marks, inline legend, restored libraries and isolated failures')

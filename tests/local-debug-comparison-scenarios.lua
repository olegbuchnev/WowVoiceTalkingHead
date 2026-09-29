local C, panel = WowVoiceComparison, WowVoiceLocalDebugPanel
local popup = panel.Suggestions
local loadedAPI, metadataAPI, sexAPI = C_AddOns.IsAddOnLoaded, C_AddOns.GetAddOnMetadata, UnitSex
local loaded = {WowVoiceSounds=true, CatVoices=true, CatQuest_Voices=true}
local version = '0.2.2'
C_AddOns.IsAddOnLoaded = function(name) return loaded[name] == true end
C_AddOns.GetAddOnMetadata = function(name, field)
    if name == 'CatQuest_Voices' and field == 'Version' then return version end
end
CatQuestVoicePack = {quests={
    [179]={d=30.4,v='dwarf-male'},
    [6]={d=23.2,g=1,v='human-male'},
    [98246]={d=28.9,v='dwarf-male'},
}}
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
assert(row.PlayButtons.wowvoice.Icon.texture == 'Interface\\AddOns\\WowVoiceTalkingHead\\Media\\Play.tga')
assert(not row.PlayButtons.wowvoice.backdrop and not row.PlayButtons.catquest.backdrop, 'Play buttons must have no frames')
assert(row.PlayButtons.wowvoice.Icon.vertexColor[3] == 1 and row.PlayButtons.catquest.Icon.vertexColor[1] == 1)
local results, startCount = popup.matches, #plays
local listened = WowVoiceDB.listenedQuests and WowVoiceDB.listenedQuests[playerGUID]
local deadline = listened and listened[179]
local lastKey = WV.lastKey
click(row, 'wowvoice')
local previous = plays[#plays].handle
assert(plays[#plays].file == WV:SoundPath(179, 'a'))
click(row, 'catquest')
assert(#plays == startCount + 2 and stops[#stops] == previous)
assert(plays[#plays].file == 'Interface\\AddOns\\CatQuest_Voices\\Sounds\\q\\179.ogg')
assert(frames.WowVoiceTalkingHead.Name.text == WV:GetReplaySpeaker(179).speaker.name)
assert(frames.WowVoiceTalkingHead.Body.text == WowVoiceAudioSources.Text(179, 'a'))
assert(WV.lastKey == lastKey and (listened and listened[179]) == deadline, 'A/B must not change regular playback/cooldowns')
assert(panel.QuestID:GetText() == '179' and popup.matches == results)
assert(row.PlayButtons.catquest.SelectedMark.visible and not row.PlayButtons.wowvoice.SelectedMark.visible)
assert(not row.Selection, 'Source selection must not outline the tile')
assert(row.PlayButtons.catquest.SelectedMark.texture == 'Interface\\AddOns\\WowVoiceTalkingHead\\Media\\PlaySelected.tga')
local started, sound = now, plays[#plays].handle
tick(started + 30)
assert(stops[#stops] ~= sound, 'CatQuest must not use the shorter Classic timer')
tick(started + 30.446792 + WowVoiceDB.tail + .01)
assert(stops[#stops] == sound, 'CatQuest must stop using its own duration')
WV:Silence()
for _, sex in ipairs({2,3}) do
    UnitSex = function() return sex end
    local recording = C.Resolve(6, 'catquest')
    assert(recording.path:find(sex == 3 and '6_f.ogg' or '6_m.ogg', 1, true))
    assert(recording.duration == (sex == 3 and 23.139708 or 23.226042))
end
UnitSex = sexAPI
-- Failed CatQuest playback cannot hide a working Classic recording.
soundOK = false
row = tile(179)
click(row, 'catquest')
assert(not row.PlayButtons.catquest:IsEnabled() and row.PlayButtons.wowvoice:IsEnabled())
assert(WV:HasQuestAudio(179))
soundOK = true
click(row, 'wowvoice')
assert(plays[#plays].file:find('179a.ogg', 1, true))
WV:Silence()
-- Missing external library hides its controls and quests before any click.
local existsAPI, errorAPI = C_AddOns.DoesAddOnExist, C_AddOns.DoesAddOnHaveLoadError
C_AddOns.DoesAddOnExist = function(name) return name ~= 'CatQuest_Voices' end
row = tile(179)
assert(CatQuestVoicePack.quests and loaded.CatQuest_Voices, 'Keep stale index and loaded flag for this regression')
assert(not row.PlayButtons.catquest:IsShown())
assert(not WowVoiceOptionsPanel.SharedVoiceButtons.catquest:IsEnabled())
for _, element in ipairs(panel.CatQuestLegend) do assert(not element.visible) end
C_AddOns.DoesAddOnExist = existsAPI
local fullLoadedAPI = C_AddOns.IsAddOnLoaded
C_AddOns.IsAddOnLoaded = function(name) return loaded[name] == true, name ~= 'CatQuest_Voices' end
row = tile(179)
assert(not row.PlayButtons.catquest:IsShown())
C_AddOns.IsAddOnLoaded = fullLoadedAPI
C_AddOns.DoesAddOnHaveLoadError = function(name) return name == 'CatQuest_Voices' end
row = tile(179)
assert(not row.PlayButtons.catquest:IsShown())
C_AddOns.DoesAddOnHaveLoadError = errorAPI
loaded.CatQuest_Voices = false
row = tile(179)
assert(not row.PlayButtons.catquest:IsEnabled())
assert(not row.PlayButtons.catquest:IsShown(), 'Missing CatQuest library must have no play icons')
for _, element in ipairs(panel.CatQuestLegend) do assert(not element.visible) end
local classicCount = 0
for key in pairs(WowVoiceDur) do if key:match('^%d+a$') then classicCount = classicCount + 1 end end
assert(panel.CatalogSummary:GetText() == 'WowVoice: ' .. classicCount)
panel.QuestID:SetText('')
assert(popup.matchCount == classicCount)
for _, cell in ipairs(popup.Rows) do assert(not cell.PlayButtons.catquest:IsShown()) end
row = tile(179)
local before = #plays
click(row, 'catquest')
assert(#plays == before, 'Disabled comparison button must do nothing')
panel.QuestID:SetText('98246')
assert(popup.matchCount == 0, 'CatQuest-only quests must not leave empty tiles')
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
version = '0.2.3'
row = tile(179)
assert(not row.PlayButtons.catquest:IsEnabled(), 'Unsupported full pack must be disabled')
version = '0.2.2'
row = tile(179)
assert(row.PlayButtons.catquest:IsEnabled())
for _, element in ipairs(panel.CatQuestLegend) do assert(element.visible) end
assert(panel.CatalogSummary:GetText():find('CatQuest:', 1, true))
assert(tile(98246).PlayButtons.catquest:IsEnabled(), 'Restored library must restore its quests')
CatQuestVoicePack.quests[179].d = 999
row = tile(179)
assert(not row.PlayButtons.catquest:IsEnabled(), 'Changed metadata must not use an old timer')
CatQuestVoicePack = nil
row = tile(179)
assert(not row.PlayButtons.catquest:IsShown(), 'Missing live index must hide CatQuest even if the client still reports it loaded')
assert(panel.CatalogSummary:GetText() == 'WowVoice: ' .. classicCount)
C_AddOns.IsAddOnLoaded, C_AddOns.GetAddOnMetadata, UnitSex = loadedAPI, metadataAPI, sexAPI
WV:RefreshAudioSources()
print('PASS: A/B tiles, immediate source switch, exact source timers/sex/text, isolated failures/cooldowns, grey unavailable icons and optional external pack support')

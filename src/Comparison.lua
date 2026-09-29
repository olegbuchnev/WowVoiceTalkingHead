-- Explicit previews never change the saved preference for normal quest playback.
local WV, Sources = WowVoice, WowVoiceAudioSources
local Comparison = {}
WowVoiceComparison = Comparison
local failed, revision = {}, nil
function Comparison.HasCatQuest()
    return Sources.Loaded("CatQuest_Voices") and type(CatQuestVoicePack) == "table"
        and type(CatQuestVoicePack.quests) == "table"
end
function Comparison.Known(id, source)
    if source == "wowvoice" then return WowVoiceDur and WowVoiceDur[id .. "a"] ~= nil end
    if source == "catquest" then
        local metadata = WowVoiceCatQuestAudio
        if metadata and metadata.entries[id .. "a"] then return true end
        return false
    end
    return false
end
function Comparison.Resolve(id, source)
    if revision ~= WV.audioRevision then failed, revision = {}, WV.audioRevision end
    if type(id) ~= "number" or id <= 0 or id % 1 ~= 0 then return end
    local path, seconds, text
    if source == "wowvoice" then
        if not Sources.Loaded("WowVoiceSounds") or not (WowVoiceDur and WowVoiceDur[id .. "a"]) then return end
        path, seconds = WV:ClassicSoundPath(id, "a")
    elseif source == "catquest" then
        local recording = Sources.Resolve(id, "a")
        if recording then path, seconds = recording.path, recording.duration end
        text = Sources.Text(id, "a")
    end
    if not path or type(seconds) ~= "number" or seconds <= 0 or failed[path] then return end
    return { path = path, duration = seconds, text = text }
end
function Comparison.QuestIDs()
    local candidates, result = {}, {}
    local function add(index)
        for key in pairs(index or {}) do
            local id = type(key) == "number" and key or tonumber(key:match("^(%d+)a$"))
            if id then candidates[id] = true end
        end
    end
    add(WowVoiceDur)
    if Comparison.HasCatQuest() then
        add(WowVoiceCatQuestAudio and WowVoiceCatQuestAudio.entries)
    end
    for id in pairs(candidates) do
        if Comparison.Known(id, "wowvoice") or Comparison.Known(id, "catquest") then result[id] = true end
    end
    return result
end
function Comparison.Play(id, source)
    local recording = Comparison.Resolve(id, source)
    if not recording then return false end
    if not (WowVoiceDB and WowVoiceDB.enabled) then
        DEFAULT_CHAT_FRAME:AddMessage("WowVoice TalkingHead: озвучка выключена. Включить: /thead on")
        return false
    end
    local ok = WV:PreviewQuestAudio(id, recording.path, recording.duration, recording.text)
    if not ok then failed[recording.path] = true end
    return ok
end

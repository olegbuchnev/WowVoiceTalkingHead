local L = WowVoiceLocale
-- Explicit previews never change the saved preference for normal quest playback.
local WV, Sources = WowVoice, WowVoiceAudioSources
local Comparison = {}
WowVoiceComparison = Comparison
local failed, revision = {}, nil
function Comparison.HasCatQuest()
    return Sources.Status() ~= nil
end
local function catQuestSnapshot()
    local data = WowVoiceCatQuestAudio
    return type(data) == "table" and data.schemaVersion == 1 and type(data.entries) == "table" and data.entries or {}
end
function Comparison.SourceAvailable(source)
    return Sources.Available(source)
end
function Comparison.Known(id, source)
    if source == "wayfarer" then return WowVoiceWayfarerSource and WowVoiceWayfarerSource.Known(id) end
    if source == "wowvoice" then return WowVoiceDur and WowVoiceDur[id .. "a"] ~= nil end
    if source == "catquest" then
        local status = Sources.Status()
        if status then
            local quest = status.quests[id]
            return type(quest) == "table" and quest.d ~= nil
        end
        -- The offline catalogue is descriptive only. Resolve still requires
        -- the loaded library and never fabricates playable snapshot paths.
        return type(catQuestSnapshot()[id .. "a"]) == "table"
    end
    return false
end
function Comparison.Resolve(id, source)
    if revision ~= WV.audioRevision then failed, revision = {}, WV.audioRevision end
    if type(id) ~= "number" or id <= 0 or id % 1 ~= 0 then return end
    local path, seconds, text, verified, packName
    if source == "wowvoice" then
        if not Sources.Loaded("WowVoiceSounds") or not (WowVoiceDur and WowVoiceDur[id .. "a"]) then return end
        local version, sourceID
        path, seconds, version, sourceID, verified = WV:ClassicSoundPath(id, "a")
    elseif source == "catquest" or source == "wayfarer" then
        local recording = Sources.Resolve(id, "a", source)
        if recording then
            path, seconds, verified = recording.path, recording.duration, recording.verified
            packName = recording.packName
        end
    end
    if not path or type(seconds) ~= "number" or seconds <= 0 or failed[path] then return end
    text = Sources.Text(id, "a")
    return { path = path, duration = seconds, text = text, sourceID = source, verified = verified, packName = packName }
end
function Comparison.QuestIDs()
    local candidates, result = {}, {}
    local function add(index)
        for key in pairs(index or {}) do
            local id = type(key) == "number" and key
                or (type(key) == "string" and tonumber(key:match("^(%d+)a$")))
            if id and id > 0 and id % 1 == 0 then candidates[id] = true end
        end
    end
    add(WowVoiceDur)
    if Comparison.HasCatQuest() then
        add(Sources.Status().quests)
    else
        add(catQuestSnapshot())
    end
    for id in pairs(candidates) do
        if Comparison.Known(id, "wowvoice") or Comparison.Known(id, "catquest") then result[id] = true end
    end
    if WowVoiceWayfarerSource then
        for id in pairs(WowVoiceWayfarerSource.QuestIDs(true, true)) do result[id] = true end
    end
    return result
end
function Comparison.Play(id, source)
    local recording = Comparison.Resolve(id, source)
    if not recording then return false end
    if not (TalkingHeadRuDB and TalkingHeadRuDB.enabled) then
        DEFAULT_CHAT_FRAME:AddMessage(L["TalkingHead Ru: озвучка выключена. Включить: /thead on"])
        return false
    end
    local ok = WV:PreviewQuestAudio(id, recording.path, recording.duration, recording.text, recording.sourceID, recording.verified)
    if not ok then failed[recording.path] = true end
    return ok
end

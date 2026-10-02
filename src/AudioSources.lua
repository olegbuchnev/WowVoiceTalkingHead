local L = WowVoiceLocale
-- Data-only source selection. Playback and CatQuest's player remain independent.
local Sources = {}
WowVoiceAudioSources = Sources
-- Includes rounding and small upstream index errors (0.2.0 quest 132 is
-- about 0.181 seconds longer than d). Exact OGG measurements need no padding.
local UNVERIFIED_PADDING = 0.25

function Sources.Loaded(name)
    local exists = C_AddOns and C_AddOns.DoesAddOnExist
    if exists and not exists(name) then return false end
    local loadError = C_AddOns and C_AddOns.DoesAddOnHaveLoadError
    if loadError and loadError(name) then return false end
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if not loaded then return false end
    -- Modern clients return loadedOrLoading, loaded. A stale global/index is
    -- not proof that the dependency finished loading in this UI session.
    local started, complete = loaded(name)
    if complete ~= nil then return complete == true end
    return started == true -- Legacy clients return a single boolean.
end

function Sources.Metadata(name, field)
    local metadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return metadata and metadata(name, field) or nil
end

function Sources.IsClassic(id)
    local d = WowVoiceDur or {}
    return d[id .. "a"] ~= nil or d[id .. "p"] ~= nil or d[id .. "c"] ~= nil
end

function Sources.IsSupplement(id)
    if Sources.IsClassic(id) then return false end
    local index = WowVoiceCatQuestAudio and WowVoiceCatQuestAudio.entries or {}
    if index[id .. "a"] or index[id .. "c"] then return true end
    return type(CatQuestVoicePack) == "table" and type(CatQuestVoicePack.quests) == "table"
        and CatQuestVoicePack.quests[id] ~= nil
end

local function olderVersion(installed, indexed)
    local function parts(version)
        if type(version) ~= "string" then return end
        local major, minor, patch = version:match("^(%d+)%.(%d+)%.(%d+)$")
        if major then return { tonumber(major), tonumber(minor), tonumber(patch) } end
    end
    local a, b = parts(installed), parts(indexed)
    if not a or not b then return false end
    for i = 1, 3 do
        if a[i] ~= b[i] then return a[i] < b[i] end
    end
    return false
end

local function external()
    if not Sources.Loaded("CatQuest_Voices") then return nil, "CatQuest_Voices не загружен" end
    local pack, compat = _G.CatQuestVoicePack, _G.WowVoiceCatQuestAudio
    if type(pack) ~= "table" or type(pack.quests) ~= "table" then
        return nil, "индекс CatQuest_Voices не загружен"
    end
    if pack.schemaVersion ~= nil and pack.schemaVersion ~= 1 then
        return nil, "формат индекса CatQuest_Voices не поддерживается"
    end
    local snapshot = type(compat) == "table" and compat.schemaVersion == 1
        and type(compat.entries) == "table" and compat or nil
    local version = Sources.Metadata("CatQuest_Voices", "Version")
    if type(version) ~= "string" or version == "" then version = nil end
    local indexedVersion = snapshot and snapshot.sourceVersion
    local verified = version ~= nil and version == indexedVersion
    return { id = "catquest", version = version or "не указана", indexedVersion = indexedVersion,
        updated = not verified, outdated = olderVersion(version, indexedVersion),
        entries = snapshot and snapshot.entries or {}, quests = pack.quests,
        prefix = "Interface\\AddOns\\CatQuest_Voices\\Sounds\\q\\" }
end

function Sources.Status()
    return external()
end

local function positiveNumber(value)
    return type(value) == "number" and value > 0 and value < math.huge
end

local function liveRecord(source, id, section)
    local quest = source.quests[id]
    if type(quest) ~= "table" then return nil end
    if section == "a" then return quest end
    if section == "c" and type(quest.t) == "table" then return quest.t end
end

local function variantFor(gender)
    if gender == nil or gender == false or gender == 0 then return "x" end
    if gender ~= 1 and gender ~= true then return nil end
    return type(UnitSex) == "function" and UnitSex("player") == 3 and "f" or "m"
end

function Sources.Resolve(id, section)
    if type(id) ~= "number" or id <= 0 or id % 1 ~= 0
        or (section ~= "a" and section ~= "p" and section ~= "c") then return nil end
    local source = Sources.Status()
    if not source then return nil end
    if section == "p" then return nil end
    local entry = source.entries[id .. section]
    local live = liveRecord(source, id, section)
    local recovered = not source.updated and type(entry) == "table" and entry.jsonOnly
        and source.quests[id] == nil
    if not recovered and (not live or not positiveNumber(live.d)) then return nil end
    local audio = type(entry) == "table" and entry.audio or nil
    local variant = recovered and (type(audio) == "table" and variantFor(audio.male ~= nil))
        or live and variantFor(live.g)
    if not variant then return nil end
    local stem = tostring(id) .. (section == "c" and "_t" or "")
    local file = stem .. (variant == "x" and "" or "_" .. variant) .. ".ogg"
    local selectedCues = live and type(live.c) == "table" and live.c[variant] or nil
    local verified = not source.updated and type(entry) == "table" and (recovered
        or (not entry.jsonOnly and live.d == entry.indexDuration
            and (variant ~= "x") == entry.gender and (live.v or "") == entry.voice))
    if type(audio) == "table" and variant ~= "x" then audio = variant == "f" and audio.female or audio.male end
    verified = verified and type(audio) == "table" and audio.file == file and positiveNumber(audio.duration)
    -- The live index owns availability and naming. The snapshot supplies only
    -- measured per-file timing for an audited release and matching record.
    if recovered and not verified then return nil end
    local seconds = verified and audio.duration or live.d + UNVERIFIED_PADDING
    return { path = source.prefix .. file, duration = seconds, verified = verified == true,
        sourceID = source.id, sourceVersion = source.version, variant = variant,
        cues = selectedCues }
end

-- Transcripts ship with the addon itself, so every package has the same fallback.
-- Independent of installed audio sources; includes Classic overlaps as well.
function Sources.Text(id, section, sourceID)
    if type(id) ~= "number" or id <= 0 or id % 1 ~= 0
        or (section ~= "a" and section ~= "c") then return nil end
    if sourceID == "catquest" then
        local source = Sources.Status()
        if not source then return nil end
        local live = liveRecord(source, id, section)
        local variant = live and variantFor(live.g)
        local cues = variant and type(live.c) == "table" and live.c[variant]
        if type(cues) == "table" and #cues > 0 then
            local parts = {}
            for _, cue in ipairs(cues) do
                if type(cue) ~= "table" or type(cue[2]) ~= "string" then return nil end
                local text = cue[2]:match("^%s*(.-)%s*$")
                if text ~= "" then parts[#parts + 1] = text end
            end
            return #parts > 0 and table.concat(parts, " ") or nil
        end
        -- Never attach stale snapshot subtitles to an unverified recording.
        local recording = Sources.Resolve(id, section)
        if not recording or not recording.verified then return nil end
    end
    local database = _G.WowVoiceQuestTexts
    if type(database) ~= "table" or database.schemaVersion ~= 1
        or type(database.entries) ~= "table" then return nil end
    local texts = database.entries[id .. section]
    if type(texts) ~= "table" then return nil end
    local female = type(UnitSex) == "function" and UnitSex("player") == 3
    local key = texts.common and "common" or (female and "female" or "male")
    local text = texts[key]
    return type(text) == "string" and text ~= "" and text or nil
end

-- Choose only at display time: keep captured game text intact in queue/session
-- data so changing locale or audio source can choose again on the next replay.
function Sources.DisplayText(context)
    if not L.isRussian then
        local russian = Sources.Text(context.questId, context.section)
        if russian and russian:find("[\208-\211][\128-\191]") then return russian end
    end
    local text = context.text
    if type(text) == "string" and text:find("%S") then return text end
    return Sources.Text(context.questId, context.section, context.audioSourceID)
end

function Sources.QuestIDs()
    local ids = {}
    local function add(index)
        for key in pairs(index or {}) do
            local id = type(key) == "string" and tonumber(key:match("^(%d+)[apc]$"))
            if id then ids[id] = true end
        end
    end
    add(WowVoiceDur)
    local source = Sources.Status()
    if source then
        for id in pairs(source.quests) do
            if type(id) == "number" and id > 0 and id % 1 == 0 then ids[id] = true end
        end
        if not source.updated then add(source.entries) end
    end
    return ids
end

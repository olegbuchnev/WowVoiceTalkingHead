-- Data-only source selection. Playback and CatQuest's player remain independent.
local Sources = {}
WowVoiceAudioSources = Sources

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
    if type(compat) ~= "table" or compat.schemaVersion ~= 1 or type(compat.entries) ~= "table" then
        return nil, "метаданные совместимости CatQuest Voices недоступны"
    end
    local version = Sources.Metadata("CatQuest_Voices", "Version")
    if type(version) ~= "string" or version == "" then version = nil end
    return { id = "catquest", version = version or "не указана", indexedVersion = compat.sourceVersion,
        updated = version ~= compat.sourceVersion, outdated = olderVersion(version, compat.sourceVersion),
        entries = compat.entries, quests = pack.quests,
        prefix = "Interface\\AddOns\\CatQuest_Voices\\Sounds\\q\\" }
end

function Sources.Status()
    return external()
end

function Sources.Resolve(id, section)
    if type(id) ~= "number" or id <= 0 or id % 1 ~= 0
        or (section ~= "a" and section ~= "p" and section ~= "c") then return nil end
    local source = Sources.Status()
    if not source then return nil end
    local entry = source.entries[id .. section]
    if type(entry) ~= "table" then return nil end
    local cues, indexDuration
    if source.id == "catquest" then
        local liveQuest = source.quests[id]
        local live = type(liveQuest) == "table" and (section == "a" and liveQuest or liveQuest.t) or nil
        if entry.jsonOnly then
            -- Recovery is valid only while upstream still omits this quest entirely.
            -- A newer pack may have removed the file as well as its index entry.
            if source.updated or liveQuest ~= nil then return nil end
        elseif type(live) ~= "table" or live.d ~= entry.indexDuration
            or (not not live.g) ~= entry.gender or (live.v or "") ~= entry.voice then
            return nil
        end
        cues = live and live.c
        indexDuration = live and live.d
        entry = entry.audio
    end
    if type(entry) ~= "table" then return nil end
    local female = type(UnitSex) == "function" and UnitSex("player") == 3
    local variant = entry.male and (female and "f" or "m") or "x"
    if entry.male then entry = female and entry.female or entry.male end
    if type(entry) ~= "table" or type(entry.file) ~= "string" or type(entry.duration) ~= "number"
        or entry.duration <= 0 or entry.duration == math.huge or entry.duration ~= entry.duration then return nil end
    local stem = tostring(id) .. (section == "c" and "_t" or "")
    local expected = stem .. (variant == "x" and "" or "_" .. variant) .. ".ogg"
    if section == "p" or entry.file ~= expected then return nil end
    local selectedCues = type(cues) == "table" and cues[variant] or nil
    local seconds = entry.duration
    if source.updated then
        -- Matching voice/sex/duration is required even on an unfamiliar release.
        -- Changed wording with the same rounded duration is a different record.
        local text = Sources.Text(id, section)
        if text then
            if type(selectedCues) ~= "table" or #selectedCues == 0 then return nil end
            local parts = {}
            for _, cue in ipairs(selectedCues) do
                if type(cue) ~= "table" or type(cue[2]) ~= "string" then return nil end
                parts[#parts + 1] = cue[2]:match("^%s*(.-)%s*$")
            end
            if table.concat(parts, " ") ~= text then return nil end
        end
        -- The OGG may have been re-encoded even when rounded metadata matches.
        -- Use the live maximum (including sex variants) plus rounding allowance;
        -- exact per-file timing returns after importing that release's metadata.
        seconds = indexDuration + 0.1
    end
    return { path = source.prefix .. entry.file, duration = seconds,
        sourceID = source.id, sourceVersion = source.version, variant = variant,
        cues = selectedCues }
end

-- Transcripts ship with the addon itself, so every package has the same fallback.
-- Independent of installed audio sources; includes Classic overlaps as well.
function Sources.Text(id, section)
    if type(id) ~= "number" or id <= 0 or id % 1 ~= 0
        or (section ~= "a" and section ~= "c") then return nil end
    local database = _G.WowVoiceCatQuestTexts
    if type(database) ~= "table" or database.schemaVersion ~= 1
        or type(database.entries) ~= "table" then return nil end
    local texts = database.entries[id .. section]
    if type(texts) ~= "table" then return nil end
    local female = type(UnitSex) == "function" and UnitSex("player") == 3
    local key = texts.common and "common" or (female and "female" or "male")
    local text = texts[key]
    return type(text) == "string" and text ~= "" and text or nil
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
    if source then add(source.entries) end
    return ids
end

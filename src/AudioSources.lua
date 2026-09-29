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

local function external()
    if not Sources.Loaded("CatQuest_Voices") then return nil, "CatQuest_Voices не загружен" end
    local pack, compat = _G.CatQuestVoicePack, _G.WowVoiceCatQuestAudio
    if type(pack) ~= "table" or type(pack.quests) ~= "table" then
        return nil, "индекс CatQuest_Voices не загружен"
    end
    local version = Sources.Metadata("CatQuest_Voices", "Version")
    if type(compat) ~= "table" or compat.schemaVersion ~= 1 or type(compat.entries) ~= "table"
        or not version or version ~= compat.sourceVersion then
        return nil, "CatQuest_Voices: неподдерживаемая версия " .. tostring(version or "не указана")
    end
    return { id = "catquest", version = version, entries = compat.entries, quests = pack.quests,
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
    local cues
    if source.id == "catquest" then
        local liveQuest = source.quests[id]
        local live = type(liveQuest) == "table" and (section == "a" and liveQuest or liveQuest.t) or nil
        if entry.jsonOnly then
            -- Recovery is valid only while upstream still omits this quest entirely.
            if liveQuest ~= nil then return nil end
        elseif type(live) ~= "table" or live.d ~= entry.indexDuration
            or (not not live.g) ~= entry.gender or (live.v or "") ~= entry.voice then
            return nil
        end
        cues = live and live.c
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
    return { path = source.prefix .. entry.file, duration = entry.duration,
        sourceID = source.id, sourceVersion = source.version, variant = variant,
        cues = type(cues) == "table" and cues[variant] or nil }
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

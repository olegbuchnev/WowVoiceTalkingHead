-- Read-only adapter for registered Wayfarer format-1 packs. Never run its player.
local W = {}
WowVoiceWayfarerSource = W
-- Core API release audited for this adapter; pack releases/timings are generated
-- separately in WayfarerAudio.lua. Updating one does not certify the other.
local AUDITED_CORE_VERSION = "0.7.0"
local requiredPacks = {"Wayfarer_Voices_Alliance", "Wayfarer_Voices_Horde", "Wayfarer_Voices_Shared"}
local function positive(value)
    return type(value) == "number" and value > 0 and value < math.huge
end
local function snapshot()
    local data = _G.WowVoiceWayfarerAudio
    return type(data) == "table" and data.schemaVersion == 1 and type(data.packs) == "table" and data.packs or {}
end
local function olderVersion(installed, audited)
    local function parts(version)
        if type(version) ~= "string" then return end
        local a, b, c = version:match("^(%d+)%.(%d+)%.(%d+)$")
        if a then return {tonumber(a), tonumber(b), tonumber(c)} end
    end
    local a, b = parts(installed), parts(audited)
    if not a or not b then return false end
    for i = 1, 3 do
        if a[i] ~= b[i] then return a[i] < b[i] end
    end
    return false
end
function W.VersionChanges()
    local S, changes = WowVoiceAudioSources, {}
    if not S.Loaded("Wayfarer") then return changes end
    local function check(addon, audited)
        if not S.Loaded(addon) then return end
        local installed = S.Metadata(addon, "Version")
        if type(installed) ~= "string" or installed == "" then installed = nil end
        if installed and installed == audited then return end
        changes[#changes + 1] = {addon=addon, installed=installed, audited=audited,
            outdated=olderVersion(installed, audited)}
    end
    check("Wayfarer", AUDITED_CORE_VERSION)
    local indexed, names, known = snapshot(), {}, {}
    for name, pack in pairs(indexed) do
        if type(pack.entries) == "table" and next(pack.entries) then known[name] = true end
    end
    local registry = type(_G.Wayfarer) == "table" and Wayfarer.Packs
    local registered = type(registry) == "table" and type(registry.list) == "table" and registry.list or {}
    for _, pack in ipairs(registered) do
        if type(pack) == "table" and type(pack.name) == "string"
            and pack.name:match("^Wayfarer_Voices[%w_]*$")
            and type(pack.q) == "table" and next(pack.q) then known[pack.name] = true end
    end
    for name in pairs(known) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do check(name, indexed[name] and indexed[name].version) end
    return changes
end
function W.Status()
    local S, ns = WowVoiceAudioSources, _G.Wayfarer
    if not S.Loaded("Wayfarer") or type(ns) ~= "table" or type(ns.Packs) ~= "table"
        or type(ns.Packs.list) ~= "table" then return nil end
    local packs = {}
    for _, pack in ipairs(ns.Packs.list) do
        if type(pack) == "table" and type(pack.name) == "string"
            and pack.name:match("^Wayfarer_Voices[%w_]*$") and S.Loaded(pack.name)
            and pack.format == 1 and type(pack.q) == "table" and next(pack.q) ~= nil
            and (pack.ext == nil or pack.ext == "ogg") then packs[#packs + 1] = pack end
    end
    if #packs == 0 then return nil end
    -- Our adapter selects v4 first, independently of Wayfarer's player settings.
    local wanted = "v4"
    table.sort(packs, function(a, b)
        local am, bm = (a.model or "v3") == wanted, (b.model or "v3") == wanted
        if am ~= bm then return am end
        local ap, bp = tonumber(a.priority) or 0, tonumber(b.priority) or 0
        if ap ~= bp then return ap > bp end
        return a.name < b.name
    end)
    return {id="wayfarer", packs=packs}
end
local function loadedPacks()
    local source, packs = W.Status(), {}
    for _, pack in ipairs(source and source.packs or {}) do packs[pack.name] = pack end
    return packs
end
function W.MissingPacks()
    local loaded, missing = loadedPacks(), {}
    for _, name in ipairs(requiredPacks) do
        if not loaded[name] then missing[#missing + 1] = name end
    end
    return missing
end
local function selected(entry)
    local key = "d"
    if entry.m ~= nil or entry.f ~= nil then
        key = type(UnitSex) == "function" and UnitSex("player") == 3 and "f" or "m"
        if entry[key] == nil then key = entry.m ~= nil and "m" or "f" end
    end
    if not positive(entry[key]) then return end
    return key
end
function W.Resolve(id, section)
    if type(id) ~= "number" or id <= 0 or id % 1 ~= 0
        or (section ~= "a" and section ~= "p" and section ~= "c") then return end
    local source = W.Status()
    if not source then return end
    for _, pack in ipairs(source.packs) do
        local quest = pack.q[id]
        local entry = type(quest) == "table" and quest[section]
        local variant = type(entry) == "table" and selected(entry)
        if variant then
            local file = "q/" .. id .. "-" .. section .. (variant == "d" and "" or "-" .. variant) .. ".ogg"
            local version = WowVoiceAudioSources.Metadata(pack.name, "Version")
            local audited = snapshot()[pack.name]
            local record = audited and audited.entries and audited.entries[id .. section]
            local audio = record and record.audio and record.audio[variant]
            local verified = audited and version == audited.version and pack.version == audited.version
                and (pack.model or "v3") == audited.model and type(audio) == "table"
                and audio.file == file and audio.indexDuration == entry[variant]
                and record.voice == (entry.v or "") and record.speaker == (entry.s or 0)
                and positive(audio.duration)
            return {path="Interface\\AddOns\\" .. pack.name .. "\\" .. file:gsub("/", "\\"),
                duration=verified and audio.duration or entry[variant] + 0.25,
                sourceID="wayfarer", sourceVersion=version, verified=verified == true,
                variant=variant, cues=entry[variant == "d" and "t" or "t" .. variant],
                speaker=entry.s, packName=pack.name}
        end
    end
end
function W.Text(id, section)
    local recording = W.Resolve(id, section)
    if not recording or type(recording.cues) ~= "table" then return end
    local parts = {}
    for _, cue in ipairs(recording.cues) do
        if type(cue) ~= "table" or type(cue[2]) ~= "string" then return end
        local text = cue[2]:match("^%s*(.-)%s*$")
        if text ~= "" then parts[#parts + 1] = text end
    end
    return #parts > 0 and table.concat(parts, " ") or nil
end
function W.QuestIDs(offline, descriptionsOnly)
    local ids, loaded = {}, loadedPacks()
    for _, pack in pairs(loaded) do
        for id, quest in pairs(pack.q) do
            if type(id) == "number" and id > 0 and id % 1 == 0 and type(quest) == "table" then
                for _, section in ipairs(descriptionsOnly and {"a"} or {"a", "p", "c"}) do
                    if type(quest[section]) == "table" and selected(quest[section]) then ids[id] = true end
                end
            end
        end
    end
    if offline then
        for name, pack in pairs(snapshot()) do
            -- A loaded pack replaces only its own audited index. Missing packs
            -- remain in the catalogue, without granting playback availability.
            if not loaded[name] then
                for key in pairs(pack.entries or {}) do
                    local id = tonumber(key:match(descriptionsOnly and "^(%d+)a$" or "^(%d+)[apc]$"))
                    if id then ids[id] = true end
                end
            end
        end
    end
    return ids
end
function W.PacksForQuest(id, section)
    local loaded, names = loadedPacks(), {}
    for name, pack in pairs(loaded) do
        local quest = pack.q[id]
        local entry = type(quest) == "table" and quest[section]
        if type(entry) == "table" and selected(entry) then names[#names + 1] = name end
    end
    for name, pack in pairs(snapshot()) do
        if not loaded[name] and pack.entries and pack.entries[id .. section] then names[#names + 1] = name end
    end
    table.sort(names)
    return names
end
function W.Known(id)
    return #W.PacksForQuest(id, "a") > 0
end

-- Simulate the upstream index only. No CatQuest player or bundled audio pack.
CatQuestVoicePack = {quests = {}}
for key, entry in pairs(WowVoiceCatQuestAudio.entries) do
    if not entry.jsonOnly then
        local id, section = key:match('^(%d+)([ac])$')
        id = tonumber(id)
        local quest = CatQuestVoicePack.quests[id] or {}
        CatQuestVoicePack.quests[id] = quest
        local record = {d=entry.indexDuration, g=entry.gender and 1 or nil, v=entry.voice, c={}}
        local texts = WowVoiceQuestTexts.entries[key]
        for _, variant in ipairs(entry.gender and {'m','f'} or {'x'}) do
            local text = texts and texts[variant == 'x' and 'common' or variant == 'm' and 'male' or 'female']
            if text then record.c[variant] = {{0, text}} end
        end
        if section == 'a' then
            quest.d, quest.g, quest.v, quest.c = record.d, record.g, record.v, record.c
        else quest.t = record end
    end
end
C_AddOns.GetAddOnMetadata = function(name, field)
    if name == 'CatQuest_Voices' and field == 'Version' then return WowVoiceCatQuestAudio.sourceVersion end
end

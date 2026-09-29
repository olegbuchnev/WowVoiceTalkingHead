-- Simulate the upstream index only. No CatQuest player or bundled audio pack.
CatQuestVoicePack = {quests = {}}
for key, entry in pairs(WowVoiceCatQuestAudio.entries) do
    if not entry.jsonOnly then
        local id, section = key:match('^(%d+)([ac])$')
        id = tonumber(id)
        local quest = CatQuestVoicePack.quests[id] or {}
        CatQuestVoicePack.quests[id] = quest
        local record = {d=entry.indexDuration, g=entry.gender and 1 or nil, v=entry.voice}
        if section == 'a' then
            quest.d, quest.g, quest.v = record.d, record.g, record.v
        else quest.t = record end
    end
end
C_AddOns.GetAddOnMetadata = function(name, field)
    if name == 'CatQuest_Voices' and field == 'Version' then return '0.2.2' end
end

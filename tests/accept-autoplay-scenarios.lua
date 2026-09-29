event('ADDON_LOADED')
local WV = WowVoice
assert(WowVoiceDB.autoPlayAccept == true, 'fresh installations default to automatic descriptions')
event('QUEST_DETAIL')
assert(#plays == 1 and plays[1].file:find('179a.ogg',1,true))
WV:Silence()
plays, stops = {}, {}

-- Correct the previous unreleased default once, preserving unrelated settings.
WowVoiceDB = {autoPlayAccept=false, trackerButtons=false, volume=0.6}
event('ADDON_LOADED')
assert(WowVoiceDB.autoPlayAccept == true and WowVoiceDB.trackerButtons == nil
    and WowVoiceDB.volume == 0.6)
command('options')
local panel = frames.WowVoiceOptionsPanel
assert(panel.AutoPlayAccept:GetChecked() == true)
panel.AutoPlayAccept:SetChecked(false)
panel.AutoPlayAccept.scripts.OnClick(panel.AutoPlayAccept)
event('ADDON_LOADED')
assert(WowVoiceDB.autoPlayAccept == false, 'explicit opt-out survives later loads')

-- Pick ten voiced quests and accept them without starting or queueing audio.
local ids = {}
for key in pairs(WowVoiceDur) do
    if key:match('^%d+a$') then ids[#ids+1] = tonumber(key:sub(1,-2)) end
end
table.sort(ids)
GetTitleText = function() return 'Quest ' .. questID end
GetQuestText = function() return 'Description ' .. questID end
for i=1,10 do
    questID = ids[i]
    npcDisplay = 7000+i
    event('QUEST_DETAIL')
    portraitEvent('QUEST_ACCEPTED',questID)
    local record = questCache()[questID]
    assert(record.description == GetQuestText() and record.displayID == npcDisplay)
end
assert(#plays == 0 and #stops == 0)
assert(not frames.WowVoiceTalkingHead or not frames.WowVoiceTalkingHead:IsShown())
restored('1','0.37')
tick(now+300)
assert(#plays == 0, 'accepting silently must not queue descriptions')

-- Manual replay retains the captured text/portrait, even when another quest opens.
assert(WV:ReplayQuest(ids[1]))
local head = frames.WowVoiceTalkingHead
assert(head.Body.text == 'Description ' .. ids[1] and head.Model.displayID == 7001)
local count, stopped, lastKey = #plays, #stops, WV.lastKey
questID = ids[10]
event('QUEST_DETAIL')
assert(#plays == count and #stops == stopped and WV.lastKey == lastKey)
assert(head.Model.displayID == 7001)
assert(WV:ReplayQuest(ids[2]))
assert(head.Model.displayID == 7002 and #plays == count+1)
WV:Silence()

-- Progress and completion remain automatic while descriptions are disabled.
questID = 179
for _,entry in ipairs({{'QUEST_PROGRESS','p'},{'QUEST_COMPLETE','c'}}) do
    event(entry[1])
    assert(plays[#plays].file:find('179' .. entry[2] .. '.ogg',1,true))
    WV:Silence()
end

-- Actual checkbox changes take effect on the next quest, and persist on load.
count, stopped = #plays, #stops
panel.AutoPlayAccept:SetChecked(true)
panel.AutoPlayAccept.scripts.OnClick(panel.AutoPlayAccept)
assert(WowVoiceDB.autoPlayAccept == true and #plays == count and #stops == stopped)
event('ADDON_LOADED')
WV:RefreshHeadOptions()
assert(panel.AutoPlayAccept:GetChecked() == true)
event('QUEST_DETAIL')
assert(#plays == count+1 and plays[#plays].file:find('179a.ogg',1,true))
count, stopped = #plays, #stops
panel.AutoPlayAccept:SetChecked(false)
panel.AutoPlayAccept.scripts.OnClick(panel.AutoPlayAccept)
assert(#plays == count and #stops == stopped, 'turning autoplay off preserves current audio')
event('ADDON_LOADED')
WV:RefreshHeadOptions()
assert(panel.AutoPlayAccept:GetChecked() == false)
questID = 490 -- Supplemental descriptions obey the same preference.
event('QUEST_DETAIL')
assert(#plays == count and #stops == stopped)
WV:Silence()
assert(WV:ReplayQuest(490))
assert(plays[#plays].file:find('CatQuest_Voices\\Sounds\\q\\490.ogg',1,true))
print('PASS: descriptions default on, one-time default migration, persistent opt-out, ten silent accepts preserve replay data, manual playback and unchanged progress/completion')

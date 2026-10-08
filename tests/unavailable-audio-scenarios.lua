event('ADDON_LOADED')
local WV=WowVoice
QuestObjectiveTracker=CreateFrame('Frame',nil,UIParent)
local tracker=QuestObjectiveTracker
local block=CreateFrame('Frame',nil,tracker)
block.id=179
block.HeaderText=block:CreateFontString(nil,'ARTWORK','QuestTitleFont')
tracker.usedBlocks={QuestTemplate={block}}
function tracker:Update() end
function tracker:FreeBlock() end
local events=frames.WowVoiceTrackerEvents
events.scripts.OnEvent(events,'ADDON_LOADED')
local trackerPlay
for _,f in ipairs(allFrames) do if f.parent==block and f.Icon then trackerPlay=f end end
assert(trackerPlay and trackerPlay.visible)

QuestScrollFrame=CreateFrame('Frame')
local row=CreateFrame('Frame',nil,QuestScrollFrame)
row.questID=179
row.Checkbox=CreateFrame('Frame',nil,row)
row.Checkbox:SetPoint('TOPRIGHT',row,'TOPRIGHT',-4,-8)
QuestScrollFrame.titleFramePool={EnumerateActive=function()
    local yielded=false
    return function() if not yielded then yielded=true; return row end end
end}
QuestMapFrame=CreateFrame('Frame')
QuestMapFrame.DetailsFrame=CreateFrame('Frame',nil,QuestMapFrame)
QuestMapFrame.DetailsFrame.questID=179
WV:RefreshJournalButtons()
local journalPlay,detailsPlay
for _,f in ipairs(allFrames) do
    if f.questOwner==row then journalPlay=f end
    if f.questOwner==QuestMapFrame.DetailsFrame then detailsPlay=f end
end
assert(journalPlay.visible and detailsPlay.visible)
WV:ToggleHeadPreview()
assert(trackerPlay.ProgressGlow.visible)
soundOK=false
trackerPlay.scripts.OnClick(trackerPlay)
assert(not WV:HasQuestAudio(179) and WV:HasQuestAudio(192))
assert(not trackerPlay.visible and not trackerPlay.ProgressGlow.visible)
assert(not journalPlay.visible and not detailsPlay.visible, 'failure hides all controls immediately')
assert(row.Checkbox.points[1][4]==-4, 'failure restores journal spacing')
tracker:Update(); WV:RefreshJournalButtons()
assert(not trackerPlay.visible and not journalPlay.visible, 'UI refresh cannot restore failed recording')
local count=#plays
assert(not WV:ReplayQuest(179) and #plays==count, 'known failure is not retried by hidden controls')
assert(not (TalkingHeadRuDB.listenedQuests and TalkingHeadRuDB.listenedQuests[playerGUID]
    and TalkingHeadRuDB.listenedQuests[playerGUID][179]), 'failed playback is not marked as heard')
restored('1','0.37')

-- Runtime failures are transient. A successful NPC playback can also recover
-- without reload, and failed turn-in audio must not hide a working description.
soundOK=true
questID=179
event('QUEST_DETAIL')
assert(WV:HasQuestAudio(179) and trackerPlay.visible and journalPlay.visible and detailsPlay.visible)
WV:Silence()
soundOK=false
event('QUEST_COMPLETE')
assert(WV:HasQuestAudio(179) and trackerPlay.visible and journalPlay.visible)
WV:Silence()
event('QUEST_DETAIL')
assert(not WV:HasQuestAudio(179) and not trackerPlay.visible and not journalPlay.visible,
    'automatic description failures hide controls too')
assert(not WV:HasQuestAudio(999999), 'quests outside the audio library never show controls')
print('PASS: failed audio hides journal/details/tracker controls and glow, preserves other quests, supports automatic recovery')

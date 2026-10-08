event('ADDON_LOADED')
local WV=WowVoice
assert(TalkingHeadRuDB.autoPlayTurnIn==true, 'turn-in autoplay defaults on')
command('options')
local panel=frames.WowVoiceOptionsPanel
assert(panel.AutoPlayTurnIn:GetChecked()==true)

-- Exercise the actual control, including updating an existing saved database.
TalkingHeadRuDB.autoPlayTurnIn=nil
event('ADDON_LOADED')
assert(TalkingHeadRuDB.autoPlayTurnIn==true)
panel.AutoPlayTurnIn:SetChecked(false)
panel.AutoPlayTurnIn.scripts.OnClick(panel.AutoPlayTurnIn)
assert(TalkingHeadRuDB.autoPlayTurnIn==false and TalkingHeadRuDB.autoPlayAccept==true)
event('ADDON_LOADED')
WV:RefreshHeadOptions()
assert(panel.AutoPlayTurnIn:GetChecked()==false, 'opt-out survives initialization')

-- Multiple progress stages followed by the reward page all stay silent.
for _,id in ipairs({179,861,3911}) do
    questID=id
    for _,name in ipairs({'QUEST_PROGRESS','QUEST_PROGRESS','QUEST_COMPLETE','QUEST_COMPLETE'}) do
        event(name)
    end
end
assert(#plays==0 and #stops==0)
assert(not frames.TalkingHeadRu or not frames.TalkingHeadRu:IsShown())
restored('1','0.37')

-- Acceptance stays automatic and turn-in events do not replace active audio.
questID=179
event('QUEST_DETAIL')
assert(#plays==1 and plays[1].file:find('179a.ogg',1,true))
local count,stopped,key=#plays,#stops,WV.lastKey
event('QUEST_PROGRESS'); event('QUEST_COMPLETE')
assert(#plays==count and #stops==stopped and WV.lastKey==key)
WV:Silence()

-- Both toggles can be off while journal/tracker replay remains available.
WV:SetAutoPlayAcceptEnabled(false)
count=#plays
event('QUEST_DETAIL'); event('QUEST_PROGRESS'); event('QUEST_COMPLETE')
assert(#plays==count)
assert(WV:ReplayQuest(179) and WV:ReplayQuest(3911))
assert(plays[#plays].file:find('CatQuest_Voices\\Sounds\\q\\3911.ogg',1,true))
WV:Silence()

-- Re-enable turn-in only: both Classic stages and supplemental completion work.
count,stopped=#plays,#stops
panel.AutoPlayTurnIn:SetChecked(true)
panel.AutoPlayTurnIn.scripts.OnClick(panel.AutoPlayTurnIn)
assert(#plays==count and #stops==stopped and TalkingHeadRuDB.autoPlayAccept==false)
event('ADDON_LOADED')
WV:RefreshHeadOptions()
assert(panel.AutoPlayTurnIn:GetChecked()==true)
questID=179
event('QUEST_DETAIL'); assert(#plays==count)
for _,entry in ipairs({{'QUEST_PROGRESS','179p.ogg'},{'QUEST_COMPLETE','179c.ogg'}}) do
    event(entry[1])
    assert(plays[#plays].file:find(entry[2],1,true))
    WV:Silence() -- Check each source in isolation; busy-player ordering is covered by the queue scenarios.
end
questID=3911
event('QUEST_COMPLETE')
assert(plays[#plays].file:find('CatQuest_Voices\\Sounds\\q\\3911_t.ogg',1,true))
count,stopped=#plays,#stops
WV:SetAutoPlayTurnInEnabled(false)
event('QUEST_PROGRESS'); event('QUEST_COMPLETE')
assert(#plays==count and #stops==stopped, 'disabling prevents new lines without interrupting current audio')
print('PASS: turn-in default/persistence, all progress/completion stages muted, independent acceptance, manual replay, Classic and supplemental playback')

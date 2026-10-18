event('ADDON_LOADED')
local WV,R,C=WowVoice,TalkingHeadRuVoiceRanking,TalkingHeadRuRankingCodec
local function order(value) return table.concat(value,',') end
assert(WV:GetVoiceSelectionMode()=='ranking','Fresh install should use race/sex ranking')
assert(TalkingHeadRuDB.voiceRankingDefaultApplied,'Fresh install did not record default migration')
event('ADDON_LOADED')
assert(WV:GetVoiceSelectionMode()=='ranking','Saved ranking mode changed on reload')
assert(WV:SetVoiceSelectionMode('manual'))
event('ADDON_LOADED')
assert(WV:GetVoiceSelectionMode()=='manual','Saved manual mode changed on reload')
-- The first upgrade switches even a saved mode from an earlier development
-- build, but retains the actual library orders, snapshot and other settings.
local migratedSettings=TalkingHeadRuDB
for _,oldMode in ipairs({false,'manual','ranking'}) do
    local priority={'wayfarer','catquest','wowvoice'}
    local private={['npc:dwarf:male']={'catquest','wowvoice','wayfarer'}}
    local imported={json='saved snapshot',sha256='saved checksum'}
    TalkingHeadRuDB={voiceSelectionMode=oldMode or nil,voicePriority=priority,
        voiceGroupOrders=private,voiceRanking=imported,volume=0.6,showVoiceSource=true}
    event('ADDON_LOADED')
    assert(WV:GetVoiceSelectionMode()=='ranking','First upgrade must enable race/sex ranking')
    assert(TalkingHeadRuDB.voiceRankingDefaultApplied,'Upgrade did not record default migration')
    assert(order(WV:GetVoicePriority())==order(priority),'Migration changed the global library order')
    assert(TalkingHeadRuDB.voiceGroupOrders==private and TalkingHeadRuDB.voiceRanking==imported,
        'Migration replaced personal orders or the imported snapshot')
    assert(TalkingHeadRuDB.volume==0.6 and TalkingHeadRuDB.showVoiceSource==true)
    assert(WV:SetVoiceSelectionMode('manual'))
    event('ADDON_LOADED')
    assert(WV:GetVoiceSelectionMode()=='manual','Later loads repeated the default migration')
end
TalkingHeadRuDB=migratedSettings
event('ADDON_LOADED')
assert(WV:GetVoiceSelectionMode()=='manual','Previously migrated user choice changed')
local builtin,_,builtinOrigin=R.Current()
assert(builtin and builtin.generatedAt=='2026-10-17T10:00:00Z' and builtinOrigin=='builtin',
    'Import scenarios must use the controlled builtin fixture')
local manual={'wayfarer','wowvoice','catquest'}
assert(WV:SetVoicePriority(manual))
assert(R.Import(rankingFixture_valid))
assert(WV:GetVoiceSelectionMode()=='manual' and order(WV:GetQuestVoicePriority(179,'a'))==order(manual))
local saved=TalkingHeadRuDB.voiceRanking
assert(R.Import(rankingFixture_valid) and TalkingHeadRuDB.voiceRanking==saved,'Duplicate import changed record')
local ok,reason=R.Import(rankingFixture_older); assert(not ok and reason=='older' and TalkingHeadRuDB.voiceRanking==saved)
assert(not R.Import(rankingFixture_older,true),'Legacy force flag downgraded snapshot')
assert(WV:SetVoiceSelectionMode('ranking'))
assert(order(WV:GetQuestVoicePriority(179,'a'))=='catquest,wayfarer,wowvoice')
assert(R.Import(rankingFixture_noTie))
assert(order(WV:GetQuestVoicePriority(179,'a'))=='catquest,wowvoice,wayfarer')
assert(R.Import(rankingFixture_legacy))
assert(order(WV:GetQuestVoicePriority(179,'a'))=='catquest,wowvoice,wayfarer','Legacy ranks invented a tie')
assert(R.Import(rankingFixture_allTied))
assert(order(WV:GetQuestVoicePriority(179,'a'))==order(manual))
assert(R.Import(rankingFixture_noData))
assert(order(WV:GetQuestVoicePriority(179,'a'))==order(manual),'Unrated group ignored user order')
local unrated=R.Current().groups[1]
local copied=R.Order(unrated,manual)
copied[1]='catquest'
assert(manual[1]=='wayfarer' and unrated.ranking[1].source=='WowVoice','Fallback mutated its inputs')
assert(R.SetOverride('npc:dwarf:male',{'catquest','wowvoice','wayfarer'}))
assert(order(WV:GetQuestVoicePriority(179,'a'))=='catquest,wowvoice,wayfarer','Unrated group ignored private order')
R.Reset('npc:dwarf:male')
assert(order(WV:GetQuestVoicePriority(179,'a'))==order(manual),'Reset did not restore global order for unrated group')
assert(order(R.Order(nil,manual))==order(manual),'Missing snapshot/group ignored user order')
assert(order(R.Order(nil,nil))=='wowvoice,catquest,wayfarer','Missing preferences lost default order')
assert(R.Import(rankingFixture_partial))
assert(order(WV:GetQuestVoicePriority(179,'a'))=='wowvoice,catquest,wayfarer','Fallback moved above observed sources')
assert(R.Import(rankingFixture_unknownRace)); assert(R.Current().groups[1].race=='future_race')
assert(order(WV:GetQuestVoicePriority(179,'a'))==order(manual))
assert(R.Import(rankingFixture_narrator)); assert(R.Current().groups[1].speakerType=='narrator')
assert(R.Import(rankingFixture_valid))
local database=TalkingHeadRuSpeakers
TalkingHeadRuSpeakers={schemaVersion=1,givers={[1]={npcID=11}},finishers={[1]={npcID=12}},npcs={
    [11]={race='dwarf',sex='male'},[12]={race='human',sex='female'},[13]={race='dwarf',sex='male'}}}
assert(R.GroupKey(1,'a')=='npc:dwarf:male')
assert(R.GroupKey(1,'c')=='npc:human:female' and R.GroupKey(1,'p')=='npc:human:female')
assert(order(WV:GetQuestVoicePriority(1,'a'))=='catquest,wayfarer,wowvoice')
assert(order(WV:GetQuestVoicePriority(1,'c'))==order(manual))
assert(order(WV:GetQuestVoicePriority(1,'c',{speaker={npcID=13}}))=='catquest,wayfarer,wowvoice')
assert(not R.GroupKey(1,'a',{speaker={npcID=99}}),'Unknown captured speaker inherited indexed race')
assert(not R.GroupKey(1,'a',{speaker={itemID=2}}))
assert(not R.GroupKey(1,'a',{speaker={objectID=2}}))
assert(R.GroupKey(1,'a',{speaker={narrator=true}})=='narrator')
TalkingHeadRuSpeakers=database
local resolve,classic=WowVoiceAudioSources.Resolve,WV.ClassicSoundPath
local available={wayfarer=true,wowvoice=true}
WowVoiceAudioSources.Resolve=function(id,section,source)
    if available[source] then return {path=source,duration=1,sourceID=source,verified=true} end
end
WV.ClassicSoundPath=function() if available.wowvoice then return 'wowvoice',1 end end
assert(WV:SoundPath(179,'a')=='wayfarer','Unavailable winner did not fall through tied user order')
available.wayfarer=false; assert(WV:SoundPath(179,'a')=='wowvoice')
available.wowvoice=false; assert(WV:SoundPath(179,'a')==nil)
WowVoiceAudioSources.Resolve,WV.ClassicSoundPath=resolve,classic
assert(order(WV:GetVoicePriority())==order(manual),'Ranking overwrote manual preferences')
command('options')
local options=frames.WowVoiceOptionsPanel
options:SetSize(720,800)
assert(options.VoiceModes.ranking:GetChecked())
local sharedHelp=options.SharedVoiceTooltip.message
options.VoiceModes.manual.scripts.OnClick()
assert(not options.Buttons.voiceRanking:IsEnabled(),'Manual mode left group settings enabled')
options.Buttons.voiceRanking.scripts.OnClick()
assert(options.Scroll:IsShown(),'Disabled group settings opened in manual mode')
assert(options.SharedVoiceTooltip.message==sharedHelp,'Help changed with the selected mode')
options.VoiceModes.ranking.scripts.OnClick()
assert(options.Buttons.voiceRanking:IsEnabled() and options.SharedVoiceTooltip.message==sharedHelp)
options.Buttons.voiceRanking.scripts.OnClick()
local view=frames.TalkingHeadRuRankingView
assert(view and view:IsShown() and not options.Scroll:IsShown())
local originalDate=date
date=function(format,epoch)
    assert(format=='%d.%m.%Y, %H:%M:%S' and epoch==1792317600)
    return '18.10.2026, 13:00:00'
end
WV:RefreshVoiceRankingView()
assert(view.Summary:GetText()=='Ваш снимок: 18.10.2026, 13:00:00  |  Групп: 1','Snapshot header must use local time')
assert(R.Current().generatedAt=='2026-10-18T10:00:00Z','Display formatting changed the stored UTC timestamp')
date=originalDate
assert(#view.Rows>=1 and view.Rows[1].Sources[1]:GetText()=='CatQuest')
local originalPortrait=SetPortraitTextureFromCreatureDisplayID
local portraitCalls=0
SetPortraitTextureFromCreatureDisplayID=function(texture,display)
    portraitCalls=portraitCalls+1; texture.displayID=display
end
assert(portraitCalls==0 and WV.Work.jobs['voice-ranking-portraits'],'Portrait rendering must be deferred until after opening the menu')
local function drainPortraits()
    for i=1,100 do
        if not WV.Work.jobs['voice-ranking-portraits'] then return end
        now=now+0.01
        local update=frames.WowVoiceWorkFrame.scripts.OnUpdate
        assert(update); update()
    end
    error('Portrait job did not finish')
end
drainPortraits()
assert(portraitCalls==1 and view.Rows[1].Portrait.displayID==TalkingHeadRuVoiceGroupPortraits['npc:dwarf:male'].displayID)
WV:RefreshVoiceRankingView(); drainPortraits()
assert(portraitCalls==1,'Refreshing a ranking must reuse the static portrait')
view.Back.scripts.OnClick(); WV:OpenVoiceRanking(); drainPortraits()
assert(portraitCalls==1,'Reopening the table must reuse the portrait')
SetPortraitTextureFromCreatureDisplayID=originalPortrait
assert(R.Import(rankingFixture_unknownRace))
WV:RefreshVoiceRankingView()
assert(view.Summary:GetText():find('Групп: 0',1,true),'Unknown imported group was counted in the table')
for _,row in ipairs(view.Rows) do assert(not row:IsShown(),'Group without NPCs remained visible') end
assert(R.Current().groups[1].race=='future_race','Filtering the view must not rewrite the imported snapshot')
-- A known ambient NPC alone cannot create a useful quest ranking category.
TalkingHeadRuSpeakers.npcs[987654]={race='future_race',sex='male'}
WV:RefreshVoiceRankingView()
assert(view.Summary:GetText():find('Групп: 0',1,true),'NPC without quest roles created an empty category')
TalkingHeadRuSpeakers.finishers[987654]={npcID=987654}
WV:RefreshVoiceRankingView()
assert(view.Summary:GetText():find('Групп: 1',1,true),'Completion-only group must remain configurable')
TalkingHeadRuSpeakers.npcs[987654]=nil
TalkingHeadRuSpeakers.finishers[987654]=nil
assert(R.Import(rankingFixture_valid))
WV:RefreshVoiceRankingView()
-- The table shows actual playback order, including global manual mode.
local permutations={
    {'wowvoice','catquest','wayfarer'},{'wowvoice','wayfarer','catquest'},
    {'catquest','wowvoice','wayfarer'},{'catquest','wayfarer','wowvoice'},
    {'wayfarer','wowvoice','catquest'},{'wayfarer','catquest','wowvoice'},
}
assert(R.Import(rankingFixture_noData))
for _,preference in ipairs(permutations) do
    assert(WV:SetVoicePriority(preference))
    WV:RefreshVoiceRankingView()
    assert(order(WV:GetQuestVoicePriority(179,'a'))==order(preference),'Unrated playback order did not update')
    local names={wowvoice='WowVoice',catquest='CatQuest',wayfarer='Wayfarer'}
    for i,id in ipairs(preference) do
        assert(view.Rows[1].Sources[i]:GetText()==names[id],'Unrated table order differs from playback')
    end
end
assert(R.Import(rankingFixture_valid))
for _,mode in ipairs({'manual','ranking'}) do
    assert(WV:SetVoiceSelectionMode(mode))
    for _,preference in ipairs(permutations) do
        view.Back.scripts.OnClick()
        assert(WV:SetVoicePriority(preference))
        WV:OpenVoiceRanking()
        local expected={}
        for _,id in ipairs(preference) do
            if id~='catquest' then expected[#expected+1]=id=='wowvoice' and 'WowVoice =' or 'Wayfarer =' end
        end
        if mode=='ranking' then
            assert(view.Rows[1].Sources[1]:GetText()=='CatQuest','Preference moved an untied winner')
            assert(view.Rows[1].Sources[2]:GetText()==expected[1] and view.Rows[1].Sources[3]:GetText()==expected[2],
                'Displayed tied places did not follow the saved preference after reopening')
        else
            local names={wowvoice='WowVoice',catquest='CatQuest',wayfarer='Wayfarer'}
            for i,id in ipairs(preference) do assert(view.Rows[1].Sources[i]:GetText()==names[id]) end
        end
    end
end
assert(WV:SetVoicePriority(manual)); assert(WV:SetVoiceSelectionMode('ranking'))
view.ImportButton.scripts.OnClick(); assert(view.Import:IsShown() and not view.List:IsShown())
assert(view.KeepOverrides:GetChecked(),'Import must preserve private orders by default')
assert(R.SetOverride('npc:dwarf:male',{'wowvoice','catquest','wayfarer'}))
local beforeImportOrders=TalkingHeadRuDB.voiceGroupOrders
view.KeepOverrides:SetChecked(false)
view.Input:SetText('invalid'); view.Apply.scripts.OnClick()
assert(view.Message:GetText():find('Не удалось',1,true))
assert(TalkingHeadRuDB.voiceGroupOrders==beforeImportOrders,'Invalid import reset private orders')
view.Input:SetText(rankingFixture_older); view.Apply.scripts.OnClick()
assert(view.Message:GetText():find('более свежий',1,true))
assert(TalkingHeadRuDB.voiceGroupOrders==beforeImportOrders,'Older import reset private orders')
view.Apply.scripts.OnClick(); assert(view.Import:IsShown())
view.Cancel.scripts.OnClick()
assert(TalkingHeadRuDB.voiceGroupOrders==beforeImportOrders,'Cancel reset private orders')
view.ImportButton.scripts.OnClick()
assert(view.KeepOverrides:GetChecked(),'Reopening import must restore the safe default')
view.Input:SetText(rankingFixture_noTie); view.Apply.scripts.OnClick()
assert(not view.Import:IsShown() and TalkingHeadRuDB.voiceGroupOrders==beforeImportOrders,'Checked import did not preserve private orders')
view.ImportButton.scripts.OnClick(); view.KeepOverrides:SetChecked(false)
view.Input:SetText(rankingFixture_valid); view.Apply.scripts.OnClick()
assert(not view.Import:IsShown() and not R.HasOverrides(),'Unchecked import did not reset private orders')
assert(order(WV:GetVoicePriority())==order(manual) and WV:GetVoiceSelectionMode()=='ranking','Import reset global preferences or mode')
assert(R.SetOverride('npc:dwarf:male',{'wowvoice','catquest','wayfarer'}))
local duplicateRecord=TalkingHeadRuDB.voiceRanking
assert(R.Import(rankingFixture_valid,{preserveOverrides=false}))
assert(TalkingHeadRuDB.voiceRanking==duplicateRecord and not R.HasOverrides(),'Duplicate import did not honor explicit reset')
view.Back.scripts.OnClick(); assert(options.Scroll:IsShown() and not view:IsShown())
WV:OpenVoiceRanking(); WV:OpenVoiceComparison()
assert(not view:IsShown() and frames.WowVoiceLocalDebugPanel:IsShown(),'Settings views overlap')
WV:OpenVoiceRanking()
assert(view:IsShown() and not frames.WowVoiceLocalDebugPanel:IsShown(),'Catalogue did not close')
WV:OpenVoiceRanking(); options:Hide(); assert(not view:IsShown() and options.Scroll:IsShown())
-- Simulate a clean installation without an imported snapshot.
TalkingHeadRuDB.voiceRanking=nil
assert(R.Current().generatedAt==builtin.generatedAt and WV:GetVoiceSelectionMode()=='ranking')
assert(order(WV:GetVoicePriority())==order(manual))
assert(WV:SetVoiceSelectionMode('manual'))
assert(R.Import(rankingFixture_valid))

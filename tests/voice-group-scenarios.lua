local WV,R,E,C=WowVoice,TalkingHeadRuVoiceRanking,TalkingHeadRuVoiceGroupExamples,WowVoiceComparison
local function order(value) assert(value,debug.traceback('Missing order')); return table.concat(value,',') end
local key='npc:dwarf:male'
local manual=order(WV:GetVoicePriority())
local private={'wowvoice','wayfarer','catquest'}
local saved=TalkingHeadRuDB.voiceRanking
assert(not R.SetOverride(key,{'wowvoice','wowvoice','catquest'}))
assert(not R.SetOverride('npc:dwarf:unknown',private))
assert(R.SetOverride(key,private))
private[1]='catquest'
assert(order(R.Override(key))=='wowvoice,wayfarer,catquest','Order was not copied')
assert(WV:SetVoiceSelectionMode('ranking'))
assert(order(WV:GetQuestVoicePriority(179,'a'))=='wowvoice,wayfarer,catquest')
assert(WV:SetVoiceSelectionMode('manual'))
assert(order(WV:GetQuestVoicePriority(179,'a'))==manual,'Private order leaked into global manual mode')
assert(R.Import(rankingFixture_noTie))
assert(R.Override(key),'Import erased private order')
assert(R.Import(rankingFixture_valid))

-- An addon upgrade supersedes an old import, with no changes to personal choices.
local originalBuiltin=TalkingHeadRuBuiltinRanking
TalkingHeadRuBuiltinRanking=assert(R.Prepare(rankingFixture_newer))
local snapshot,_,origin=R.Current()
assert(origin=='builtin' and snapshot.generatedAt=='2026-10-19T10:00:00Z')
assert(R.Override(key))
local savedImport=TalkingHeadRuDB.voiceRanking
assert(not R.Import(rankingFixture_valid,{preserveOverrides=false}),'An old duplicate import bypassed the newer builtin snapshot')
assert(R.Override(key),'Rejected duplicate import cleared private orders')
assert(not R.Import(rankingFixture_older,true))
assert(TalkingHeadRuDB.voiceRanking==savedImport)
assert(R.Import(rankingFixture_newer))
local _,_,equalOrigin=R.Current(); assert(equalOrigin=='imported')
R.Reset(key)
assert(not R.Override(key) and R.Current().generatedAt=='2026-10-19T10:00:00Z')
assert(TalkingHeadRuDB.voiceRanking and order(WV:GetVoicePriority())==manual)
TalkingHeadRuBuiltinRanking=originalBuiltin
TalkingHeadRuDB.voiceRanking=nil; assert(R.Import(rankingFixture_valid))
TalkingHeadRuDB.voiceGroupOrders={[key]={'wowvoice','wowvoice','bad'}}
assert(not R.Override(key),'Invalid saved order was used')
R.ResetAll()

-- Synthetic catalog exercises availability, verified speaker filtering and sampling.
local oldAvailable,oldIDs,oldResolve,oldSpeaker=C.SourceAvailable,C.QuestIDs,C.Resolve,WV.GetReplaySpeaker
local oldDatabase=TalkingHeadRuSpeakers
local availability={wowvoice=true,catquest=true,wayfarer=true}
local recordings={
    [101]={wowvoice=true,catquest=true},
    [102]={wowvoice=true,catquest=true,wayfarer=true},
    [103]={wowvoice=true}, -- excluded with two or more installed libraries
    [104]={wowvoice=true,catquest=true},
    [105]={wowvoice=true,catquest=true}, -- a different race
}
C.SourceAvailable=function(source) return availability[source]==true end
C.QuestIDs=function() return {[101]=true,[102]=true,[103]=true,[104]=true,[105]=true} end
C.Resolve=function(id,source)
    if availability[source] and recordings[id] and recordings[id][source] then
        return {path=source..id,duration=5,sourceID=source,text='Текст'}
    end
end
TalkingHeadRuSpeakers={schemaVersion=1,givers={},finishers={},npcs={
    [11]={race='dwarf',sex='male',name='Дворф'},[12]={race='human',sex='male',name='Человек'}}}
WV.GetReplaySpeaker=function(_,id) return {questId=id,section='a',title='Задание '..id,speaker={npcID=id==105 and 12 or 11}} end
local candidates,count=E.Build(key)
assert(count==3 and #candidates==3 and candidates[1].id==102,'First sample must prefer all three libraries')
local bag=E.New(candidates)
local seen={[bag.current.id]=true}
for _=2,#candidates do local next=E.Next(bag); assert(not seen[next.id]); seen[next.id]=true end
for cycle=1,10 do
    local previous=bag.current.id; seen={}
    for _=1,#candidates do
        local next=E.Next(bag); assert(not seen[next.id] and next.id~=previous)
        seen[next.id],previous=true,next.id
    end
end
availability.catquest=false; availability.wayfarer=false
candidates,count=E.Build(key); assert(count==1 and #candidates==4)
availability.wowvoice=false; candidates,count=E.Build(key); assert(count==0 and #candidates==0)
availability.wowvoice=true; availability.catquest=true; availability.wayfarer=true
local savedRecordings=recordings
recordings={[101]={wowvoice=true},[102]={catquest=true},[103]={wayfarer=true}}
candidates,count=E.Build(key); assert(count==3 and #candidates==0,'Disjoint sources became a comparison')
recordings={[101]={wowvoice=true,catquest=true}}
candidates=E.Build(key); assert(#candidates==1)
local singleton=E.New(candidates); assert(E.Next(singleton)==singleton.current)
recordings=savedRecordings

-- Client cache may have no title for a quest the character never accepted.
local titleIDs,titleSpeaker,titleResolve=C.QuestIDs,WV.GetReplaySpeaker,C.Resolve
C.QuestIDs=function() return {[8422]=true} end
WV.GetReplaySpeaker=function() return {questId=8422,speaker={npcID=11},title=''} end
C.Resolve=function(id,source) return {path=source..id,duration=5,sourceID=source} end
local titled=E.Build(key)
assert(titled[1].context.title=='Тролли Пера','Missing client title did not fall back to bundled index')
WV.GetReplaySpeaker=function() return {questId=8422,speaker={npcID=11},title='Название из журнала'} end
assert(E.Build(key)[1].context.title=='Название из журнала','Index replaced a known current title')
local oldLocale=GetLocale
for _,locale in ipairs({'enUS','enGB','ruRU'}) do
    GetLocale=function() return locale end
    WV.GetReplaySpeaker=function() return {questId=8422,speaker={npcID=11},title='Voodoo Feathers'} end
    assert(E.Build(key)[1].context.title=='Тролли Пера','English client title hid a bundled Russian title')
end
GetLocale=oldLocale
C.QuestIDs=function() return {[987654]=true} end
WV.GetReplaySpeaker=function() return {questId=987654,speaker={npcID=11},title='Untranslated Forever Quest'} end
assert(E.Build(key)[1].context.title=='Untranslated Forever Quest','Missing Russian translation must retain the English title')
C.QuestIDs,WV.GetReplaySpeaker,C.Resolve=titleIDs,titleSpeaker,titleResolve

-- Navigate, play, reorder and reset through the actual view.
WV:SetVoiceSelectionMode('ranking'); WV:OpenVoiceRanking()
frames.WowVoiceOptionsPanel:SetPoint('CENTER',UIParent,'CENTER',0,0)
local view=frames.TalkingHeadRuRankingView
local function drainExamples()
    for i=1,20000 do
        if not WV.Work.jobs['voice-group-examples'] then return end
        local update=frames.WowVoiceWorkFrame.scripts.OnUpdate
        assert(update,'Pending example job has no scheduler')
        update()
    end
    error('Example scan did not finish')
end
-- Enter the page immediately; expensive work starts only in later frames.
local cpu,reads,enumerations=0,0,0
local savedProfile,savedIDs,savedSpeaker,savedResolve=debugprofilestop,C.QuestIDs,WV.GetReplaySpeaker,C.Resolve
debugprofilestop=function() return cpu end
C.QuestIDs=function(checkpoint)
    local ids={}
    for i=1,2000 do ids[i]=true; enumerations=enumerations+1; cpu=cpu+0.001; checkpoint() end
    return ids
end
WV.GetReplaySpeaker=function(self,id,snapshot)
    assert(snapshot,'Examples did not share a speaker snapshot')
    reads=reads+1; cpu=cpu+0.35
    return savedSpeaker(self,id,snapshot)
end
C.Resolve=function(id,source) return {path=source..id,duration=5,sourceID=source} end
view.Rows[1].Open.scripts.OnClick()
assert(reads==0 and enumerations==0 and view.Group.Body.loading and view.Group.Body.Loading:IsShown())
assert(not view.Group.Body.Players.wowvoice:IsEnabled())
local framesUsed=0
while WV.Work.jobs['voice-group-examples'] do
    local started=cpu
    frames.WowVoiceWorkFrame.scripts.OnUpdate()
    assert(cpu-started<=WV.Work.budgetMS+0.001,'Example scan exceeded shared frame budget')
    framesUsed=framesUsed+1; assert(framesUsed<10000)
end
assert(reads==2000 and framesUsed>1 and not view.Group.Body.Loading:IsShown())
assert(#view.Group.Body.samples.candidates==1999 and view.Group.Body.samples.current.id==1)
for i=2,#view.Group.Body.samples.candidates do
    assert(view.Group.Body.samples.candidates[i-1].id<view.Group.Body.samples.candidates[i].id,'Incremental sort lost ordering')
end
C.QuestIDs,WV.GetReplaySpeaker,debugprofilestop,C.Resolve=savedIDs,savedSpeaker,savedProfile,savedResolve
-- The shared portrait snapshot scans inventory once, not once per candidate.
local savedBags,savedBagCount=C_Container,NUM_TOTAL_EQUIPPED_BAG_SLOTS
local bagReads=0
NUM_TOTAL_EQUIPPED_BAG_SLOTS=0
C_Container={
    GetContainerNumSlots=function() return 20 end,
    GetContainerItemQuestInfo=function() bagReads=bagReads+1 end,
    GetContainerItemInfo=function() end,
}
local snapshot=WV:BuildReplaySpeakerSnapshot()
for id=1,100 do oldSpeaker(WV,id,snapshot) end
assert(bagReads==20,'Replay lookup repeated the inventory scan')
C_Container,NUM_TOTAL_EQUIPPED_BAG_SLOTS=savedBags,savedBagCount
view.Back.scripts.OnClick()
view.Rows[1].Open.scripts.OnClick()
assert(WV.Work.jobs['voice-group-examples'])
view.Back.scripts.OnClick()
assert(not WV.Work.jobs['voice-group-examples'] and not view.Group.Body.Loading:IsShown(),'Closed page kept its job')
-- An obsolete request cannot replace the page opened next.
view.Group:Open({speakerType='npc',race='human',sex='female'},'Другая группа')
view.Group:Open(view.Rows[1].group,'Дворф')
drainExamples()
assert(view.Group.Body.samples.current.id==102)
view.Back.scripts.OnClick()
local resolveBeforeError=C.Resolve
C.Resolve=function() error('synthetic example failure') end
view.Rows[1].Open.scripts.OnClick(); drainExamples()
assert(view.Group.Body.loadError and not view.Group.Body.Loading:IsShown(),'Failed request left spinner running')
C.Resolve=resolveBeforeError
view.Back.scripts.OnClick()
view.Rows[1].Open.scripts.OnClick(); drainExamples()
local detail=view.Group.Body
assert(view.Group:IsShown() and not view.List:IsShown())
assert(view.Title:GetText()=='Дворф — Мужской' and not detail.Origin and not detail.Stop)
assert(detail.samples.current.id==102 and detail.Players.wowvoice:IsEnabled())
assert(detail.Dice:IsEnabled())
local first=detail.samples.current.id
detail.Dice.scripts.OnClick(); assert(detail.samples.current.id~=first)
local oldPlay=WV.Playback.Play
local plays=0
WV.Playback.Play=function(self) self.previewOwner=nil; plays=plays+1; return true end
detail.Players.catquest.scripts.OnClick()
assert(plays==1 and WV.Playback.previewOwner==view.Group)
local oldStop=WV.Playback.Stop
local stops=0
WV.Playback.Stop=function(self) self.previewOwner=nil; stops=stops+1 end
view.Back.scripts.OnClick()
assert(stops==1 and not view.Group:IsShown() and view.List:IsShown())
assert(view.Title:GetText()=='Озвучка по расе и полу')
view.Rows[1].Open.scripts.OnClick(); drainExamples(); detail.Players.wowvoice.scripts.OnClick()
WV.Playback.previewOwner={} -- unrelated playback took over
view.Back.scripts.OnClick(); assert(stops==1,'Navigation stopped unrelated playback')
WV.Playback.Play,WV.Playback.Stop=oldPlay,oldStop
assert(WV:PreviewQuestAudio(102,'group-preview',5,'Текст','wowvoice',true,view.Group))
assert(WV.Playback.previewOwner==view.Group)
assert(WV.Playback:Play('ordinary-quest',5,{questId=102,section='a'},'wowvoice',true))
assert(WV.Playback.previewOwner==nil,'Normal playback retained preview ownership')
WV.Playback:Stop('test complete')
view.Rows[1].Open.scripts.OnClick(); drainExamples()
local oldCursor,oldDown=GetCursorPosition,IsMouseButtonDown
local dragX,dragY=detail.Cards[1]:GetCenter()
assert(dragX and dragY,'Group cards have no screen position')
GetCursorPosition=function() return dragX,dragY end
IsMouseButtonDown=function() return true end
detail.Cards[1].scripts.OnMouseDown(detail.Cards[1],'LeftButton')
dragX,dragY=detail.Cards[3]:GetCenter()
detail.Cards[1].scripts.OnMouseUp(detail.Cards[1],'LeftButton')
assert(order(R.Override(key))=='wayfarer,wowvoice,catquest','Drag did not move first library to third')
assert(not detail.loading and not WV.Work.jobs['voice-group-examples'],'Preference edit restarted catalog scan')
GetCursorPosition,IsMouseButtonDown=oldCursor,oldDown
assert(detail.Reset:IsEnabled())
detail.Reset.scripts.OnClick()
assert(not R.Override(key) and TalkingHeadRuDB.voiceRanking,'Group reset erased ranking')
-- Navigating away mid-drag cancels it even if a late mouse-up arrives.
GetCursorPosition=function() return detail.Cards[1]:GetCenter() end
IsMouseButtonDown=function() return true end
detail.Cards[1].scripts.OnMouseDown(detail.Cards[1],'LeftButton')
view.Back.scripts.OnClick()
GetCursorPosition=function() return detail.Cards[3]:GetCenter() end
detail.Cards[1].scripts.OnMouseUp(detail.Cards[1],'LeftButton')
assert(not R.Override(key),'Late drag event changed a closed group')
GetCursorPosition,IsMouseButtonDown=oldCursor,oldDown
view.Rows[1].Open.scripts.OnClick(); drainExamples()
assert(R.SetOverride(key,{'wayfarer','catquest','wowvoice'}))
assert(R.SetOverride('npc:human:female',{'catquest','wowvoice','wayfarer'}))
view.Back.scripts.OnClick(); view.ResetButton.scripts.OnClick()
assert(view.Confirm:IsShown() and R.HasOverrides(),'Reset ran before confirmation')
view.Confirm.Cancel.scripts.OnClick(); assert(R.HasOverrides())
view.ResetButton.scripts.OnClick(); view.Confirm.Apply.scripts.OnClick()
assert(not R.HasOverrides() and TalkingHeadRuDB.voiceRanking and order(WV:GetVoicePriority())==manual)
availability.catquest=false; availability.wayfarer=false; WV:RefreshAudioSources()
view.Rows[1].Open.scripts.OnClick(); drainExamples()
assert(detail.Hint:GetText():find('ещё одну',1,true) and detail.Players.wowvoice:IsEnabled())
assert(not detail.Players.catquest:IsEnabled())
availability.wowvoice=false; WV:RefreshAudioSources(); drainExamples()
assert(not detail.Dice:IsEnabled() and not detail.Players.wowvoice:IsEnabled())
assert(detail.Cards[1]:IsShown(),'Empty catalog disabled order editing')
WV:CloseVoiceRanking()
C.SourceAvailable,C.QuestIDs,C.Resolve,WV.GetReplaySpeaker=oldAvailable,oldIDs,oldResolve,oldSpeaker
TalkingHeadRuSpeakers=oldDatabase
WV:SetVoiceSelectionMode('manual')

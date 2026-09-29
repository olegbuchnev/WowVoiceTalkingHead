event('ADDON_LOADED')
WowVoiceDB.autoPlayAccept = true
event('PLAYER_LOGIN')
local WV=WowVoice
local description=string.rep('A long description with words and spaces. ',80)
GetQuestText=function() return description end
event('QUEST_DETAIL')
local head=frames.WowVoiceTalkingHead
assert(head.Body.text==description and head.textRange>0)
assert(head.TextScroll.scroll==0)
local started=now
local duration=WowVoiceDur['179a']
local first=head.scrollPlan[1]
local last=head.scrollPlan[#head.scrollPlan]
now=started+first.start*.5; head.scripts.OnUpdate()
assert(head.TextScroll.scroll==0,'first lines must be held')
now=started+(first.start+first.finish)*.5; head.scripts.OnUpdate()
assert(math.abs(head.TextScroll.scroll-first.to*.5)<.001)
local halfway=head.TextScroll.scroll
local sounds=#plays
command('options'); frames.WowVoiceOptionsPanel:Hide()
assert(head.TextScroll.scroll==halfway and #plays==sounds,'opening options preserves speech time and scroll')
now=started+(last.finish+duration)*.5; head.scripts.OnUpdate()
assert(head.TextScroll.scroll==head.textRange,'last lines must be held')
portraitEvent('QUEST_ACCEPTED',179)
assert(questCache()[179].description==description)
WV:Silence()
GetQuestText=function() error('Replay must not read open NPC window') end
assert(WV:ReplayQuest(179))
assert(head.Body.text==description and head.TextScroll.scroll==0)
print('PASS: exact quest text, initial/final holds, midpoint scrolling, options preserve position, replay restarts text')

-- Fresh text for each section, never overwrite accepted description with turn-in text.
GetProgressText=function() return 'Short progress text.' end
GetRewardText=function() return 'Reward text.' end
event('QUEST_PROGRESS')
assert(head.Body.text=='Short progress text.' and head.textRange==0 and head.TextScroll.scroll==0)
now=now+2; head.scripts.OnUpdate(); assert(head.TextScroll.scroll==0)
event('QUEST_COMPLETE')
assert(head.Body.text=='Reward text.' and questCache()[179].description==description)
WV:Silence()
-- Existing accepted quest, cached before subtitles existed: use exact journal index.
questCache()[179].description=nil
local expectedID=179
C_QuestLog.GetLogIndexForQuestID=function(id) assert(id==expectedID); return 7 end
GetQuestLogQuestText=function(index) assert(index==7); return 'Description from journal','Objectives are not description' end
WV:ReplayQuest(179)
assert(head.Body.text=='Description from journal')
WV:Silence()
expectedID=861
WV:ReplayQuest(861)
assert(head.Body.text=='Description from journal' and head.Name.text=='Скорн Белое Облако')
assert(head.Model.creatureID==3052)
WV:Silence()
C_QuestLog.GetLogIndexForQuestID=function() return nil end
GetQuestLogQuestText=function() error('Never read selected quest with nil index') end
WV:ReplayQuest(861)
assert(head.Body.text==WowVoiceAudioSources.Text(861,'a'), 'missing journal text must use bundled transcript')
assert(not questCache()[861] or not questCache()[861].description, 'fallback must not be saved as game text')
WV:Silence()
local transcript=WowVoiceCatQuestTexts.entries['861a']
WowVoiceCatQuestTexts.entries['861a']=nil
WV:ReplayQuest(861)
assert(head.Body.text=='Текст задания недоступен.' and head.TextScroll.scroll==0)
WowVoiceCatQuestTexts.entries['861a']=transcript
WV:Silence()
print('PASS: independent a/p/c text, short text stays still, old quests read exact journal index, missing text clears previous text')

-- Unknown duration cannot produce invented synchronization.
GetQuestText=function() return description end
questID=999999; event('QUEST_DETAIL')
assert(head.textRange>0)
now=now+20; head.scripts.OnUpdate()
assert(head.TextScroll.scroll==0)
WV:Silence()
restored('1','0.37')

-- Native Settings page, retained geometry, centering and screen bounds.
sounds=#plays
command('options'); command('options')
local panel=frames.WowVoiceOptionsPanel
local anchor=frames.WowVoiceTalkingHeadAnchor
assert(panel.visible and #settingsCategories==1 and settingsCategories[1].name=='WowVoice TalkingHead')
assert(panel.Presets==nil and panel.Enabled==nil)
local function fill(width,height,scale,x,y)
    return WV:ApplyHeadSettings({width=width,height=height,scale=scale/100,x=x,y=y})
end
assert(head.RetailBackground.visible)
assert(panel.Fields==nil and panel.Buttons.apply==nil)
fill(520,260,125,125.5,-250.25)
local p=WowVoiceDB.headPosition
assert(p[1]=='CENTER' and p[2]=='CENTER' and p[3]==125.5 and p[4]==-250.25)
assert(head.width==520 and head.height==260 and head.scale==1.25)
assert(anchor.width==650 and anchor.height==325)
assert(head.TextScroll.width==326 and head.TextScroll.height==195)
panel.Buttons.center.scripts.OnClick()
assert(WowVoiceDB.headPosition[3]==0 and WowVoiceDB.headPosition[4]==-250.25)
local unchanged=WowVoiceDB.headPosition
for _,bad in ipairs({'bad','',math.huge}) do
    assert(not fill(520,260,125,bad,0))
    assert(WowVoiceDB.headPosition==unchanged)
end
assert(not fill(520,260,10,0,0))
assert(WowVoiceDB.headPosition==unchanged and head.scale==1.25)
assert(not fill(1000,600,200,0,0))
assert(WowVoiceDB.headPosition==unchanged,'oversized panel must be rejected')
fill(520,260,125,999999,-999999)
assert(WowVoiceDB.headPosition[3]==(1920-anchor.width)/2)
assert(WowVoiceDB.headPosition[4]==-(1080-anchor.height)/2)
fill(520,260,125,125.5,-250.25)
panel.Buttons.reset.scripts.OnClick()
assert(WowVoiceDB.headPosition==nil and anchor.points[1][1]=='BOTTOM')
assert(head.width==520 and head.height==260 and head.scale==1.25, 'position reset preserves size')
WV:ResetHeadSettings()
print('PASS: native Settings category, legacy geometry, centering, validation and screen bounds')

-- Preview uses the player model, scrolls on a loop, and is the only draggable mode.
local beforeStops=#stops
panel.Buttons.test.scripts.OnClick()
assert(head.visible and head.Model.unit=='player' and head.Model.displayID==98765)
assert(head.Name.text=='Тестовый персонаж' and head.mouseEnabled)
assert(head.textRange>0)
now=now+15; head.scripts.OnUpdate()
assert(head.TextScroll.scroll>0)
now=now+16; head.scripts.OnUpdate()
assert(head.TextScroll.scroll==0,'preview loops after 30 seconds')
head.scripts.OnDragStart(head); assert(anchor.moving)
anchor:ClearAllPoints(); anchor:SetPoint('CENTER',UIParent,'CENTER',123,-234)
head.scripts.OnDragStop(head)
assert(not anchor.moving and WowVoiceDB.headPosition[3]==123 and WowVoiceDB.headPosition[4]==-234)
WV:RefreshHeadOptions()
assert(head.visible and head.mouseEnabled and head.Model.unit=='player')
assert(WowVoiceDB.headPosition[3]==123 and WowVoiceDB.headPosition[4]==-234)
assert(#plays==sounds and #stops==beforeStops)
restored('1','0.37')
panel:Hide(); assert(not head.visible and not head.mouseEnabled)
command('options'); panel.Buttons.test.scripts.OnClick(); head.Close.scripts.OnClick()
assert(not head.visible and #stops==beforeStops)
-- Preview can be toggled repeatedly.
panel.Buttons.test.scripts.OnClick(); assert(head.visible)
panel.Buttons.test.scripts.OnClick(); assert(not head.visible)
-- Refreshing and closing the options do not interrupt real voice.
questID=179; event('QUEST_DETAIL')
assert(head.visible and head.mouseEnabled) -- Retail right-click dismissal, no dragging.
head.scripts.OnDragStart(head); assert(not anchor.moving)
local playingSounds=#plays; beforeStops=#stops
assert(#plays==playingSounds and #stops==beforeStops and head.visible and head.mouseEnabled)
now=now+8; head.scripts.OnUpdate()
local scroll, progress = head.TextScroll.scroll, head.Progress.value
WV:RefreshHeadOptions()
head.scripts.OnUpdate()
assert(head.Progress.value==progress and head.TextScroll.scroll==scroll,
    'shared layout preserves playback time and text position when refreshing options')
assert(head.visible and #plays==playingSounds and #stops==beforeStops)
panel:Hide(); assert(head.visible and #stops==beforeStops)
WV:RefreshHeadOptions()
head.scripts.OnUpdate()
assert(head.Progress.value==progress and #plays==playingSounds and #stops==beforeStops)
assert(head.TextScroll.scroll==scroll,'returning to the same layout restores the same text position')
head.Close.scripts.OnClick()
assert(not head.visible and #stops==beforeStops+1,'Retail close must stop audio')
restored('1','0.37')
print('PASS: player preview, looping scroll, drag only in test, close cleanup, options changes preserve real audio')

-- Opening preview replaces real playback.
command('options')
do
    assert(WV:ReplayQuest(179))
    local soundCount,stopCount,handle=#plays,#stops,plays[#plays].handle
    assert(frames.WowVoiceTicker.visible and head.mouseEnabled)
    panel.Buttons.test.scripts.OnClick()
    assert(#plays==soundCount and #stops==stopCount+1 and stops[#stops]==handle,
        'preview must stop the playing sound exactly once without starting another')
    restored('1','0.37')
    assert(not frames.WowVoiceTicker.visible and WV.lastKey==nil,
        'preview must clear the playback timer and allow the same quest to be replayed')
    assert(head.visible and head.mouseEnabled and head.Model.unit=='player'
        and head.Name.text=='Тестовый персонаж')
    head.scripts.OnDragStart(head); assert(anchor.moving)
    head.scripts.OnDragStop(head); assert(not anchor.moving)
    tick(now+WowVoiceDur['179a']+WowVoiceDB.tail+1)
    head.scripts.OnUpdate()
    assert(head.visible and head.mouseEnabled and head.Model.unit=='player',
        'the old playback deadline must not close or replace the preview')
    panel.Buttons.test.scripts.OnClick()
    assert(not head.visible and #stops==stopCount+1 and #plays==soundCount,
        'a second click closes preview without resuming or stopping audio again')
end
print('PASS: preview replaces audible playback, restores Dialog, cancels old timer and remains draggable after replacing playback')

-- Persist geometry, position and description for the separate reload phase.
command('options'); fill(500,140,100,0,-250); panel:Hide()
questID=179; event('QUEST_DETAIL'); portraitEvent('QUEST_ACCEPTED',179); WV:Silence()
savedSubtitle=description

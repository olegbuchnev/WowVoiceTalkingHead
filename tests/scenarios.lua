WowVoiceDB = {debug=true}
event('ADDON_LOADED')
assert(WowVoiceDB.debug==false and WowVoiceDB.ducknpc==true)
print('PASS: previously saved debug=true resets on addon load')
command('debug on'); command('debug on'); assert(WowVoiceDB.debug)
command('diag')
assert(has('бесплатный аудиопак: лицензия не требуется'))
assert(not has('Forever test:') and not has('установка через WowVoice.exe'))
for _,s in ipairs({'70009','16001','WOW_PROJECT_ID=99','C_AddOns=table','GetQuestID=function','GetQuestText=function','GetRewardText=function','StopSound: function','Sound_EnableDialog=1','Sound_DialogVolume=0.37'}) do
    assert(has(s),'missing diagnostic: '..s)
end
for _,item in ipairs({{'QUEST_DETAIL','a'},{'QUEST_PROGRESS','p'},{'QUEST_COMPLETE','c'}}) do
    messages={}
    event(item[1])
    local play=plays[#plays]
    assert(play.file=='Interface\\AddOns\\WowVoiceSounds\\179'..item[2]..'.ogg')
    assert(play.channel=='Master' and play.dialog=='0' and play.volume=='0')
    for _,s in ipairs({'event='..item[1],'questID=179','section='..item[2],'title=Дворфские экипировщики','WowVoiceDur=true','PlaySoundFile: result=true','handle=','Dialog duck:'}) do
        assert(has(s),'missing event diagnostic: '..s)
    end
    local count=#plays
    event(item[1]); assert(#plays==count,'duplicate event restarted audio')
    tick(now+WowVoiceDur['179'..item[2]]+0.051)
    assert(stops[#stops]==play.handle)
    restored('1','0.37')
    assert(has('reason=duration timer') and has('StopSound: done') and has('Dialog restore: done'))
end
print('PASS: all three quest events, Master, duck, durations, duplicate suppression, stop, restore')

questID=861
event('QUEST_COMPLETE')
local count=#stops
tick(now+2)
assert(#stops==count and cvars.Sound_EnableDialog=='0','Classic 861c incorrectly stopped at Midnight duration')
tick(now+22)
assert(#stops==count+1)
restored('1','0.37')
print('PASS: Classic 861c remains active after 2 seconds and stops at Classic duration')

questID=179
cvars.Sound_EnableDialog,cvars.Sound_DialogVolume='0','0.64'
event('QUEST_DETAIL')
local old=plays[#plays].handle
event('QUEST_PROGRESS')
assert(stops[#stops]==old)
command('stop'); restored('0','0.64')
cvars.Sound_EnableDialog,cvars.Sound_DialogVolume='1','0.37'
soundOK=false; messages={}
event('QUEST_DETAIL'); restored('1','0.37')
assert(has('PlaySoundFile: result=false handle=nil') and has('Dialog restore: done'))
soundOK=true; command('stop')
print('PASS: replacement, manual stop, initially disabled Dialog, failed playback restoration')

questID=999999; messages={}
event('QUEST_DETAIL'); assert(has('WowVoiceDur=false') and has('999999a.ogg'))
command('stop')
local original=GetQuestID
GetQuestID=function() error('simulated GetQuestID incompatibility') end
local ok,err=pcall(function() event('QUEST_DETAIL') end)
assert(not ok and err:find('simulated GetQuestID incompatibility',1,true),'debug swallowed quest API error')
GetQuestID=original
local originalText=GetQuestText
GetQuestText=nil
ok,err=pcall(function() event('QUEST_DETAIL') end)
assert(not ok and err:find('GetQuestText',1,true),'text API error hidden')
GetQuestText=originalText
print('PASS: missing duration is visible, incompatible APIs propagate errors in debug mode')

command('debug off'); command('debug off'); assert(not WowVoiceDB.debug)
questID=179; messages={}
event('QUEST_DETAIL'); tick(now+40)
assert(#messages==0,'normal mode produced debug spam')
restored('1','0.37')
print('PASS: idempotent debug on/off, normal mode quiet')

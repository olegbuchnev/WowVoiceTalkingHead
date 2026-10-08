format, gsub, strfind, strsub, strlower = string.format, string.gsub, string.find, string.sub, string.lower
function strtrim(s) return s:match('^%s*(.-)%s*$') end
function strsplit(delim, s, limit)
    local result, start = {}, 1
    while not limit or #result < limit-1 do
        local first, last = s:find(delim, start, true)
        if not first then break end
        result[#result+1], start = s:sub(start,first-1), last+1
    end
    result[#result+1] = s:sub(start)
    return table.unpack(result)
end
now, questID, soundOK, nextHandle = 0, 179, true, 100
serverNow = 1800000000
function GetServerTime() return serverNow end
messages, plays, stops, frames = {}, {}, {}, {}
cvars = {Sound_MasterVolume='1', Sound_EnableDialog='1', Sound_DialogVolume='0.37', Sound_EnableMusic='1', Sound_MusicVolume='0.25', Sound_EnableSoundWhenGameIsInBG='1'}
function GetTime() return now end
function GetCVar(k) return cvars[k] end
function SetCVar(k,v) cvars[k]=tostring(v) end
function GetQuestID() return questID end
function GetTitleText() return 'Дворфские экипировщики' end
function GetQuestText() return 'Текст выдачи' end
function GetProgressText() return 'Текст процесса' end
function GetRewardText() return 'Текст сдачи' end
function UnitName() return 'Стен Крепкорук' end
function UnitGUID() return 'Creature-0-1-0-1-658-0000000001' end
function PlaySoundFile(file, channel)
    nextHandle = nextHandle+1
    plays[#plays+1] = {file=file,channel=channel,handle=nextHandle,dialog=cvars.Sound_EnableDialog,volume=cvars.Sound_DialogVolume}
    if soundOK then return true,nextHandle end
    return false,nil
end
function StopSound(h) stops[#stops+1]=h end
function PlayMusic() error('Unexpected musical fallback') end
function StopMusic() end
function GetBuildInfo() return '1.60.1','70009','date',16001 end
WOW_PROJECT_ID = 99
C_AddOns = {IsAddOnLoaded=function() return true end}
DEFAULT_CHAT_FRAME = {AddMessage=function(_,text) messages[#messages+1]=text end}
SlashCmdList, StaticPopupDialogs = {}, {}
function StaticPopup_Show() end
function CreateFrame(_,name)
    local f={scripts={},events={},visible=true}
    function f:SetScript(event,callback) self.scripts[event]=callback end
    function f:RegisterEvent(event) self.events[event]=true end
    function f:Hide() self.visible=false end
    function f:Show() self.visible=true end
    if name then frames[name]=f end
    return f
end
function event(name)
    local f=frames.WowVoiceFrame
    assert(f.events[name], 'event not registered: '..name)
    f.scripts.OnEvent(f,name,'TalkingHeadRu')
end
function tick(t)
    now=t
    local f=frames.WowVoiceTicker
    if f.visible then f.scripts.OnUpdate() end
end
function command(s) SlashCmdList.WOWVOICETALKINGHEAD(s) end
function has(s)
    for _,m in ipairs(messages) do if m:find(s,1,true) then return true end end
    return false
end
function restored(enable,volume)
    assert(cvars.Sound_EnableDialog==enable and cvars.Sound_DialogVolume==volume,'Dialog restoration failed')
end

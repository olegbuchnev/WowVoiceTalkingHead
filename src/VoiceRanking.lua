-- Community ranking applies only to normal playback; explicit source previews stay independent.
local WV, Codec = WowVoice, TalkingHeadRuRankingCodec
local Ranking = {}
TalkingHeadRuVoiceRanking = Ranking
local sourceIDs = {WowVoice='wowvoice',CatQuest='catquest',Wayfarer='wayfarer'}
local fallback = {'wowvoice','catquest','wayfarer'}
local function fields(value, allowed)
    assert(Codec.IsObject(value),'Expected object')
    for key in pairs(value) do assert(allowed[key],'Unknown field') end
end
local function stamp(value)
    assert(type(value)=='string','Missing timestamp')
    local y,m,d,h,n,s,tail=value:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)(.*)$')
    assert(y and (tail=='Z' or tail:match('^%.%d+Z$')),'Invalid UTC timestamp')
    y,m,d,h,n,s=tonumber(y),tonumber(m),tonumber(d),tonumber(h),tonumber(n),tonumber(s)
    local days={31,(y%4==0 and (y%100~=0 or y%400==0)) and 29 or 28,31,30,31,30,31,31,30,31,30,31}
    assert(y>=1970 and m>=1 and m<=12 and d>=1 and d<=days[m] and h<24 and n<60 and s<60,'Invalid UTC timestamp')
    local fraction=tail:match('^%.(%d+)Z$') or ''
    return value:sub(1,19)..'.'..fraction:gsub('0+$','')
end
function Ranking.FormatSnapshotTime(value)
    stamp(value)
    local y,m,d,h,n,s=value:match('^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)')
    y,m,d,h,n,s=tonumber(y),tonumber(m),tonumber(d),tonumber(h),tonumber(n),tonumber(s)
    local function leapYearsBefore(year)
        year=year-1
        return math.floor(year/4)-math.floor(year/100)+math.floor(year/400)
    end
    local days=(y-1970)*365+leapYearsBefore(y)-leapYearsBefore(1970)+d-1
    local months={31,(y%4==0 and (y%100~=0 or y%400==0)) and 29 or 28,31,30,31,30,31,31,30,31,30,31}
    for month=1,m-1 do days=days+months[month] end
    -- Convert UTC directly to an epoch. Local time() and today's UTC offset
    -- would misinterpret the date around DST transitions or in another season.
    local epoch=days*86400.0+h*3600+n*60+s
    local formatter=date or (os and os.date)
    if formatter then
        local ok,text=pcall(formatter,'%d.%m.%Y, %H:%M:%S',epoch)
        if ok and type(text)=='string' then return text end
    end
    return value:sub(1,19):gsub('T',' ')..' UTC'
end
function Ranking.Validate(snapshot)
    fields(snapshot,{schemaVersion=true,generatedAt=true,groups=true})
    assert(snapshot.schemaVersion==1,'Unsupported schema')
    stamp(snapshot.generatedAt)
    assert(Codec.IsArray(snapshot.groups) and #snapshot.groups<=256,'Invalid groups')
    local clean={schemaVersion=1,generatedAt=snapshot.generatedAt,groups={}}
    local index={}
    for _,group in ipairs(snapshot.groups) do
        fields(group,{speakerType=true,race=true,sex=true,status=true,ranking=true})
        local key
        if group.speakerType=='npc' then
            assert(type(group.race)=='string' and #group.race<=64 and group.race:match('^[a-z][a-z0-9_]*$'),'Invalid race')
            assert(group.sex=='male' or group.sex=='female','Invalid sex')
            key='npc:'..group.race..':'..group.sex
        else
            assert(group.speakerType=='narrator' and group.race==Codec.Null and group.sex==Codec.Null,'Invalid speaker type')
            key='narrator'
        end
        assert(not index[key],'Duplicate speaker group')
        assert(Codec.IsArray(group.ranking) and #group.ranking==3,'Invalid ranking')
        local places,seen,ties,observed={}, {}, {}, 0
        for rank,place in ipairs(group.ranking) do
            fields(place,{rank=true,source=true,basis=true,tieGroup=true})
            assert(place.rank==rank and sourceIDs[place.source] and not seen[place.source],'Invalid places')
            seen[place.source]=true
            assert(place.basis=='votes' or place.basis=='fallback','Invalid basis')
            if place.basis=='votes' then observed=observed+1; assert(observed==rank,'Votes after fallback') end
            local tie=place.tieGroup
            if tie==Codec.Null then tie=nil end
            if tie~=nil then
                assert(type(tie)=='number' and (tie==1 or tie==2) and place.basis=='votes','Invalid tie')
                ties[tie]=ties[tie] or {}; ties[tie][#ties[tie]+1]=rank
            end
            places[rank]={rank=rank,source=place.source,basis=place.basis,tieGroup=tie}
        end
        for tie,members in pairs(ties) do
            assert(#members>=2,'Singleton tie')
            for i,rank in ipairs(members) do assert(rank==tie+i-1,'Noncontiguous tie') end
        end
        local expected=observed==0 and 'no_data' or observed==3 and 'ranked' or observed==2 and 'partial'
        assert(expected and group.status==expected,'Invalid group status')
        local value={speakerType=group.speakerType,race=group.race~=Codec.Null and group.race or nil,
            sex=group.sex~=Codec.Null and group.sex or nil,status=group.status,ranking=places}
        clean.groups[#clean.groups+1]=value; index[key]=value
    end
    return clean,index
end

local cachedRecord,cachedSnapshot,cachedIndex,builtinSnapshot,builtinIndex,builtinRecord
local function fromRecord(record)
    if type(record)~='table' or type(record.json)~='string' or #record.json>65536
        or type(record.sha256)~='string' or #record.sha256~=64 then return end
    if Codec.SHA256(record.json)~=record.sha256 then return end
    return Ranking.Validate(Codec.JSON(record.json))
end
function Ranking.Current()
    local record=TalkingHeadRuDB and TalkingHeadRuDB.voiceRanking
    if record~=cachedRecord then
        cachedRecord,cachedSnapshot,cachedIndex=record,nil,nil
        local ok,snapshot,index=pcall(fromRecord,record)
        if ok then cachedSnapshot,cachedIndex=snapshot,index end
    end
    if builtinRecord~=TalkingHeadRuBuiltinRanking then
        builtinRecord=TalkingHeadRuBuiltinRanking
        builtinSnapshot,builtinIndex=nil,nil
        local ok,snapshot,index=pcall(fromRecord,TalkingHeadRuBuiltinRanking)
        if ok then builtinSnapshot,builtinIndex=snapshot,index end
    end
    if cachedSnapshot and (not builtinSnapshot or stamp(cachedSnapshot.generatedAt)>=stamp(builtinSnapshot.generatedAt)) then
        return cachedSnapshot,cachedIndex,'imported'
    end
    return builtinSnapshot,builtinIndex,'builtin'
end
function Ranking.Prepare(text)
    local ok,result=pcall(function()
        local raw,json,hash=Codec.Decode(text)
        local snapshot=Ranking.Validate(raw)
        return {json=json,sha256=hash,snapshot=snapshot}
    end)
    if not ok then return nil,'Не удалось прочитать рейтинг. Скопируйте строку целиком с сайта.' end
    return result
end
function Ranking.Import(text,options)
    local record,message=Ranking.Prepare(text)
    if not record then return false,message end
    if not TalkingHeadRuDB then return false,'Настройки ещё не загружены.' end
    local current=Ranking.Current()
    if current and stamp(record.snapshot.generatedAt)<stamp(current.generatedAt) then
        return false,'older',record.snapshot.generatedAt
    end
    local preserve=not (type(options)=='table' and options.preserveOverrides==false)
    local saved=TalkingHeadRuDB.voiceRanking
    if type(saved)=='table' and saved.sha256==record.sha256 and saved.json==record.json then
        if not preserve then
            TalkingHeadRuDB.voiceGroupOrders=nil
            WV:RefreshAudioSources(true)
        end
        return true,'Этот рейтинг уже установлен.'
    end
    record.importedAt=type(GetServerTime)=='function' and GetServerTime() or 0
    TalkingHeadRuDB.voiceRanking=record
    if not preserve then TalkingHeadRuDB.voiceGroupOrders=nil end
    WV:RefreshAudioSources(true)
    return true,'Рейтинг обновлён.'
end
function WV:GetVoiceSelectionMode()
    return TalkingHeadRuDB and TalkingHeadRuDB.voiceSelectionMode=='ranking' and 'ranking' or 'manual'
end
function WV:SetVoiceSelectionMode(mode)
    if not TalkingHeadRuDB or (mode~='manual' and mode~='ranking') then return false end
    TalkingHeadRuDB.voiceSelectionMode=mode; self:RefreshAudioSources(true); return true
end

function Ranking.GroupKey(questID,section,context)
    local database=TalkingHeadRuSpeakers
    if not database or database.schemaVersion~=1 then return end
    local speaker=context and context.speaker
    if not speaker then
        local roles=(section=='p' or section=='c') and database.finishers or database.givers
        speaker=roles and roles[questID]
    end
    if not speaker or speaker.itemID or speaker.objectID then return end
    if speaker.narrator then return 'narrator' end
    local npc=database.npcs and database.npcs[speaker.npcID]
    if npc and type(npc.race)=='string' and (npc.sex=='male' or npc.sex=='female') then
        return 'npc:'..npc.race..':'..npc.sex
    end
end
local function copyOrder(value)
    if type(value)~='table' or #value~=3 then return end
    local result,seen={},{}
    for i,id in ipairs(value) do
        if (id~='wowvoice' and id~='catquest' and id~='wayfarer') or seen[id] then return end
        result[i],seen[id]=id,true
    end
    return result
end
function Ranking.Order(group, preference)
    if not group or group.status=='no_data' then return copyOrder(preference) or copyOrder(fallback) end
    local order,position={},{}
    for i,id in ipairs(preference or {}) do position[id]=i end
    for _,entry in ipairs(group.ranking) do order[#order+1]=entry end
    table.sort(order,function(a,b)
        if a.tieGroup and a.tieGroup==b.tieGroup then
            local x,y=position[sourceIDs[a.source]] or 4,position[sourceIDs[b.source]] or 4
            if x~=y then return x<y end
        end
        return a.rank<b.rank
    end)
    local result={}
    for _,entry in ipairs(order) do result[#result+1]=sourceIDs[entry.source] end
    return result
end
function WV:GetQuestVoicePriority(questID,section,context)
    if self:GetVoiceSelectionMode()~='ranking' then return self:GetVoicePriority() end
    local key=Ranking.GroupKey(questID,section,context)
    return Ranking.ConfiguredOrder(key)
end

function Ranking.GroupID(group)
    return group.speakerType=='narrator' and 'narrator' or 'npc:'..group.race..':'..group.sex
end
local function validKey(key)
    if type(key)~='string' then return false end
    if key=='narrator' then return true end
    local race,sex=key:match('^npc:([a-z][a-z0-9_]*):([a-z]+)$')
    return race and #race<=64 and (sex=='male' or sex=='female')
end
function Ranking.Override(key)
    local orders=TalkingHeadRuDB and TalkingHeadRuDB.voiceGroupOrders
    return validKey(key) and type(orders)=='table' and copyOrder(orders[key]) or nil
end
function Ranking.SetOverride(key,order)
    local copy=copyOrder(order)
    if not TalkingHeadRuDB or not validKey(key) or not copy then return false end
    if type(TalkingHeadRuDB.voiceGroupOrders)~='table' then TalkingHeadRuDB.voiceGroupOrders={} end
    TalkingHeadRuDB.voiceGroupOrders[key]=copy
    WV:RefreshAudioSources(true); return true
end
function Ranking.Reset(key)
    local orders=TalkingHeadRuDB and TalkingHeadRuDB.voiceGroupOrders
    if type(orders)=='table' then orders[key]=nil; WV:RefreshAudioSources(true) end
end
function Ranking.ResetAll()
    if TalkingHeadRuDB then TalkingHeadRuDB.voiceGroupOrders=nil; WV:RefreshAudioSources(true) end
end
function Ranking.HasOverrides()
    local orders=TalkingHeadRuDB and TalkingHeadRuDB.voiceGroupOrders
    for key in pairs(type(orders)=='table' and orders or {}) do if Ranking.Override(key) then return true end end
    return false
end
function Ranking.ConfiguredOrder(key)
    local private=Ranking.Override(key)
    if private then return private,'custom' end
    local _,index=Ranking.Current()
    local group=index and key and index[key]
    return Ranking.Order(group,WV:GetVoicePriority()),group and group.status~='no_data' and 'ranking' or 'fallback'
end
function Ranking.EffectiveOrder(key)
    if WV:GetVoiceSelectionMode()=='manual' then return WV:GetVoicePriority(),'manual' end
    return Ranking.ConfiguredOrder(key)
end

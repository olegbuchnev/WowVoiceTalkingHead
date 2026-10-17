-- Description samples use the same resolved speaker and transport as local previews.
local WV,R,C=WowVoice,TalkingHeadRuVoiceRanking,WowVoiceComparison
local Examples={}
TalkingHeadRuVoiceGroupExamples=Examples
local sources={'wowvoice','catquest','wayfarer'}
local function noop() end
local titleSource,titleIndex
local function questTitles(checkpoint)
    local index=WowVoiceIndex
    if titleIndex and titleSource==index then return titleIndex end
    local titles,steps={},0
    for title,entries in pairs(index or {}) do
        for _,entry in ipairs(entries) do
            if type(entry.q)=='number' and (not titles[entry.q] or title<titles[entry.q]) then titles[entry.q]=title end
            steps=steps+1
            if steps%32==0 then checkpoint() end
        end
    end
    titleSource,titleIndex=index,titles
    return titles
end
local function before(a,b) return a.count==b.count and a.id<b.id or a.count>b.count end
-- Merge in small steps: Lua 5.1 cannot yield from table.sort's comparator.
local function sortCandidates(values,checkpoint)
    local size,n=1,#values
    while size<n do
        local merged={}
        for start=1,n,size*2 do
            local left,right=start,start+size
            local leftEnd,rightEnd=math.min(start+size-1,n),math.min(start+size*2-1,n)
            for i=start,rightEnd do
                if left<=leftEnd and (right>rightEnd or before(values[left],values[right])) then
                    merged[i]=values[left]; left=left+1
                else merged[i]=values[right]; right=right+1 end
                if i%32==0 then checkpoint() end
            end
        end
        values=merged; size=size*2; checkpoint()
    end
    return values
end
function Examples.Build(key,checkpoint)
    checkpoint=checkpoint or noop
    local result,available,enabled={},0,{}
    for _,source in ipairs(sources) do
        enabled[source]=C.SourceAvailable(source)
        if enabled[source] then available=available+1 end
        checkpoint()
    end
    if available==0 then return result,available end
    local snapshot=WV:BuildReplaySpeakerSnapshot(checkpoint)
    local titles=questTitles(checkpoint)
    local enumerated=0
    local ids=C.QuestIDs(function()
        enumerated=enumerated+1
        if enumerated%32==0 then checkpoint() end
    end)
    checkpoint()
    for id in pairs(ids) do
        local context=WV.GetReplaySpeaker and WV:GetReplaySpeaker(id,snapshot)
        if context and (type(context.title)~='string' or not context.title:find('%S')) then context.title=titles[id] end
        checkpoint()
        if R.GroupKey(id,'a',context)==key then
            local count=0
            for _,source in ipairs(sources) do
                if enabled[source] and C.Resolve(id,source) then count=count+1 end
                checkpoint()
            end
            if count>=math.min(2,available) then result[#result+1]={id=id,count=count,context=context} end
        end
    end
    return sortCandidates(result,checkpoint),available
end
local jobKey='voice-group-examples'
function Examples.Cancel()
    WV.Work:Cancel(jobKey)
end
function Examples.Request(key,complete)
    Examples.Cancel()
    WV.Work:Queue(jobKey,function()
        -- Resume a nested coroutine to report errors without pcall across yields
        -- (unsupported by Lua 5.1). No catalogue work runs in the click handler.
        local worker=coroutine.create(function() return Examples.Build(key,coroutine.yield) end)
        while true do
            local ok,result,available=coroutine.resume(worker)
            if not ok then complete(nil,nil,tostring(result)); return end
            if coroutine.status(worker)=='dead' then complete(result,available); return end
            coroutine.yield()
        end
    end,0,false)
end
function Examples.New(candidates)
    local state={candidates=candidates,bag={},current=candidates[1]}
    for i=2,#candidates do state.bag[#state.bag+1]=candidates[i] end
    return state
end
function Examples.Next(state)
    if #state.candidates<2 then return state.current end
    if #state.bag==0 then
        for _,candidate in ipairs(state.candidates) do state.bag[#state.bag+1]=candidate end
    end
    local choices={}
    for i,candidate in ipairs(state.bag) do
        if candidate~=state.current then choices[#choices+1]=i end
    end
    local index=choices[math.random(#choices)]
    state.current=table.remove(state.bag,index)
    return state.current
end
function Examples.Stop(owner)
    if WV.Playback.previewOwner==owner then WV.Playback:Stop('group preview closed') end
end

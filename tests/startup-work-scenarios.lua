event('ADDON_LOADED')
local WV, work = WowVoice, WowVoice.Work
local frame = frames.WowVoiceWorkFrame
local rows={}
for key in pairs(WowVoiceDur) do
    local id=key:match('^(%d+)a$')
    if id then rows[#rows+1]={questID=tonumber(id)} end
end
table.sort(rows,function(a,b) return a.questID<b.questID end)
while #rows>25 do table.remove(rows) end
C_QuestLog.GetNumQuestLogEntries=function() return #rows end
C_QuestLog.GetInfo=function(i) return rows[i] end
local cpu, slots, maxLoading, requests = 0,0,0,0
function debugprofilestop() return cpu end
NUM_TOTAL_EQUIPPED_BAG_SLOTS=4
C_Container={
    GetContainerNumSlots=function() return 20 end,
    GetContainerItemQuestInfo=function() slots=slots+1; cpu=cpu+0.12; return nil end,
    GetContainerItemInfo=function() return nil end,
}
local create=CreateFrame
function CreateFrame(kind,name,...)
    local f=create(kind,name,...)
    if kind=='PlayerModel' and name and name:find('WowVoiceWarmPortrait',1,true) then
        function f:SetCreature()
            requests=requests+1; cpu=cpu+0.2
            local loading=0
            for key,model in pairs(frames) do
                if key:find('WowVoiceWarmPortrait',1,true) and model.visible then loading=loading+1 end
            end
            maxLoading=math.max(maxLoading,loading)
            assert(loading<=2, 'too many pending background model loads')
        end
    end
    return f
end
local function pump(seconds)
    for i=1,math.ceil(seconds*60) do
        now=now+1/60
        if frame.scripts.OnUpdate then frame.scripts.OnUpdate() end
    end
end
frame.scripts.OnEvent(frame,'PLAYER_ENTERING_WORLD')
portraitEvent('PLAYER_LOGIN')
pump(2.9)
assert(slots==0 and requests==0, 'preparation ran during login grace period')
assert(WV:ReplayQuest(179) and #plays==1, 'early click must not wait for preparation')
WV:Silence(); slots=0
pump(4)
assert(slots==100, '25 quests must share exactly one 100-slot inventory scan')
assert(requests>0 and maxLoading<=2 and work.maxSliceMS<=1.01)
assert(work.metrics['portrait-scan'].steps>4000, 'reverse index must be prepared incrementally')
for i=1,50 do portraitEvent('QUEST_LOG_UPDATE') end
pump(1)
assert(slots==200, 'event burst must cause one fresh inventory pass')
pump(90)
assert(not frame.scripts.OnUpdate and #work.order==0, 'completed/exhausted warmup must go idle')
assert(work.errors==0)
-- Real progress scans, unlike prewarming, must still run during combat.
local objectiveCalls=0
C_QuestLog.GetQuestObjectives=function()
    objectiveCalls=objectiveCalls+1
    return {{text='Targets: 0/10',type='monster',numFulfilled=0,numRequired=10}}
end
function InCombatLockdown() return true end
frame.scripts.OnEvent(frame,'PLAYER_REGEN_DISABLED')
local tracker=frames.WowVoiceTrackerEvents
tracker.scripts.OnEvent(tracker,'PLAYER_LOGIN')
for i=1,50 do tracker.scripts.OnEvent(tracker,'QUEST_LOG_UPDATE') end
pump(0.2)
assert(objectiveCalls==25, 'combat progress event burst must share one journal scan')
assert(not frame.scripts.OnUpdate and #work.order==0)
print('PASS: 2500 inventory queries reduced to 100 per scan; delayed incremental initialization, immediate replay, two pending models, coalesced events and idle shutdown')

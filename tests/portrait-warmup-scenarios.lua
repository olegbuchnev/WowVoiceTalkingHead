event('ADDON_LOADED')
event('PLAYER_LOGIN')
WowVoiceDB.questSpeakers = {}
local WV = WowVoice
local rows = {{isHeader=true},{questID=179},{questID=861},{questID=176},
    {questID=999999},{questID=7649},{questID=179}}
C_QuestLog.GetNumQuestLogEntries = function() return #rows end
C_QuestLog.GetInfo = function(index) return rows[index] end
WV:GetReplaySpeaker(179)
questCache()[7649] = {itemID=18769,icon=134939}

local baseCreate = CreateFrame
local requests, available, displayRequests = {}, {}, {}
function CreateFrame(kind,name,parent,template)
    local frame = baseCreate(kind,name,parent,template)
    if kind == 'PlayerModel' then
        local setDisplay = frame.SetDisplayInfo
        function frame:SetCreature(id)
            requests[id] = (requests[id] or 0) + 1
            -- Metadata arrives before render resources and OnModelLoaded.
            self.displayID = id + 10000
            if available[id] then self:CompleteLoad(available[id]) end
        end
        function frame:SetDisplayInfo(id)
            displayRequests[id] = (displayRequests[id] or 0) + 1
            setDisplay(self,id)
        end
    end
    return frame
end
local function background(seconds)
    for i=1,math.ceil(seconds*60) do
        now=now+1/60
        local update = frames.WowVoiceWorkFrame.scripts.OnUpdate
        if update then update() end
    end
end
portraitEvent('PLAYER_LOGIN')
background(5)
assert(requests[658] == 1 and requests[3052] == 1)
assert(not requests[240] and not requests[999999])
local count=0
for _ in pairs(requests) do count=count+1 end
assert(count==2 and #plays==0 and #stops==0)
assert(not frames.WowVoiceTalkingHead, 'background warmup must not create a visible head')
assert(frames.WowVoiceWarmPortraitNPC658.alpha==0)
assert(frames.WowVoiceWarmPortraitNPC658.modelAlpha==0,
    'warmup geometry must be invisible independently of frame alpha')
assert(frames.WowVoiceWarmPortraitNPC658.visible,
    'an early display ID must not finish or hide an unloaded warmup model')
print('PASS: login warms unique journal givers gradually, skipping headers, receivers, items and quests without audio')

assert(WV:ReplayQuest(861))
local head=frames.WowVoiceTalkingHead
assert(head.Icon.visible and head.Model.alpha==0)
assert(not head.Model.portraitReady and not head.Model.cameraRefreshes,
    'metadata alone must not initialize the camera or hide the placeholder')
local sounds,stopped=#plays,#stops
now=now+1
frames.WowVoiceWarmPortraitNPC3052:CompleteLoad(13052)
assert(head.Model.displayID==13052 and not head.Icon.visible)
head.scripts.OnUpdate()
assert(head.Progress.value>0 and #plays==sounds and #stops==stopped)
assert(head.Name.text=='Скорн Белое Облако')
local cameraRefreshes=head.Model.cameraRefreshes
head.Model:CompleteLoad(13052)
assert(head.Model.cameraRefreshes==cameraRefreshes+1,
    'every real load must restore the camera even after an earlier ready state')
available[658]=10658
background(2)
assert(not frames.WowVoiceWarmPortraitNPC658.visible)
local before=requests[658]
WV:ReplayQuest(179)
assert(head.Model.displayID==10658 and not head.Icon.visible)
assert(requests[658]==before and displayRequests[10658])
assert(head.Name.text=='Стен Крепкорук')
print('PASS: early metadata stays pending, real loads configure the camera, repeated loads restore it without restarting audio')

-- A quest not preloaded still retries on its own, without another click.
WV:ReplayQuest(318)
assert(head.Icon.visible)
sounds,stopped=#plays,#stops
available[1378]=11378
now=now+1.1; head.scripts.OnUpdate()
assert(head.Model.displayID==11378 and not head.Icon.visible)
assert(#plays==sounds and #stops==stopped and head.Progress.value>0)
before=requests[1378]
now=now+3; head.scripts.OnUpdate()
assert(requests[1378]==before)
-- Missing models stop retrying, and stopping playback cancels visible retries.
WV:ReplayQuest(1127)
for i=1,25 do now=now+1; head.scripts.OnUpdate() end
before=requests[2498]
assert(before<=21 and head.Icon.visible)
now=now+30; head.scripts.OnUpdate()
assert(requests[2498]==before)
WV:Silence(); head.scripts.OnUpdate()
assert(requests[2498]==before)
restored('1','0.37')
print('PASS: visible portraits retry until model-loaded events, preserve audio time, and stop at a bounded deadline')

-- Quest-log updates warm new identities and captured display IDs.
questCache()[861]={npcID=3052,displayID=7777,name='Captured NPC'}
rows={{questID=1127},{questID=861}}
portraitEvent('QUEST_LOG_UPDATE')
portraitEvent('QUEST_LOG_UPDATE')
background(1)
assert(displayRequests[7777])
assert(not frames.WowVoiceWarmPortraitDisplay7777.visible)
local warmMissing=frames.WowVoiceWarmPortraitNPC2498
assert(warmMissing and warmMissing.alpha==0)
before=requests[2498]
background(90)
local finalRequests=requests[2498]
assert(finalRequests-before<=8)
background(90)
assert(requests[2498]==finalRequests, 'missing models must not retry forever')

-- An abandoned job's late event must not replace the current quest's model.
rows={{questID=861}}
portraitEvent('QUEST_REMOVED',1127)
background(1)
assert(not warmMissing.visible)
WV:ReplayQuest(861)
assert(head.Model.displayID==7777)
sounds,stopped=#plays,#stops
warmMissing:CompleteLoad(12498)
assert(head.Model.displayID==7777 and #plays==sounds and #stops==stopped)
assert(not questCache()[1127])
WV:Silence(); restored('1','0.37')
assert(questCache()[861].displayID==7777)
print('PASS: journal changes refresh warmup, captured displays win, failures are bounded, abandoned callbacks cannot change another quest')

-- Development-only simulation. No WoW events or SavedVariables here.
WowVoiceQueueLab = { version = 1 }
local Lab = WowVoiceQueueLab
local State = {}
State.__index = State

function Lab.NewState()
    return setmetatable({ quests = {}, accepted = {} }, State)
end

function State:Accept(quest)
    if self.quests[quest.id] then return false end
    self.quests[quest.id] = quest
    self.accepted[#self.accepted + 1] = quest
    quest.accepted = true
    return true
end

function State:TurnIn(id)
    local quest = self.quests[id]
    if not quest or not quest.accepted then return false end
    quest.accepted = false
    return true
end

function State:AcceptedQuests()
    local result = {}
    for _, quest in ipairs(self.accepted) do
        if quest.accepted then result[#result + 1] = quest end
    end
    return result
end

Lab.state = Lab.NewState()

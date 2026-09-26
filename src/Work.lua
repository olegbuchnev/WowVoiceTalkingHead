-- Cooperative background work. The budget covers all jobs together; native
-- client calls cannot be interrupted, so every caller must yield small units.
local WV = _G.WowVoice
local Work = { budgetMS = 1, jobs = {}, order = {}, metrics = {}, slices = 0,
    maxSliceMS = 0, overBudget = 0, errors = 0, cursor = 0 }
WV.Work = Work
local frame = CreateFrame("Frame", "WowVoiceWorkFrame")
local prepareAt, leavingWorld = GetTime() + 3, false
local wake, update
local timerPending = false
local function clockMS()
    if type(debugprofilestop) == "function" then return debugprofilestop() end
    return GetTime() * 1000
end
local function allowed(job)
    return not leavingWorld and (not job.prepare or
        not (type(InCombatLockdown) == "function" and InCombatLockdown()))
end
local function dueAt(job)
    return math.max(job.due, job.prepare and prepareAt or 0)
end
local function remove(key)
    Work.jobs[key] = nil
    for i, name in ipairs(Work.order) do
        if name == key then
            table.remove(Work.order, i)
            if i <= Work.cursor then Work.cursor = math.max(0, Work.cursor - 1) end
            break
        end
    end
end
function Work:Cancel(key)
    remove(key)
    wake()
end
function Work:Queue(key, fn, delay, prepare)
    local job = self.jobs[key]
    if job then
        -- Pending events coalesce; a running scan gets at most one fresh pass.
        if job.started then job.again = fn else job.fn = fn end
    else
        self.jobs[key] = { fn = fn, due = GetTime() + (delay or 0), prepare = prepare }
        self.order[#self.order + 1] = key
    end
    wake()
end
update = function()
    local started, units = clockMS(), 0
    while units < 64 and #Work.order > 0 do
        local key, job
        for _ = 1, #Work.order do
            Work.cursor = Work.cursor % #Work.order + 1
            local name = Work.order[Work.cursor]
            local candidate = Work.jobs[name]
            if allowed(candidate) and GetTime() >= dueAt(candidate) then
                key, job = name, candidate
                break
            end
        end
        if not job then break end
        local estimate = Work.metrics[key] and Work.metrics[key].estimateMS or 0
        if units > 0 and clockMS() - started + estimate * 1.2 >= Work.budgetMS then
            -- Keep the deferred job first next frame, including an expensive
            -- native step whose estimate exceeds the entire soft budget.
            Work.cursor = math.max(0, Work.cursor - 1)
            break
        end
        job.thread = job.thread or coroutine.create(job.fn)
        job.started = true
        local before = clockMS()
        local ok, delay = coroutine.resume(job.thread)
        local elapsed = math.max(0, clockMS() - before)
        local metric = Work.metrics[key] or { steps = 0, totalMS = 0, maxStepMS = 0 }
        Work.metrics[key] = metric
        metric.steps, metric.totalMS = metric.steps + 1, metric.totalMS + elapsed
        metric.maxStepMS = math.max(metric.maxStepMS, elapsed)
        -- Retain peaks for diagnostics, but let scheduling recover from a cold
        -- native call/GC spike instead of running one cheap step per frame forever.
        metric.estimateMS = math.max(elapsed, (metric.estimateMS or 0) * 0.8)
        units = units + 1
        if Work.jobs[key] == job then
            if not ok then
                Work.errors = Work.errors + 1
                Work.lastError = key .. ": " .. tostring(delay)
                remove(key)
                if type(geterrorhandler) == "function" then geterrorhandler()(Work.lastError) end
            elseif coroutine.status(job.thread) == "dead" then
                if job.again then
                    job.fn, job.thread, job.started, job.again = job.again, nil, nil, nil
                    job.due = GetTime()
                else remove(key) end
            else job.due = GetTime() + (type(delay) == "number" and math.max(0, delay) or 0) end
        end
    end
    if units > 0 then
        local elapsed = math.max(0, clockMS() - started)
        Work.slices = Work.slices + 1
        Work.maxSliceMS = math.max(Work.maxSliceMS, elapsed)
        if elapsed > Work.budgetMS then Work.overBudget = Work.overBudget + 1 end
    end
    wake()
end
wake = function()
    local earliest
    for _, job in pairs(Work.jobs) do
        if allowed(job) then earliest = math.min(earliest or math.huge, dueAt(job)) end
    end
    if not earliest then frame:SetScript("OnUpdate", nil); return end
    if earliest <= GetTime() or not (C_Timer and C_Timer.After) then
        frame:SetScript("OnUpdate", update)
    else
        frame:SetScript("OnUpdate", nil)
        if not timerPending then
            timerPending = true
            -- A short wakeup also covers jobs added while this timer is pending.
            C_Timer.After(math.min(0.1, earliest - GetTime()), function()
                timerPending = false
                wake()
            end)
        end
    end
end
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LEAVING_WORLD" then leavingWorld = true
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        leavingWorld, prepareAt = false, GetTime() + 3
    end
    wake()
end)
function Work:Report()
    local function line(text)
        DEFAULT_CHAT_FRAME:AddMessage(WV.displayName .. ": " .. text)
    end
    line(string.format("Work: budget=%.1fms pending=%d slices=%d max=%.2fms over=%d errors=%d clock=%s",
        self.budgetMS, #self.order, self.slices, self.maxSliceMS, self.overBudget, self.errors,
        type(debugprofilestop) == "function" and "profile" or "coarse"))
    for key, m in pairs(self.metrics) do
        line(string.format("%s: steps=%d total=%.2fms maxStep=%.2fms", key, m.steps, m.totalMS, m.maxStepMS))
    end
    if self.lastError then line(self.lastError) end
end

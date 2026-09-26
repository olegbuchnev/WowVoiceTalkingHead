event('ADDON_LOADED')
local work, frame = WowVoice.Work, frames.WowVoiceWorkFrame
local cpu, combat = 0, false
function debugprofilestop() return cpu end
function InCombatLockdown() return combat end
local function update()
    if frame.scripts.OnUpdate then frame.scripts.OnUpdate() end
end
local function signal(name) frame.scripts.OnEvent(frame, name) end
local a, b = 0, 0
work:Queue('a', function()
    for i=1,20 do a=a+1; cpu=cpu+0.35; coroutine.yield() end
end)
work:Queue('b', function()
    for i=1,20 do b=b+1; cpu=cpu+0.35; coroutine.yield() end
end)
update()
assert(a>0 and b>0 and a+b<=2, 'jobs share one budget, not one budget each')
for i=1,60 do update() end
assert(a==20 and b==20 and work.maxSliceMS<=1)
assert(not frame.scripts.OnUpdate and #work.order==0, 'idle queue has no per-frame callback')

-- An indivisible native call may overrun, but must not starve or lose its job.
local slow, fast = 0, 0
work:Queue('slow', function()
    for i=1,3 do slow=slow+1; cpu=cpu+2; coroutine.yield() end
end)
work:Queue('fast', function()
    for i=1,6 do fast=fast+1; cpu=cpu+0.1; coroutine.yield() end
end)
for i=1,30 do update() end
assert(slow==3 and fast==6 and work.overBudget>=3)
assert(work.metrics.slow.maxStepMS==2)
local cold=0
work:Queue('cold',function()
    for i=1,200 do cold=cold+1; cpu=cpu+(i==1 and 4 or 0.001); coroutine.yield() end
end)
for i=1,30 do update() end
assert(cold==200 and work.metrics.cold.maxStepMS==4,
    'a cold allocation spike must not permanently throttle cheap steps')

local prepared, progress = 0, 0
signal('PLAYER_ENTERING_WORLD')
work:Queue('prepare', function() prepared=prepared+1 end, 0, true)
now=2.9; update(); assert(prepared==0)
combat=true; signal('PLAYER_REGEN_DISABLED')
now=4; update(); assert(prepared==0 and not frame.scripts.OnUpdate)
work:Queue('progress', function() progress=progress+1 end)
update(); assert(progress==1 and prepared==0, 'progress remains available in combat')
combat=false; signal('PLAYER_REGEN_ENABLED'); update(); assert(prepared==1)

-- A burst before execution coalesces; events during execution request one rerun.
local starts=0
local function scan() starts=starts+1; coroutine.yield(0.5) end
for i=1,50 do work:Queue('scan', scan, 0.05) end
now=now+0.1; update(); assert(starts==1)
for i=1,50 do work:Queue('scan', scan, 0.05) end
now=now+0.6; update(); now=now+0.6; update()
assert(starts==2 and not work.jobs.scan)
work:Queue('cancel', function() error('cancelled work ran') end)
work:Cancel('cancel'); update(); assert(work.errors==0)
work:Queue('error', function() error('expected test failure') end)
update(); assert(work.errors==1 and work.lastError:find('expected test failure',1,true))
command('perf'); assert(has('budget=1.0ms') and has('maxStep='))

-- Old clients lack the profiler and timers: cap units and still finish.
debugprofilestop=nil
local fallback=0
work:Queue('fallback',function() for i=1,200 do fallback=fallback+1; coroutine.yield() end end)
update(); assert(fallback==64)
for i=1,5 do update() end
assert(fallback==200 and not frame.scripts.OnUpdate)

-- Modern clients detach OnUpdate while sleeping and wake through a timer.
local timers={}
C_Timer={After=function(delay,fn) timers[#timers+1]={delay=delay,fn=fn} end}
local delayed=0
work:Queue('timer',function() delayed=delayed+1 end,0.05)
assert(not frame.scripts.OnUpdate and #timers==1)
now=now+0.06; timers[1].fn(); update()
assert(delayed==1 and not frame.scripts.OnUpdate)
print('PASS: shared frame budget, fairness, overruns, startup delay, combat, coalescing, cancellation, idle, diagnostics and legacy/timer wakeups')

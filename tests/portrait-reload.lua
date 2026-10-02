event('ADDON_LOADED')
event('PLAYER_LOGIN')
assert(questCache()[179].displayID==savedBeforeReload)
assert(WowVoice:ReplayQuest(179))
local head=frames.WowVoiceTalkingHead
assert(head.visible and head.Model.displayID==savedBeforeReload)
WowVoice:Silence()
print('PASS: saved appearance survives recreation of all addon frames/state and replays after simulated reload')

-- A cold native load can finish after OnModelLoaded returns, resetting the
-- animation and exposing the mesh before its talking sequence is available.
local model = head.Model
local completeLoad, hasAnimation, setAnimation = model.CompleteLoad, model.HasAnimation, model.SetAnimation
local animationReady, animationStarts = false, 0
function model:CompleteLoad(display)
    completeLoad(self, display)
    self.animation, self.paused = 0, true
end
function model:HasAnimation(id) return animationReady and hasAnimation(self, id) end
function model:SetAnimation(id)
    animationStarts = animationStarts + 1
    setAnimation(self, id)
end
assert(WowVoice:ReplayQuest(179))
assert(model.portraitReady and model.animation == 0 and model.paused)
local soundCount = #plays
head.scripts.OnUpdate()
assert(not model.paused, 'restored model must leave the native paused state')
animationReady = true
now = now + 0.6
head.scripts.OnUpdate()
assert(model.animation == 60, 'late animation data must replace the idle fallback')
local started = animationStarts
now = now + 1
head.scripts.OnUpdate()
assert(animationStarts == started and #plays == soundCount, 'healthy animation and audio must not restart every update')

-- Completion callbacks must restart outside the native event, which can still
-- write the final pose after our handler returns.
model.scripts.OnAnimFinished(model)
model.animation = 0
head.scripts.OnUpdate()
assert(model.animation == 60)

-- The settings scale preview deliberately freezes the portrait; recovery may
-- not undo that pause, and pending work must be cancelled at stop/fade.
WowVoice:BeginHeadScalePreview()
started = animationStarts
model.scripts.OnAnimFinished(model)
head.scripts.OnUpdate()
assert(model.paused and animationStarts == started)
WowVoice:EndHeadScalePreview(true)
assert(not model.paused)
model.scripts.OnAnimFinished(model)
WowVoice:FinishTalkingHead(true)
head.scripts.OnUpdate()
assert(model.animation == 0)
WowVoice:Silence()
model.CompleteLoad, model.HasAnimation, model.SetAnimation = completeLoad, hasAnimation, setAnimation
print('PASS: cold reload recovers native animation reset, late talking data and completed loops without disturbing scale preview, fade or audio')

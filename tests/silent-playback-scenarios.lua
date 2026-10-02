event('ADDON_LOADED')
local WV, Q = WowVoice, WowVoice.questQueue
local loaded = {}
C_AddOns.IsAddOnLoaded = function(name) return loaded[name] == true end
event('PLAYER_LOGIN')
assert(not has('Не загружена основная база') and not has('Установите комплект'))
assert(not WV:HasQuestAudio(179) and WV:CanPresentQuest(179))
assert(WV:CanPresentQuest(999999) and not WV:CanPresentQuest(0) and not WV:CanPresentQuest(nil))
local realPlay, realStop, realCVar = PlaySoundFile, StopSound, SetCVar
function PlaySoundFile() error('Silent playback called PlaySoundFile') end
function StopSound() error('Silent playback called StopSound') end
function PlayMusic() error('Silent playback called PlayMusic') end
function StopMusic() error('Silent playback called StopMusic') end
function SetCVar() error('Silent playback changed sound settings') end
local function step(t)
    tick(t)
    local driver = frames.WowVoiceQuestQueueDriver
    if driver.visible then driver.scripts.OnUpdate() end
end
local function record(id, section, text)
    return { context = { questId = id, section = section or 'a', text = text or 'Текст задания',
        speaker = { npcID = 658, name = 'Собеседник' } } }
end

-- Every transport setting stays silent, including forced Music and background-off.
for _, channel in ipairs({'auto', 'music', 'sound'}) do
    for _, background in ipairs({'0', '1'}) do
        WowVoiceDB.channel = channel
        cvars.Sound_EnableSoundWhenGameIsInBG = background
        for _, section in ipairs({'a', 'p', 'c'}) do
            local item = record(179, section)
            local start = now
            assert(Q:Start(item) and Q.current == item and frames.WowVoiceTalkingHead:IsShown())
            assert(frames.WowVoiceTalkingHead.Body:GetText() == item.context.text)
            step(start + WowVoiceDur['179' .. section] - 0.001)
            assert(Q.current == item)
            step(start + WowVoiceDur['179' .. section] + 0.001)
            assert(not Q.current and item.status == 'done')
            Q:Clear()
        end
    end
end

-- Non-indexed quests use reading time, including Cyrillic text and all stages.
local text = string.rep('Слово ', 60)
assert(WV:SilentDuration(record(999999, 'a', text).context) == 22)
assert(WV:SilentDuration(record(999999, 'c', '').context) == 4)
questID = 999999
event('QUEST_DETAIL')
assert(Q.current.context.questId == 999999 and frames.WowVoiceTalkingHead:IsShown())
Q:Event('QUEST_ACCEPTED', questID)
Q:Clear()
assert(WV:ReplayQuest(179) and frames.WowVoiceTalkingHead:IsShown())
assert(not (WowVoiceDB.listenedQuests and WowVoiceDB.listenedQuests[playerGUID]
    and WowVoiceDB.listenedQuests[playerGUID][179]), 'Silent reading must not mark audio as listened')
Q:Clear()

-- Timers, skip and an explicitly paused playlist all use the normal queue.
local first, second = record(999998, 'a', text), record(999999, 'a', text)
Q:Add(first); Q:Add(second)
local start = now
assert(Q:Start(first))
step(start + 22.001)
assert(Q.gap and first.status == 'done')
step(Q.gap.deadline + 0.001)
assert(Q.current == second)
Q:Clear()
first, second = record(179), record(192)
Q:Add(first); Q:Add(second); assert(Q:Start(first))
frames.WowVoiceTalkingHead.Close.scripts.OnClick()
step(now + 0.001)
assert(Q.current == second and not Q.paused and WowVoiceDB.queueAutoPlay)
Q:Clear()
first, second = record(179), record(192)
Q:Add(first); Q:Add(second); assert(Q:Start(first))
WV:SetQueueAutoPlay(false)
frames.WowVoiceTalkingHead.Close.scripts.OnClick()
step(now + 100)
assert(not Q.current and Q:Waiting() == second and Q.paused)
Q:Clear()
WV:SetQueueAutoPlay(true)

-- Reload persistence retains silent records just like voiced ones.
first, second = record(179), record(192)
Q:Add(first); Q:Add(second); assert(Q:Start(first))
Q:SaveSession()
local saved = WowVoiceQueueDB
Q:Clear()
WowVoiceQueueDB = saved
Q:RestoreSession()
step(now + 0.001)
assert(Q.current and Q.current.context.questId == 179)
Q:Clear()

-- Enabling CatQuest later applies on the next start; silent playback does not restart.
first = record(179)
assert(Q:Start(first))
loaded.CatQuest_Voices = true
WV:RefreshAudioSources()
assert(Q.current == first and WV:HasQuestAudio(179))
PlaySoundFile, StopSound, SetCVar = realPlay, realStop, realCVar
WowVoiceDB.channel = 'auto'
cvars.Sound_EnableSoundWhenGameIsInBG = '1'
assert(WV:ReplayQuest(179) and plays[#plays].file:find('CatQuest_Voices', 1, true))
Q:Clear()
print('PASS: no-library heads/queue, zero audio or CVar calls, exact/reading timers, skip/pause, saved queue and late CatQuest')

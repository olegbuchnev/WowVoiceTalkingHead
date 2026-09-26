--[[ WowVoice: quest voice-over using pregenerated audio.

How it works:
  1. Listen for quest dialog events (accept / progress / complete).
  2. Read the quest title and NPC name (or entry ID).
  3. Resolve quest_id through WowVoiceIndex. Titles are not unique, so
     distinguish candidates by NPC and the length of the displayed text.
  4. Play Interface\AddOns\WowVoiceSounds\<quest_id><section>.mp3.

Compatibility: 3.3.5a and modern Classic clients. Playback encapsulates API
differences: older clients cannot stop PlaySoundFile, so they use
PlayMusic/StopMusic by default.
]]

local ADDON = "WowVoice"
local SOUND_ADDON = "WowVoiceSounds"

-- Text sections: a = accept, p = progress, c = complete
local SECTION = { accept = "a", progress = "p", complete = "c" }

local defaults = {
    enabled  = true,
    autoPlayAccept = true, -- Automatically play quest descriptions unless opted out
    autoPlayTurnIn = true, -- Both progress dialogue and the final quest reward dialogue
    trackerButtons = true, -- Replay controls beside tracked quest titles
    trackerProgressPulse = true, -- Silent replay reminder when quest objectives change
    channel  = "auto",   -- auto | sound | music
    ext      = "ogg",    -- Sound pack format: ogg | mp3
    stopmode = "silence",-- Music silencing method: silence | cvar | stopmusic
    button   = "auto",   -- Stop button mode: auto | always | off
    volume   = 1.0,      -- Voice volume on the music channel, 0..1
    tail     = 0.05,     -- Stop time offset in seconds. The timer measures
                         -- duration from the PlayMusic CALL, but buffering
                         -- delays the actual audio slightly. Shift the stop
                         -- time to avoid cutting off the ending. Listening
                         -- tests found 0.05 to match the end. OGG files have
                         -- no trailing silence, so this is purely an offset.
                         -- Larger values let PlayMusic loop and briefly
                         -- repeat the start. Fine-tune with /wv tail 0.1
                         -- if the ending is cut off, or 0 if it repeats.
    debug    = false,
    ducknpc  = true,     -- Mute the NPC greeting on the Dialog channel
                         -- so it does not overlap our voice-over
}

local WV = {}
_G.WowVoice = WV

--------------------------------------------------------------------- Utilities

local function msg(fmt, ...)
    local text = select("#", ...) > 0 and format(fmt, ...) or fmt
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff" .. ADDON .. "|r: " .. text)
end

local function dbg(fmt, ...)
    if WowVoiceDB and WowVoiceDB.debug then
        msg("[Forever %.3f] " .. fmt, GetTime(), ...)
    end
end

-- String length in bytes: index text lengths use the same UTF-8 byte counts,
-- so comparisons remain valid without decoding individual characters.
local function blen(s)
    return s and #s or 0
end

--[[ NPC entry ID from a GUID.
     Modern client: "Creature-0-3777-0-128-1234-000078EF2C" -> field 6.
     3.3.5a: "0xF130007C4A000123" -> F130 | entry (6 hex) | counter (6 hex).
     Verify parsing in a live 3.3.5a client: some builds use a different
     layout, so the NPC name remains the primary key.
]]
local function npcIdFromGUID(guid)
    if not guid then return nil end
    if strfind(guid, "-") then
        local kind, _, _, _, _, id = strsplit("-", guid)
        if kind == "Creature" or kind == "Vehicle" or kind == "GameObject" then
            return tonumber(id)
        end
        return nil
    end
    local hex = gsub(guid, "^0[xX]", "")
    if #hex == 16 then
        return tonumber(strsub(hex, 5, 10), 16)
    end
    return nil
end

local function currentNPC()
    local name = UnitName("npc") or UnitName("questnpc") or UnitName("target")
    local guid = UnitGUID("npc") or UnitGUID("questnpc") or UnitGUID("target")
    return name, npcIdFromGUID(guid)
end

--------------------------------------------------------------------- Playback

local Playback = {}
do
    -- Modern clients return a PlaySoundFile handle and support StopSound.
    local canStopSound = (type(StopSound) == "function")
    local handle, playing = nil, false

    --[[ PlayMusic loops the file, so stop it when the duration from
         Durations.lua expires. Unknown durations use a fallback limit to
         prevent endless playback. Track time in OnUpdate because 3.3.5a
         does not provide C_Timer.
]]
    local FALLBACK_LIMIT = 180      -- Seconds to play when the duration is unknown
    local stopAt = nil
    local restoreAt, musicWasOn = nil, nil
    local savedVol, savedEnable = nil, nil
    local savedDialog, savedDialogVol = nil, nil

    local SILENCE = "Interface\\AddOns\\" .. SOUND_ADDON .. "\\silence.ogg"

    --[[ Music-channel playback depends on Sound_MusicVolume and
         Sound_EnableMusic. Quiet or disabled music makes the voice inaudible,
         and switching characters can reset that state. Enable music and set
         its volume before EVERY playback, then restore the previous values
         when playback stops.
]]
    local function forceAudio()
        if savedVol == nil then                      -- Save the original value once
            savedVol = GetCVar("Sound_MusicVolume")
            savedEnable = GetCVar("Sound_EnableMusic")
        end
        SetCVar("Sound_EnableMusic", "1")
        local v = (WowVoiceDB and WowVoiceDB.volume) or 1.0
        SetCVar("Sound_MusicVolume", tostring(v))
    end

    local function restoreAudio()
        if savedVol ~= nil then
            SetCVar("Sound_MusicVolume", savedVol)
            SetCVar("Sound_EnableMusic", savedEnable or "1")
            savedVol, savedEnable = nil, nil
        end
    end

    --[[ NPC greetings use the Dialog channel and can overlap our voice-over
         on Master. Temporarily suppress Dialog in two ways:
           Sound_EnableDialog=0 prevents NEW lines from starting.
           Sound_DialogVolume=0 mutes a line ALREADY PLAYING, since volume
                                changes apply immediately. Disabling the
                                channel alone does not interrupt a greeting
                                that started before us, such as during gossip.
         Restore both CVars after playback. Modern clients only:
         3.3.5a does not use these CVars or this playback path.
]]
    local function duckNPC()
        if not (WowVoiceDB and WowVoiceDB.ducknpc) then
            dbg("Dialog duck: пропущено, ducknpc=false")
            return
        end
        if GetCVar("Sound_EnableDialog") == nil then
            dbg("Dialog duck: пропущено, Sound_EnableDialog отсутствует")
            return
        end
        if savedDialog == nil then
            savedDialog = GetCVar("Sound_EnableDialog")
            savedDialogVol = GetCVar("Sound_DialogVolume")
        end
        SetCVar("Sound_EnableDialog", "0")
        SetCVar("Sound_DialogVolume", "0")
        dbg("Dialog duck: saved enable=%s volume=%s; current enable=%s volume=%s",
            tostring(savedDialog), tostring(savedDialogVol),
            tostring(GetCVar("Sound_EnableDialog")), tostring(GetCVar("Sound_DialogVolume")))
    end

    local function unduckNPC()
        if savedDialog ~= nil then
            dbg("Dialog restore: begin enable=%s volume=%s",
                tostring(savedDialog), tostring(savedDialogVol))
            SetCVar("Sound_EnableDialog", savedDialog)
            if savedDialogVol ~= nil then SetCVar("Sound_DialogVolume", savedDialogVol) end
            dbg("Dialog restore: done enable=%s volume=%s",
                tostring(GetCVar("Sound_EnableDialog")), tostring(GetCVar("Sound_DialogVolume")))
            savedDialog, savedDialogVol = nil, nil
        end
    end

    --[[ Closing the quest window intentionally leaves the voice playing.
         The player can keep listening or stop it with the button.
         The timer is only needed to prevent PlayMusic from looping.
]]
    local ticker = CreateFrame("Frame", "WowVoiceTicker")
    ticker:Hide()

    --[[ Live testing on 3.3.5a showed that StopMusic() does not interrupt
         a file started by PlayMusic. Select a workaround with /wv stopmode
         and check it with /wv stoptest:
           silence   replaces the current stream with a short silent file.
           cvar      briefly disables the music channel.
           stopmusic calls StopMusic() alone (does not work on Sirus).
]]
    local function killMusic()
        local how = (WowVoiceDB and WowVoiceDB.stopmode) or "silence"
        if how == "stopmusic" then
            StopMusic()
        elseif how == "cvar" then
            StopMusic()
            musicWasOn = GetCVar("Sound_EnableMusic")
            SetCVar("Sound_EnableMusic", "0")
            restoreAt = GetTime() + 0.25
            ticker:Show()
        else
            PlayMusic(SILENCE)
            StopMusic()
        end
        dbg("глушу музыку способом «%s»", how)
    end

    ticker:SetScript("OnUpdate", function()
        local now = GetTime()
        if restoreAt and now >= restoreAt then
            SetCVar("Sound_EnableMusic", musicWasOn or "1")
            restoreAt = nil
            if not stopAt then ticker:Hide() end
        end
        if not stopAt then return end
        if now >= stopAt then
            dbg("таймер длительности истёк: stopAt=%.3f", stopAt)
            Playback:Stop("duration timer")
            WV.lastKey = nil        -- Allow replay when the quest is opened again
        end
    end)

    --[[ Select the sound channel only when playback can be stopped.
         3.3.5a has no StopSound, so it always uses the music channel even
         when the user selects sound.
]]
    function Playback:mode()
        local pick = (WowVoiceDB and WowVoiceDB.channel) or "auto"
        if pick == "sound" and not canStopSound then return "music" end
        if pick ~= "auto" then return pick end
        return canStopSound and "sound" or "music"
    end

    function Playback:Stop(reason)
        stopAt = nil
        if not restoreAt then ticker:Hide() end
        if not playing then
            -- The audio can already be over while its portrait is fading out.
            if WV.StopTalkingHead then WV:StopTalkingHead() end
            return
        end
        playing = false
        if handle and canStopSound then
            dbg("StopSound: begin handle=%s reason=%s", tostring(handle), tostring(reason or "manual"))
            StopSound(handle)
            dbg("StopSound: done handle=%s", tostring(handle))
            handle = nil
        elseif self.usedMusic then
            killMusic()
            restoreAudio()
            self.usedMusic = false
        end
        unduckNPC()                      -- Restore the Dialog channel (NPC greetings)
        if reason == "duration timer" and WV.FinishTalkingHead then
            WV:FinishTalkingHead()
        elseif WV.StopTalkingHead then WV:StopTalkingHead() end
        if WV.OnPlaybackChanged then WV.OnPlaybackChanged(false) end
    end

    -- duration: voice line length, or nil if unknown
    function Playback:Play(path, duration, context)
        local descriptionQuest = context and context.section == "a" and context.questId
        local mode = self:mode()
        dbg("Playback: mode=%s duration=%s path=%s", tostring(mode), tostring(duration), path)
        if mode == "music" then
            dbg("PlayMusic: резервный режим, приглушение Dialog здесь не применяется")
            -- The new file replaces the current stream; no explicit stop is needed.
            stopAt = nil
            forceAudio()                 -- Enable music and apply the requested volume
            PlayMusic(path)
            self.usedMusic, playing = true, true
            if descriptionQuest and WV.MarkQuestListened then WV:MarkQuestListened(descriptionQuest) end
            local tail = (WowVoiceDB and WowVoiceDB.tail) or 0.05
            stopAt = GetTime() + (duration or FALLBACK_LIMIT) + tail
            ticker:Show()
            if WV.StartTalkingHead then WV:StartTalkingHead(context, stopAt, duration) end
            if WV.OnPlaybackChanged then WV.OnPlaybackChanged(true) end
            return true
        end
        self:Stop("new playback")
        if not canStopSound then
            -- On 3.3.5a, PlaySoundFile takes one argument and returns no values,
            -- so Lua cannot determine whether playback succeeded.
            PlaySoundFile(path)
            playing = true
            if descriptionQuest and WV.MarkQuestListened then WV:MarkQuestListened(descriptionQuest) end
            return true
        end
        duckNPC()                        -- Mute the NPC greeting for the duration of the voice line
        dbg("PlaySoundFile: begin channel=Master path=%s", path)
        local ok, h = PlaySoundFile(path, "Master")
        dbg("PlaySoundFile: result=%s handle=%s", tostring(ok), tostring(h))
        if ok then
            handle, playing = h, true
            if descriptionQuest and WV.MarkQuestListened then WV:MarkQuestListened(descriptionQuest) end
            -- Show the Stop button in auto mode and schedule a stop
            -- using the duration table for this exact sound pack.
            -- The timer calls StopSound and restores Dialog; a duration table
            -- from another pack could cut the voice line short.
            local tail = (WowVoiceDB and WowVoiceDB.tail) or 0.05
            stopAt = GetTime() + (duration or FALLBACK_LIMIT) + tail
            dbg("таймер: duration=%s tail=%.3f stopAt=%.3f",
                tostring(duration or FALLBACK_LIMIT), tail, stopAt)
            ticker:Show()
            if WV.StartTalkingHead then WV:StartTalkingHead(context, stopAt, duration) end
            if WV.OnPlaybackChanged then WV.OnPlaybackChanged(true) end
            return true
        end
        unduckNPC()                      -- Playback failed; restore the Dialog channel
        return false
    end

    function Playback:canStop() return canStopSound end
end

--------------------------------------------------------------------- Quest lookup

--[[ Normalize titles by mapping Cyrillic yo to ye, preserving case.
     The index uses yo, while Russian 3.3.5a clients (Sirus and official)
     return titles with ye. Different UTF-8 bytes (yo=D1 91, ye=D0 B5)
     break exact matches for about 430 titles. Normalize both sides to
     match either spelling while keeping the original index unchanged.
]]
local function normTitle(s)
    if not s then return s end
    s = gsub(s, "\209\145", "\208\181")   -- Lowercase Cyrillic yo -> ye
    s = gsub(s, "\208\129", "\208\149")   -- Uppercase Cyrillic yo -> ye
    return s
end

-- Return quest_id or nil. Find candidates by title, then filter by NPC
-- and use the closest text length to distinguish remaining candidates.
function WV:Resolve(title, section, shownText)
    local index = _G.WowVoiceIndex
    if not index then return nil, "нет индекса (Index.lua)" end

    local list = index[title]
    if not list then
        -- Fallback to normalized titles (Cyrillic yo/ye). Build the map once.
        local norm = WV._indexNorm
        if not norm then
            norm = {}
            for name, l in pairs(index) do
                local nn = normTitle(name)
                if norm[nn] == nil then norm[nn] = l end
            end
            WV._indexNorm = norm
        end
        list = norm[normTitle(title)]
    end
    if not list then return nil, "квест не найден в индексе" end

    local npcName, npcId = currentNPC()

    -- Select the speaking NPC: accept uses the GIVER (i/n), while
    -- progress/complete use the RECEIVER (ei/en). Same-title quests may
    -- have different givers but share a receiver (BC quests 458/459).
    -- Filtering completion by giver picked the wrong quest. The index stores
    -- ei/en only when the receiver differs from the giver; otherwise use i/n.
    local isEnd = (section == "c" or section == "p")

    -- Filter by NPC if one is known
    local pool = {}
    if npcName or npcId then
        for i = 1, #list do
            local e = list[i]
            local eid = (isEnd and e.ei) or e.i
            local enm = (isEnd and e.en) or e.n
            if (npcId and eid == npcId) or (npcName and enm == npcName) then
                pool[#pool + 1] = e
            end
        end
    end
    if #pool == 0 then pool = list end
    if #pool == 1 then return pool[1].q end

    -- Distinguish remaining candidates by displayed text length
    local want = blen(shownText)
    local best, bestDiff
    for i = 1, #pool do
        local e = pool[i]
        local stored = e[section]
        if stored then
            local diff = math.abs(stored - want)
            if not bestDiff or diff < bestDiff then
                best, bestDiff = e, diff
            end
        end
    end
    if best then
        dbg("развод по длине: %d кандидатов, взят quest %d (|%d-%d|=%d)",
            #pool, best.q, want, best[section] or -1, bestDiff or -1)
        return best.q
    end
    return pool[1].q
end

--[[ Voice file path. Licensed installations use hashed filenames:
     HMAC-SHA256(content_key, "179a")[:32] .. ".ogg". The installer renames
     files the same way; Hash.lua and Python produce identical results.
     Without a license (the deploy_addon.py development pack), filenames
     use canonical keys such as "179a.ogg".
]]
WV._nameCache = {}
local function foreverAudio(questId, section)
    local key = tostring(questId) .. section
    -- Never replace a recording from the original pack, even if an imported
    -- entry overlaps after a future pack update.
    if _G.WowVoiceDur and _G.WowVoiceDur[key] then return nil end
    local entries = _G.WowVoiceForeverAudio
    local entry = entries and entries[key]
    if not entry then return nil end
    if entry.male then
        return (type(UnitSex) == "function" and UnitSex("player") == 3)
            and entry.female or entry.male
    end
    return entry
end

function WV:SoundPath(questId, section)
    local key = tostring(questId) .. section
    local duration = _G.WowVoiceDur and _G.WowVoiceDur[key]
    local extra = foreverAudio(questId, section)
    if extra then
        return "Interface\\AddOns\\CatVoices\\" .. extra.file, extra.duration
    end
    if not duration and _G.WowVoiceForeverAudio and _G.WowVoiceForeverAudio[questId .. "a"] then
        -- The supplemental pack has no progress lines and few turn-ins.
        -- Do not substitute the description for a missing quest section.
        return nil
    end
    local secret = WV.license and WV.license.content_key
    if secret and secret ~= "" and WowVoiceHash then
        local name = WV._nameCache[key]
        if not name then
            name = WowVoiceHash.filename(secret, key)
            WV._nameCache[key] = name
        end
        return "Interface\\AddOns\\" .. SOUND_ADDON .. "\\" .. name, duration
    end
    local ext = (WowVoiceDB and WowVoiceDB.ext) or "ogg"
    return "Interface\\AddOns\\" .. SOUND_ADDON .. "\\" .. key .. "." .. ext, duration
end

--------------------------------------------------------------------- Logic

WV.lastKey = nil

-- Get the actual questID from the displayed quest dialog. Modern clients
-- (MoP Classic, Classic Era, Anniversary, Retail) return the exact ID via
-- GetQuestID(). This avoids title/length guesses and mix-ups between
-- class, faction or race variants sharing a title. On 3.3.5a the API
-- is unavailable; return nil and fall back to WV:Resolve using text.
local function shownQuestID()
    if type(GetQuestID) == "function" then
        local ok, id
        if WowVoiceDB and WowVoiceDB.debug then
            -- In debug mode, let API errors reach the default handler with
            -- their original source line and full stack instead of using pcall.
            dbg("GetQuestID: begin")
            ok, id = true, GetQuestID()
            dbg("GetQuestID: result=%s type=%s", tostring(id), type(id))
        else
            ok, id = pcall(GetQuestID)
        end
        if ok and type(id) == "number" and id > 0 then return id end
    end
    dbg("GetQuestID: нет положительного ID, используется существующий Resolve")
    return nil
end

function WV:Speak(section, title, text, event)
    dbg("Speak: event=%s section=%s title=%s", tostring(event), tostring(section), tostring(title))
    local questId = shownQuestID()
    if not questId then
        -- Legacy client without questID API: resolve by title, text and NPC.
        if not title or title == "" then return end
        local err
        questId, err = self:Resolve(title, section, text)
        if not questId then
            dbg("«%s»: %s", title, err or "не разрешён")
            return
        end
    end

    -- Capture the quest giver even when voice-over is disabled or OGG is missing.
    local context = self.CaptureQuestSpeaker and self:CaptureQuestSpeaker(questId, section, title, text)
    if not (WowVoiceDB and WowVoiceDB.enabled) then
        dbg("Speak: пропущено, enabled=false")
        return
    end
    if section == SECTION.accept and WowVoiceDB.autoPlayAccept ~= true then
        dbg("Speak: пропущено, autoPlayAccept=false")
        return
    end
    if (section == SECTION.progress or section == SECTION.complete) and WowVoiceDB.autoPlayTurnIn == false then
        dbg("Speak: пропущено, autoPlayTurnIn=false")
        return
    end

    local key = questId .. section
    local path, dur = self:SoundPath(questId, section)
    if not path then
        dbg("нет записи для квеста %s, секция %s", tostring(questId), section)
        return
    end
    dbg("выбор: event=%s questID=%s section=%s title=%s",
        tostring(event), tostring(questId), section, tostring(title))
    dbg("аудио: key=%s WowVoiceDur=%s duration=%s path=%s",
        key, tostring(_G.WowVoiceDur ~= nil and _G.WowVoiceDur[key] ~= nil), tostring(dur), path)
    if key == self.lastKey then
        dbg("Speak: повтор ключа %s, PlaySoundFile не вызывается", key)
        return
    end
    self.lastKey = key

    -- Play strictly by questID. If a file is missing or its section was
    -- intentionally omitted, stay silent instead of substituting another quest.
    dbg("играю %s (квест %d, секция %s, длительность %s)",
        path, questId, section, dur and format("%.1f с", dur) or "неизвестна")
    local ok = Playback:Play(path, dur, context)
    if section == SECTION.accept then self:SetQuestAudioAvailable(questId, ok) end
    if not ok then
        dbg("файл не проигрался: %s", path)
    end
end

function WV:SetAutoPlayAcceptEnabled(enabled)
    WowVoiceDB.autoPlayAccept = enabled == true
    if self.RefreshHeadOptions then self:RefreshHeadOptions() end
end

function WV:SetAutoPlayTurnInEnabled(enabled)
    WowVoiceDB.autoPlayTurnIn = enabled == true
    if self.RefreshHeadOptions then self:RefreshHeadOptions() end
end

function WV:Silence(reason)
    Playback:Stop(reason or "manual silence")
    self.lastKey = nil
end

-- Journal IDs belong to their row or details panel; GetQuestID() refers
-- to the NPC dialog. Manual replay bypasses Speak and its lastKey filter.
-- Keep runtime failures out of SavedVariables: repaired files can be retried
-- after reload, or restored by a successful automatic description playback.
local unavailableQuestAudio = {}
function WV:SetQuestAudioAvailable(questId, available)
    local unavailable = not available or nil
    if unavailableQuestAudio[questId] == unavailable then return end
    unavailableQuestAudio[questId] = unavailable
    if self.RefreshJournalButtons then self:RefreshJournalButtons() end
    if self.RefreshTrackerButtons then self:RefreshTrackerButtons() end
end

function WV:HasQuestAudio(questId)
    return type(questId) == "number" and questId > 0
        and not unavailableQuestAudio[questId]
        and ((_G.WowVoiceDur ~= nil and _G.WowVoiceDur[questId .. "a"] ~= nil)
            or foreverAudio(questId, "a") ~= nil)
end

function WV:ReplayQuest(questId)
    if not (WowVoiceDB and WowVoiceDB.enabled) then
        msg("озвучка выключена. Включить: /wv on")
        return false
    end
    if not self:HasQuestAudio(questId) then
        msg("для описания этого квеста нет записи в установленном аудиопаке")
        return false
    end
    local key = questId .. "a"
    local path, duration = self:SoundPath(questId, "a")
    dbg("журнал: повтор questID=%s key=%s path=%s", tostring(questId), key, path)
    local context = self.GetReplaySpeaker and self:GetReplaySpeaker(questId)
    local ok = Playback:Play(path, duration, context)
    self:SetQuestAudioAvailable(questId, ok)
    self.lastKey = ok and key or nil
    if not ok then msg("не удалось воспроизвести описание квеста %d", questId) end
    return ok
end

--------------------------------------------------------------------- Events

--[[ The complete release contains both sound folders. If a folder's
     marker addon is missing/disabled, explain how to reinstall the bundle.
     Check at PLAYER_LOGIN, after all addons have loaded, to avoid false
     warnings caused by addon load order.
]]
local function warnIfNoSounds()
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if not isLoaded then return end
    if isLoaded(SOUND_ADDON) and isLoaded("CatVoices") then return end
    msg("|cffff2020Не все звуковые паки установлены или включены.|r")
    msg("Скопируйте из архива все три папки: WowVoice, WowVoiceSounds и CatVoices в _classic_beta_\\Interface\\AddOns.")
    msg("Включите их в списке модификаций и полностью перезапустите игру.")
end

local f = CreateFrame("Frame", "WowVoiceFrame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("QUEST_DETAIL")
f:RegisterEvent("QUEST_PROGRESS")
f:RegisterEvent("QUEST_COMPLETE")
f:RegisterEvent("PLAYER_LOGOUT")

f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        WowVoiceDB = WowVoiceDB or {}
        WowVoiceDB.playTooltips = nil -- Removed setting; our controls no longer show tooltips.
        for k, v in pairs(defaults) do
            if WowVoiceDB[k] == nil then WowVoiceDB[k] = v end
        end
        -- Correct the disabled default from the unreleased options build once.
        -- Later checkbox choices, including false, survive subsequent loads.
        if not WowVoiceDB.autoPlayAcceptDefaultOnApplied then
            WowVoiceDB.autoPlayAccept = true
            WowVoiceDB.autoPlayAcceptDefaultOnApplied = true
        end
        -- Diagnostics are enabled manually for the current session and reset
        -- after /reload or the next login.
        WowVoiceDB.debug = false
        --[[ Tail migrations: successive builds automatically used 0 (cut off
             endings), 0.3 (about 0.2 seconds of repeated audio), 0.1 (still
             slightly too long), then 0.05 (matched the ending by ear).
             Each migration changes ONLY the previous automatic value,
             preserving manual /wv tail settings. The current default is 0.05.
]]
        if not WowVoiceDB.tailMigrated then
            WowVoiceDB.tail = defaults.tail          -- 0 -> default (fresh installation)
            WowVoiceDB.tailMigrated = true
        end
        if not WowVoiceDB.tail2Migrated then         -- Automatic 0.3 -> default
            if WowVoiceDB.tail and WowVoiceDB.tail > 0.25 and WowVoiceDB.tail < 0.35 then
                WowVoiceDB.tail = defaults.tail
            end
            WowVoiceDB.tail2Migrated = true
        end
        if not WowVoiceDB.tail3Migrated then         -- Automatic 0.1 from an intermediate build -> default
            if WowVoiceDB.tail and WowVoiceDB.tail > 0.08 and WowVoiceDB.tail < 0.12 then
                WowVoiceDB.tail = defaults.tail
            end
            WowVoiceDB.tail3Migrated = true
        end
        WV.license = _G.WowVoiceLicense   -- Installer marker, or nil in development
        local n = 0
        if _G.WowVoiceIndex then for _ in pairs(_G.WowVoiceIndex) do n = n + 1 end end
        msg("загружен. Квестов в индексе: %d. Команды: /wv", n)
        -- Free CurseForge build: no license; show the Boosty donation message.
        if not (WV.license and WV.license.key) then
            msg("|cffffd100Понравился WowVoice? Угости разработчика пивом на Boosty|r — набери /wv boosty")
        end

        if WV.RestoreButton then WV:RestoreButton() end

    elseif event == "PLAYER_LOGIN" then
        warnIfNoSounds()

    elseif event == "QUEST_DETAIL" then
        dbg("event=%s section=a; чтение GetTitleText/GetQuestText", event)
        WV:Speak(SECTION.accept, GetTitleText(), GetQuestText(), event)

    elseif event == "QUEST_PROGRESS" then
        dbg("event=%s section=p; чтение GetTitleText/GetProgressText", event)
        WV:Speak(SECTION.progress, GetTitleText(), GetProgressText(), event)

    elseif event == "QUEST_COMPLETE" then
        dbg("event=%s section=c; чтение GetTitleText/GetRewardText", event)
        WV:Speak(SECTION.complete, GetTitleText(), GetRewardText(), event)

    elseif event == "PLAYER_LOGOUT" then
        WV:Silence("PLAYER_LOGOUT")
    end
end)

--------------------------------------------------------------------- Commands

--[[ Donation link. WoW cannot open URLs from chat, so /wv boosty
     shows a selectable field for copying into a browser with Ctrl+C.
     Select its text automatically and undo edits to protect the address.
     The editBox location varies: 3.3.5a uses the global "<popup>EditBox",
     while modern clients use self.editBox. Support both forms.
]]
local BOOSTY_URL = "https://boosty.to/wowvoice"
StaticPopupDialogs["WOWVOICE_BOOSTY"] = {
    text = "Спасибо, что поддерживаешь WowVoice! |cffffd100Ctrl+C|r скопирует ссылку — вставь её в браузер:",
    button1 = "Закрыть",
    hasEditBox = true,
    editBoxWidth = 260,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,          -- Reduce taint risk on modern clients
    OnShow = function(self)
        local eb = self.editBox or self.EditBox
                   or _G[(self.GetName and self:GetName() or "") .. "EditBox"]
        if eb then
            eb:SetText(BOOSTY_URL)
            eb:SetCursorPosition(0)
            eb:HighlightText()
            eb:SetFocus()
        end
    end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    EditBoxOnTextChanged = function(self)     -- Prevent accidental removal of the address
        if self:GetText() ~= BOOSTY_URL then
            self:SetText(BOOSTY_URL)
            self:HighlightText()
        end
    end,
}

SLASH_WOWVOICE1 = "/wv"
SLASH_WOWVOICE2 = "/wowvoice"
SlashCmdList["WOWVOICE"] = function(input)
    local cmd, rest = strsplit(" ", strtrim(input or ""), 2)
    cmd = strlower(cmd or "")

    if cmd == "on" or cmd == "off" then
        WowVoiceDB.enabled = (cmd == "on")
        if not WowVoiceDB.enabled then WV:Silence() end
        msg("озвучка %s", WowVoiceDB.enabled and "включена" or "выключена")

    elseif cmd == "stop" then
        WV:Silence()
        msg("остановлено")

    elseif cmd == "channel" then
        rest = strlower(rest or "")
        if rest == "auto" or rest == "sound" or rest == "music" then
            WowVoiceDB.channel = rest
            msg("канал: %s (сейчас работает: %s)", rest, Playback:mode())
            if rest == "sound" and not Playback:canStop() then
                msg("|cffff8800на этом клиенте канал sound остановить нечем —|r")
                msg("оставлен музыкальный, иначе реплику было бы не оборвать.")
            end
        else
            msg("канал: %s. Варианты: auto | sound | music", WowVoiceDB.channel)
        end

    elseif cmd == "ext" then
        rest = strlower(rest or "")
        if rest == "mp3" or rest == "ogg" then
            WowVoiceDB.ext = rest
            msg("формат пака: %s", rest)
        else
            msg("формат пака: %s. Варианты: mp3 | ogg", WowVoiceDB.ext)
        end

    elseif cmd == "button" then
        if not WV.ButtonMode then
            msg("UI.lua не загружен — кнопки нет. Новый файл в TOC клиент видит")
            msg("только при запуске: выйди из игры полностью и зайди заново.")
            return
        end
        rest = strlower(rest or "")
        if rest == "auto" or rest == "always" or rest == "off" then
            WV:ButtonMode(rest)
            msg("кнопка остановки: %s", rest)
        elseif rest == "reset" then
            WV:ResetButton()
            msg("кнопка возвращена на середину экрана")
        else
            msg("кнопка: %s. Варианты: auto | always | off | reset",
                WowVoiceDB.button)
        end

    elseif cmd == "volume" or cmd == "vol" then
        local v = tonumber(rest)
        if v and v >= 0 and v <= 1 then
            WowVoiceDB.volume = v
            msg("громкость реплик: %.2f (применится к следующей)", v)
        else
            msg("громкость: %.2f. Задать: /wv volume 0..1 (напр. 1.0)",
                WowVoiceDB.volume)
        end

    elseif cmd == "tail" then
        local v = tonumber(rest)
        if v ~= nil and v >= -3 and v <= 3 then
            WowVoiceDB.tail = v
            msg("сдвиг остановки: %+.2f с (минус = раньше конца, против лупа)", v)
        else
            msg("сдвиг остановки: %+.2f с. Задать: /wv tail 0.1 (дольше) / 0 (короче, против лупа)",
                WowVoiceDB.tail)
        end

    elseif cmd == "stopmode" then
        rest = strlower(rest or "")
        if rest == "silence" or rest == "cvar" or rest == "stopmusic" then
            WowVoiceDB.stopmode = rest
            msg("способ остановки: %s", rest)
        else
            msg("способ остановки: %s. Варианты: silence | cvar | stopmusic",
                WowVoiceDB.stopmode)
        end

    elseif cmd == "stoptest" then
        --[[ Play a voice line, then attempt to stop it after three seconds
             using the selected method. Continued audio means the method failed.
]]
        local path = WV:SoundPath(179, "a")
        msg("канал: %s | способ остановки: %s", Playback:mode(), WowVoiceDB.stopmode)
        msg("играю 179a, оборву через 3 с — слушай, замолчит ли")
        Playback:Play(path, 60)
        local t = CreateFrame("Frame")
        local since = 0
        t:SetScript("OnUpdate", function(self, elapsed)
            since = since + elapsed
            if since >= 3 then
                self:SetScript("OnUpdate", nil)
                Playback:Stop("stoptest")
                msg("остановка вызвана. Если звук идёт — попробуй другой stopmode")
            end
        end)

    elseif cmd == "duck" then
        rest = strlower(rest or "")
        if rest == "on" or rest == "off" then
            WowVoiceDB.ducknpc = (rest == "on")
        end
        msg("глушение приветствия NPC: %s. Переключить: /wv duck on|off",
            WowVoiceDB.ducknpc and "вкл" or "выкл")

    elseif cmd == "debug" then
        rest = strlower(strtrim(rest or ""))
        if rest == "on" then
            WowVoiceDB.debug = true
        elseif rest == "off" then
            WowVoiceDB.debug = false
        elseif rest == "" then
            WowVoiceDB.debug = not WowVoiceDB.debug
        else
            msg("использование: /wv debug on|off")
            return
        end
        msg("отладка %s", WowVoiceDB.debug and "включена" or "выключена")

    elseif cmd == "options" then
        if WV.OpenOptions then WV:OpenOptions() end

    elseif cmd == "head" then
        if WV.HeadCommand then WV:HeadCommand(strlower(rest or "")) end

    elseif cmd == "diag" then
        local ver, build, _, iface = GetBuildInfo()
        local n = 0
        if _G.WowVoiceIndex then for _ in pairs(_G.WowVoiceIndex) do n = n + 1 end end
        msg("клиент %s (сборка %s, интерфейс %s)", tostring(ver), tostring(build),
            tostring(iface))
        msg("Forever: WOW_PROJECT_ID=%s | C_AddOns=%s", tostring(WOW_PROJECT_ID), type(C_AddOns))
        msg("GetQuestID=%s | GetTitleText=%s | GetQuestText=%s",
            type(GetQuestID), type(GetTitleText), type(GetQuestText))
        msg("GetProgressText=%s | GetRewardText=%s", type(GetProgressText), type(GetRewardText))
        msg("Dialog: Sound_EnableDialog=%s | Sound_DialogVolume=%s",
            tostring(GetCVar("Sound_EnableDialog")), tostring(GetCVar("Sound_DialogVolume")))
        msg("PlaySoundFile: %s | StopSound: %s | PlayMusic: %s",
            type(PlaySoundFile), type(StopSound), type(PlayMusic))
        msg("канал: %s (настройка %s), остановка звука: %s",
            Playback:mode(), WowVoiceDB.channel,
            Playback:canStop() and "поддерживается" or "нет, откат на музыку")
        msg("громкость реплик: %.2f | сдвиг остановки: %+.2f с",
            WowVoiceDB.volume, WowVoiceDB.tail)
        msg("сейчас в клиенте: музыка %s, громкость музыки %s",
            GetCVar("Sound_EnableMusic") == "1" and "вкл" or "ВЫКЛ",
            GetCVar("Sound_MusicVolume"))
        local d = 0
        if _G.WowVoiceDur then for _ in pairs(_G.WowVoiceDur) do d = d + 1 end end
        msg("формат: %s | индекс: %d названий | длительностей: %d",
            WowVoiceDB.ext, n, d)
        msg("глушение приветствия NPC: %s (канал Dialog)",
            WowVoiceDB.ducknpc and "вкл" or "выкл")
        if WV.license and WV.license.key then
            local k = WV.license.key
            msg("лицензия: активна (ключ …%s, пак %s)",
                strsub(k, -6), tostring(WV.license.pack or "?"))
        else
            msg("бесплатный аудиопак: лицензия не требуется")
        end
        msg("пример пути: %s", WV:SoundPath(179, "a"))
        msg("UI.lua (кнопка): %s",
            WV.ButtonMode and "загружен" or "НЕ ЗАГРУЖЕН — нужен полный перезапуск игры")
        msg("обрыв реплики: только кнопкой (при закрытии окна не прерывается)")
        if WV.HeadDiagnostics then WV:HeadDiagnostics() end

    elseif cmd == "test" then
        local id = tonumber(rest)
        if id then
            local path, dur = WV:SoundPath(id, "a")
            msg("проверка: %s (%s)", path,
                dur and format("%.1f с", dur) or "длительность неизвестна")
            Playback:Play(path, dur)
        else
            msg("использование: /wv test <quest_id>")
        end

    elseif cmd == "boosty" then
        StaticPopup_Show("WOWVOICE_BOOSTY")

    else
        msg("команды: on | off | stop | boosty | diag | debug <on|off> | duck <on|off> | test <quest_id> | stoptest")
        msg("         volume <0..1> | tail <сек> | button <auto|always|off>")
        msg("         channel <auto|sound|music> | ext <mp3|ogg>")
        msg("         stopmode <silence|cvar|stopmusic>")
        msg("         options — настройки говорящей головы")
        msg("состояние: %s, канал %s (%s), формат %s, стоп %s, индекс %s",
            WowVoiceDB.enabled and "вкл" or "выкл",
            WowVoiceDB.channel, Playback:mode(), WowVoiceDB.ext,
            WowVoiceDB.stopmode,
            _G.WowVoiceIndex and "загружен" or "ОТСУТСТВУЕТ")
    end
end

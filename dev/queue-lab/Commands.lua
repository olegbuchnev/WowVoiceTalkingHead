-- Developer console: deployed only with QueueLab, never shipped in release ZIPs.
local WV, Playback = WowVoice, WowVoice.Playback
local function msg(fmt, ...)
    local text = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff" .. WV.displayName .. "|r: " .. text)
end

local originalCommand = SlashCmdList.WOWVOICETALKINGHEAD
SlashCmdList.WOWVOICETALKINGHEAD = function(input)
    local cmd, rest = strsplit(" ", strtrim(input or ""), 2)
    cmd = strlower(cmd or "")

    if cmd == "remindertest" then
        local value = strtrim(rest or "")
        local id = tonumber(value)
        if value == "off" then
            WV:TestQuestReminder(false)
        elseif value == "" or (id and id > 0 and id == math.floor(id)) then
            WV:TestQuestReminder(id)
        else
            msg("тест напоминания: /thead remindertest [ID квеста] | off")
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

    elseif cmd == "debug" then
        rest = strlower(strtrim(rest or ""))
        if rest == "on" then
            WowVoiceDB.debug = true
        elseif rest == "off" then
            WowVoiceDB.debug = false
        elseif rest == "" then
            WowVoiceDB.debug = not WowVoiceDB.debug
        else
            msg("использование: /thead debug on|off")
            return
        end
        msg("отладка %s", WowVoiceDB.debug and "включена" or "выключена")

    elseif cmd == "perf" then
        if WV.Work then WV.Work:Report() end

    elseif cmd == "source" then
        local source, reason = WowVoiceAudioSources.Status()
        msg("Дополнительная озвучка выбирается автоматически: %s", source and (source.id .. " " .. source.version) or reason)

    elseif cmd == "diag" then
        local source, reason = WowVoiceAudioSources.Status()
        msg("Дополнительная озвучка (автоматически): %s", source and (source.id .. " " .. source.version) or reason)
        msg("CatQuest: автозапуск квестов %s; книги и лор управляются CatQuest",
            WV:IsCatQuestAutoplaySuppressed() and "приостановлен" or "не изменён")
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
        msg("множитель громкости диалогов: %.2f | сдвиг остановки: %+.2f с",
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
        msg("имена файлов: <quest_id><секция>.%s", WowVoiceDB.ext)
        msg("пример пути: %s", WV:SoundPath(179, "a"))
        msg("UI.lua (журнал): %s",
            WV.RefreshJournalButtons and "загружен" or "НЕ ЗАГРУЖЕН — нужен полный перезапуск игры")
        msg("обрыв реплики: только кнопкой (при закрытии окна не прерывается)")
        if WV.HeadDiagnostics then WV:HeadDiagnostics() end
        if WV.Work then WV.Work:Report() end

    elseif cmd == "test" then
        local id = tonumber(rest)
        if id then
            local path, dur, _, sourceID, verified = WV:SoundPath(id, "a")
            msg("проверка: %s (%s)", path,
                dur and format("%.1f с", dur) or "длительность неизвестна")
            Playback:Play(path, dur, nil, sourceID, verified)
        else
            msg("использование: /thead test <quest_id>")
        end

    else return originalCommand(input) end
end

-- Legacy debug alias is local-only; users open the catalogue with /wvvoices.
SLASH_WOWVOICELOCALDEBUG2 = "/wvdebug"

-- The precise clock has its own epoch. A slow frame leaves GetTime() stale
-- while real time (and the audio engine) keeps advancing.
frameLag = 0
if restoreTestCase ~= 'legacy' then
    function GetTimePreciseSec() return 10000 + now + frameLag end
end
if restoreTestCase == 'music' or restoreTestCase == 'stale-music' then
    cvars.Sound_EnableSoundWhenGameIsInBG = '0'
    function PlayMusic(file)
        if not file:find('silence.ogg', 1, true) then
            plays[#plays + 1] = {file = file, channel = 'Music'}
        end
    end
elseif restoreTestCase == 'silent' or restoreTestCase == 'stale-silent' then
    C_AddOns.IsAddOnLoaded = function() return false end
elseif restoreTestCase == 'legacy' then
    local create = CreateFrame
    function CreateFrame(...)
        local frame = create(...)
        local register = frame.RegisterEvent
        function frame:RegisterEvent(name)
            if name == 'LOADING_SCREEN_DISABLED' then error('Unknown event') end
            return register(self, name)
        end
        return frame
    end
end

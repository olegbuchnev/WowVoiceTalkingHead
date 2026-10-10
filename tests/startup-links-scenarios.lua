local originalLoaded = C_AddOns.IsAddOnLoaded
local loaded, pending = {}, {}
C_AddOns.IsAddOnLoaded = function(name)
    return loaded[name] == true or pending[name] == true, loaded[name] == true
end
local sources = {
    {'WowVoiceSounds', 'WowVoice — https://boosty.to/wowvoice'},
    {'CatQuest_Voices', 'CatQuest — https://boosty.to/cathey'},
    {'Wayfarer', 'Wayfarer — https://discord.gg/sgTeeQCZvh'},
}
local prefix = WowVoiceLocale.isEnglish and 'Voices: ' or 'Озвучка: '
local function startup()
    local first = #messages + 1
    event('ADDON_LOADED')
    local lines = {}
    for i=first,#messages do
        if messages[i]:find(prefix,1,true) then lines[#lines+1] = messages[i] end
    end
    return lines
end
for mask=0,7 do
    loaded, pending = {}, {}
    local expected = {}
    for index,source in ipairs(sources) do
        if math.floor(mask / 2^(index-1)) % 2 == 1 then
            loaded[source[1]] = true
            expected[#expected+1] = source[2]
        end
    end
    local lines = startup()
    assert(#lines == (#expected > 0 and 1 or 0), 'one combined notice, none without loaded sources')
    if #expected > 0 then
        assert(lines[1] == '|cff66ccffTalkingHead Ru|r: ' .. prefix .. table.concat(expected, '; '))
        assert(not lines[1]:find('Cathey',1,true))
    end
end
-- Merely installed/loading addons and stale globals must not earn a link.
loaded, pending = {CatQuest=true,WowVoice=true}, {WowVoiceSounds=true,CatQuest_Voices=true,Wayfarer=true}
assert(#startup() == 0)
loaded, pending = {Wayfarer=true}, {}
assert(startup()[1]:find('Wayfarer — https://discord.gg/sgTeeQCZvh',1,true))
local before = #messages
event('PLAYER_LOGIN')
assert(#messages == before, 'login refresh must not repeat startup credits')
C_AddOns.IsAddOnLoaded = originalLoaded
print('PASS: ' .. GetLocale() .. ' startup credits, all eight loaded combinations, CatQuest label, complete-load checks and no duplicate login notice')

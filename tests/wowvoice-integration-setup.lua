-- Keep references to the upstream objects, even after our own named frames
-- and globals replace them. Disabling an addon does not unload these objects.
local create = CreateFrame
function CreateFrame(kind, name, ...)
    local frame = create(kind, name, ...)
    if name then _G[name] = frame end
    function frame:UnregisterAllEvents() self.events = {} end
    return frame
end
upstreamTest = {disableCalls=0, saves=0, stops=0, callbacks=0}
local test = upstreamTest
test.startupMessages = {
    '|cff66ccffWowVoice|r: загружен. Квестов в индексе: 3134. Команды: /wv',
    '|cff66ccffWowVoice|r: |cffffd100Понравился WowVoice? Угости разработчика пивом на Boosty|r — набери /wv boosty',
    'WowVoice: загружен. Квестов в индексе: 4205. Команды: /wv',
    'WowVoice: Понравился WowVoice? Угости разработчика пивом на Boosty — набери /wv boosty',
}
test.retainedMessages = {
    'OtherAddon: loaded',
    '|cff66ccffWowVoice TalkingHead|r: Voices: WowVoice — https://boosty.to/wowvoice; Cathey — https://boosty.to/cathey',
    '|cff66ccffWowVoice|r: ОЗВУЧКА НЕ УСТАНОВЛЕНА.',
    '[Player]: WowVoice: загружен. Квестов в индексе: 3134. Команды: /wv',
    'OtherAddon: Понравился WowVoice? Угости разработчика пивом на Boosty — набери /wv boosty',
}
for _, text in ipairs(test.retainedMessages) do DEFAULT_CHAT_FRAME:AddMessage(text) end
-- Seed history even without upstream to ensure those modes leave it alone.
for _, text in ipairs(test.startupMessages) do DEFAULT_CHAT_FRAME:AddMessage(text) end
if upstreamTestMode ~= 'no-chat-removal' then
    function DEFAULT_CHAT_FRAME:RemoveMessagesByPredicate(predicate)
        assert(not predicate(nil) and not predicate({}))
        for i = #messages, 1, -1 do
            if predicate(messages[i]) then table.remove(messages, i) end
        end
    end
end
test.addMessage = DEFAULT_CHAT_FRAME.AddMessage
local loaded = upstreamTestMode ~= 'absent' and upstreamTestMode ~= 'disabled'
local enabled = {WowVoice=upstreamTestMode ~= 'disabled', WowVoiceSounds=true, CatQuest=true, CatQuest_Voices=true}
function UnitName(unit)
    assert(unit == 'player' or unit == 'npc')
    if unit == 'player' and upstreamTestMode == 'early-login' and not test.playerReady then return nil end
    return 'TestPlayer'
end
C_AddOns.DoesAddOnExist = function(name)
    if name == 'WowVoice' then return upstreamTestMode ~= 'absent' end
    return enabled[name] ~= nil
end
C_AddOns.DisableAddOn = function(name, character)
    assert(name == 'WowVoice' and character == 'TestPlayer', 'only disable upstream for this character')
    enabled[name] = false
    test.disableCalls = test.disableCalls + 1
end
C_AddOns.SaveAddOns = function() test.saves = test.saves + 1 end
C_AddOns.IsAddOnLoaded = function(name)
    if name == 'WowVoice' then return loaded end
    return enabled[name] == true
end
if upstreamTestMode == 'legacy' then
    GetAddOnInfo = function(name) if enabled[name] ~= nil then return name end end
    DisableAddOn = C_AddOns.DisableAddOn
    C_AddOns.DoesAddOnExist, C_AddOns.DisableAddOn, C_AddOns.SaveAddOns = nil, nil, nil
end
if not loaded then return end
WowVoiceIndex, WowVoiceDur = {upstream=true}, {upstream=true}
WowVoiceDB = {enabled=true, stopmode=upstreamTestMode == 'cvar' and 'cvar' or 'silence'}
test.db = WowVoiceDB
test.stopmode = WowVoiceDB.stopmode
test.frame = CreateFrame('Frame', 'WowVoiceFrame')
for _, event in ipairs({'PLAYER_LOGIN', 'QUEST_DETAIL', 'QUEST_PROGRESS', 'QUEST_COMPLETE', 'PLAYER_LOGOUT'}) do
    test.frame:RegisterEvent(event)
end
test.ticker = CreateFrame('Frame', 'WowVoiceTicker')
test.button = CreateFrame('Button', 'WowVoiceStopButton')
local function callback() test.callbacks = test.callbacks + 1 end
test.frame:SetScript('OnEvent', callback)
test.ticker:SetScript('OnUpdate', callback)
test.button:SetScript('OnClick', callback)
SlashCmdList.WOWVOICE = callback
SLASH_WOWVOICE1, SLASH_WOWVOICE2 = '/wv', '/wowvoice'
WowVoice = {Silence=function()
    assert(WowVoiceDB == test.db, 'stop upstream before replacing its settings')
    assert(WowVoiceDB.stopmode ~= 'cvar', 'do not schedule a restore on the retired ticker')
    test.stops = test.stops + 1
end}
test.upstream = WowVoice

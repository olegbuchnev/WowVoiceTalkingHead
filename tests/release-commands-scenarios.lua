event('ADDON_LOADED')
local WV = WowVoice
local function forbidden() error('Release command reached a development action') end
WV.TestQuestReminder, WV.HeadDiagnostics, WV.Work.Report = forbidden, forbidden, forbidden
WV.Playback.Play, WV.Playback.Stop = forbidden, forbidden
for _, value in ipairs({'remindertest', 'remindertest 179', 'remindertest off',
    'test 179', 'stoptest', 'debug on', 'diag', 'perf', 'source', 'queuelab', 'queuetest'}) do
    messages = {}
    command(value)
    assert(not WowVoiceDB.debug and not frames.WowVoiceQuestReminderPreview)
    assert(has('/thead help'), 'Unknown development commands should use ordinary release help')
    for _, message in ipairs(messages) do
        for _, name in ipairs({'remindertest', 'stoptest', 'diag', 'perf', 'debug', 'source', 'queuelab', 'queuetest'}) do
            assert(not message:find(name, 1, true), 'Release help advertises a development command')
        end
    end
end
assert(SLASH_WOWVOICELOCALDEBUG1 == '/wvvoices' and not SLASH_WOWVOICELOCALDEBUG2)
assert(not SLASH_WOWVOICEQUEUELAB1 and not SLASH_WOWVOICECATQUESTUPDATELAB1)
local opened = 0
WV.OpenOptions = function() opened = opened + 1 end
command(''); command('options')
assert(opened == 2 and #plays == 0)
print('PASS: release excludes development commands/aliases/help; public settings and catalogue remain available')

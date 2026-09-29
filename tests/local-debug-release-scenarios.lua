event('ADDON_LOADED')
WV = WowVoice
WV:OpenOptions()
assert(WowVoiceOptionsPanel.VoiceComparisonButton and SlashCmdList.WOWVOICELOCALDEBUG,
    'Release options must include the voice catalogue')
assert(not WowVoiceOptionsPanel.LocalDebugButton, 'Old header Debug button must be removed')
assert(not WowVoiceLocalDebugPanel, 'Catalogue must remain lazy until opened')
print('PASS: public voice catalogue included in release, lazy creation, no header Debug button')

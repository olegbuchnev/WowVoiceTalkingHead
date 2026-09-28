event('ADDON_LOADED')
local WV = WowVoice
assert(not WV:IsCatQuestAutoplaySuppressed(), 'CatQuest must remain optional')
command('off'); command('on')
assert(CatQuestDB == nil, 'do not create another addon database')

local history, quests = {}, {}
CatQuestDB = {autoDetail=true, autoProgress=false, autoComplete=true,
    readAfterAccept=true, autoBooks=true, lore=true, head=true, subtitles=true,
    autoGreeting=true, autoGossip=false, history=history, quests=quests}
event('PLAYER_LOGIN')
assert(WV:IsCatQuestAutoplaySuppressed())
assert(not CatQuestDB.autoDetail and not CatQuestDB.autoProgress and not CatQuestDB.autoComplete)
assert(not (CatQuestDB.readAfterAccept and CatQuestDB.autoDetail), 'acceptance cannot enqueue a second reading')
assert(CatQuestDB.autoBooks and CatQuestDB.lore and CatQuestDB.head and CatQuestDB.subtitles)
assert(CatQuestDB.autoGreeting and not CatQuestDB.autoGossip)
assert(CatQuestDB.history == history and CatQuestDB.quests == quests)
event('PLAYER_LOGIN') -- repeated synchronization must not replace the snapshot
command('diag')
assert(has('приостановлен'))
command('off')
assert(CatQuestDB.autoDetail and not CatQuestDB.autoProgress and CatQuestDB.autoComplete)
assert(not WV:IsCatQuestAutoplaySuppressed())
command('on')
assert(not CatQuestDB.autoDetail and not CatQuestDB.autoComplete)
event('PLAYER_LOGOUT')
assert(CatQuestDB.autoDetail and not CatQuestDB.autoProgress and CatQuestDB.autoComplete,
    'save original settings so CatQuest works when WowVoice is disabled next login')

-- Late load: defer until CatQuest has populated defaults, even when our event
-- listener runs first. No file modifications, globals replaced or libraries.
CatQuestDB = {}
local deferred
C_Timer = {After=function(delay, callback) assert(delay == 0); deferred=callback end}
local frame = frames.WowVoiceFrame
frame.scripts.OnEvent(frame, 'ADDON_LOADED', 'CatQuest')
assert(deferred and not WV:IsCatQuestAutoplaySuppressed())
CatQuestDB.autoDetail, CatQuestDB.autoProgress, CatQuestDB.autoComplete = true, true, false
CatQuestDB.autoBooks, CatQuestDB.lore = false, false
deferred()
assert(not CatQuestDB.autoDetail and not CatQuestDB.autoProgress and not CatQuestDB.autoComplete)
assert(not CatQuestDB.autoBooks and not CatQuestDB.lore, 'preserve books/lore opt-outs')
CatQuestDB.autoComplete = true -- explicit change through CatQuest's settings
command('off')
assert(CatQuestDB.autoDetail and CatQuestDB.autoProgress and CatQuestDB.autoComplete)

-- Replacing a database must restore the old reference and capture the new one.
command('on')
local old = CatQuestDB
CatQuestDB = {autoDetail=false, autoProgress=false, autoComplete=true}
WV:UpdateCatQuestIntegration()
assert(old.autoDetail and old.autoProgress and old.autoComplete)
event('PLAYER_LOGOUT')
assert(not CatQuestDB.autoDetail and not CatQuestDB.autoProgress and CatQuestDB.autoComplete)
print('PASS: optional CatQuest autoplay integration, books/lore, late load, toggles and saved preferences')

-- Identify read buttons by the exact CatQuest click handler, never their label.
function CatQuest_Toggle() end
function CatQuest_ReadQuestLog() end
local function surface()
    local parent = CreateFrame('Frame', nil, UIParent)
    parent.children = {}
    function parent:GetChildren() return table.unpack(self.children) end
    return parent
end
local function readButton(parent, handler, shown)
    local button = CreateFrame('Button', nil, parent)
    button:SetScript('OnClick', handler)
    function button:GetScript(script) return self.scripts[script] end
    button:SetText('Читать')
    if shown == false then button:Hide() end
    parent.children[#parent.children+1] = button
    return button
end
QuestFrame, ItemTextFrame, GossipFrame = surface(), surface(), surface()
QuestMapFrame = {DetailsFrame=surface()}
QuestLogDetailFrame, QuestLogFrame = nil, surface() -- nil gap must not skip legacy UI
local quest = readButton(QuestFrame, CatQuest_Toggle)
local book = readButton(ItemTextFrame, CatQuest_Toggle)
local gossip = readButton(GossipFrame, CatQuest_Toggle)
local other = readButton(QuestFrame, function() end)
local journal = readButton(QuestMapFrame.DetailsFrame, CatQuest_ReadQuestLog)
QuestMapFrame.DetailsFrame.catQuestButton = journal
local hidden = readButton(QuestLogFrame, CatQuest_ReadQuestLog, false)
QuestLogFrame.catQuestButton = hidden
command('on')
assert(not quest.visible and not journal.visible and not hidden.visible)
assert(book.visible and gossip.visible and other.visible, 'books/gossip/unrelated read buttons stay intact')
assert(quest.scripts.OnClick == CatQuest_Toggle and journal.scripts.OnClick == CatQuest_ReadQuestLog)
quest:Show(); journal:Show()
assert(not quest.visible and not journal.visible, 'a native Show must not defeat suppression')
WV:UpdateCatQuestIntegration() -- must retain the original visibility snapshot
command('off')
assert(quest.visible and journal.visible and not hidden.visible, 'restore exactly the prior shown state')
journal:Hide(); journal:Show()
assert(journal.visible, 'installed visibility hooks must be inactive after /wv off')
command('on')
event('PLAYER_LOGOUT')
assert(quest.visible and journal.visible and not hidden.visible)

-- CatQuest can create buttons after our login/addon listener has run.
QuestFrame, QuestMapFrame, QuestLogFrame = surface(), nil, nil
command('on')
event('PLAYER_LOGIN')
local lateQuest = readButton(QuestFrame, CatQuest_Toggle)
assert(lateQuest.visible)
deferred()
assert(not lateQuest.visible, 'deferred login refresh finds anonymous quest buttons')
frame.scripts.OnEvent(frame, 'ADDON_LOADED', 'Blizzard_QuestLog')
QuestMapFrame = {DetailsFrame=surface()}
local lateJournal = readButton(QuestMapFrame.DetailsFrame, CatQuest_ReadQuestLog)
QuestMapFrame.DetailsFrame.catQuestButton = lateJournal
deferred()
assert(not lateJournal.visible, 'deferred journal load refresh finds its button')
command('off')
assert(lateQuest.visible and lateJournal.visible)

-- Missing optional APIs/frames must be harmless with CatQuest absent.
CatQuestDB = nil
WV:UpdateCatQuestIntegration()
assert(book.visible and gossip.visible and other.visible)
print('PASS: CatQuest quest/read buttons, exact identity, book exclusion, prior visibility, late journal/login and restoration')

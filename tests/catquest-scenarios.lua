event('ADDON_LOADED')
local WV = WowVoice
assert(not WV:IsCatQuestAutoplaySuppressed(), 'CatQuest must remain optional')
command('off'); command('on')
assert(CatQuestDB == nil, 'do not create another addon database')

local history, quests = {}, {}
CatQuestDB = {autoDetail=true, autoProgress=false, autoComplete=true,
    readAfterAccept=true, autoBooks=true, lore=true, head=true, subtitles=true,
    loreAuto=true, loreMark='toast', codexToasts=true, storyCard=true, world=true,
    autoGreeting=true, autoGossip=false, history=history, quests=quests}
event('PLAYER_LOGIN')
assert(WV:IsCatQuestAutoplaySuppressed())
assert(not CatQuestDB.autoDetail and not CatQuestDB.autoProgress and not CatQuestDB.autoComplete)
assert(not (CatQuestDB.readAfterAccept and CatQuestDB.autoDetail), 'acceptance cannot enqueue a second reading')
assert(not CatQuestDB.autoBooks and CatQuestDB.lore and CatQuestDB.head and CatQuestDB.subtitles)
assert(not CatQuestDB.autoGreeting and not CatQuestDB.autoGossip)
assert(not CatQuestDB.loreAuto and CatQuestDB.loreMark == 'hidden' and not CatQuestDB.codexToasts and not CatQuestDB.storyCard)
assert(not CatQuestDB.world, 'CatQuest 0.7.0 world speech must not autoplay by default')
assert(CatQuestDB.history == history and CatQuestDB.quests == quests)
event('PLAYER_LOGIN') -- repeated synchronization must not replace the snapshot
command('diag')
assert(has('приостановлен'))
command('off')
assert(CatQuestDB.autoDetail and not CatQuestDB.autoProgress and CatQuestDB.autoComplete)
assert(CatQuestDB.autoBooks and CatQuestDB.autoGreeting and CatQuestDB.loreAuto and CatQuestDB.loreMark == 'toast')
assert(CatQuestDB.codexToasts and CatQuestDB.storyCard)
assert(CatQuestDB.world, 'restore world speech when TalkingHead Ru is disabled')
assert(not WV:IsCatQuestAutoplaySuppressed())
command('on')
assert(not CatQuestDB.autoDetail and not CatQuestDB.autoComplete)
CatQuestDB.world = true
WV:UpdateCatQuestIntegration()
assert(CatQuestDB.world and WV:IsLibraryPreferenceCustomized('CATQUEST_', 'world'),
    'explicitly enabling world speech remains under user control')
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
local otherGossip = readButton(GossipFrame, function() end)
local other = readButton(QuestFrame, function() end)
local journal = readButton(QuestMapFrame.DetailsFrame, CatQuest_ReadQuestLog)
QuestMapFrame.DetailsFrame.catQuestButton = journal
local hidden = readButton(QuestLogFrame, CatQuest_ReadQuestLog, false)
QuestLogFrame.catQuestButton = hidden
DUIQuestFrame, DUIBookFrame = surface(), surface()
ImmersionFrame = {TalkBox=surface()}
local dialogue = readButton(DUIQuestFrame, CatQuest_Toggle)
local immersion = readButton(ImmersionFrame.TalkBox, CatQuest_Toggle)
local dialogueBook = readButton(DUIBookFrame, CatQuest_Toggle)
local dialogueOther = readButton(DUIQuestFrame, function() end)
command('on')
assert(not quest.visible and not gossip.visible and not journal.visible and not hidden.visible)
assert(not dialogue.visible and not immersion.visible, 'CatQuest compatibility buttons stay hidden on replacement quest panels')
assert(dialogueBook.visible and dialogueOther.visible, 'DialogueUI books and native controls remain intact')
assert(book.visible and other.visible and otherGossip.visible, 'books and unrelated read buttons stay intact')
assert(quest.scripts.OnClick == CatQuest_Toggle and journal.scripts.OnClick == CatQuest_ReadQuestLog)
quest:Show(); journal:Show(); gossip:Show()
dialogue:Show(); immersion:Show()
assert(not dialogue.visible and not immersion.visible, 'compatibility button updates cannot defeat suppression')
assert(not quest.visible and not gossip.visible and not journal.visible, 'a native Show must not defeat suppression')
WV:UpdateCatQuestIntegration() -- must retain the original visibility snapshot
command('off')
assert(quest.visible and gossip.visible and journal.visible and not hidden.visible, 'restore exactly the prior shown state')
assert(dialogue.visible and immersion.visible, 'restore compatibility buttons when TalkingHead Ru is disabled')
journal:Hide(); journal:Show()
assert(journal.visible, 'installed visibility hooks must be inactive after /thead off')
command('on')
event('PLAYER_LOGOUT')
assert(quest.visible and gossip.visible and journal.visible and not hidden.visible)
assert(dialogue.visible and immersion.visible, 'restore compatibility buttons at logout')

-- CatQuest can create buttons after our login/addon listener has run.
QuestFrame, GossipFrame, QuestMapFrame, QuestLogFrame = surface(), surface(), nil, nil
command('on')
event('PLAYER_LOGIN')
local lateQuest = readButton(QuestFrame, CatQuest_Toggle)
local lateGossip = readButton(GossipFrame, CatQuest_Toggle)
lateGossip:SetText('Read') -- Identification must not depend on translated labels.
assert(lateQuest.visible)
deferred()
assert(not lateQuest.visible and not lateGossip.visible, 'deferred login refresh finds anonymous quest and gossip buttons')
lateGossip:Show()
assert(not lateGossip.visible)
frame.scripts.OnEvent(frame, 'ADDON_LOADED', 'Blizzard_QuestLog')
QuestMapFrame = {DetailsFrame=surface()}
local lateJournal = readButton(QuestMapFrame.DetailsFrame, CatQuest_ReadQuestLog)
QuestMapFrame.DetailsFrame.catQuestButton = lateJournal
deferred()
assert(not lateJournal.visible, 'deferred journal load refresh finds its button')
command('off')
assert(lateQuest.visible and lateGossip.visible and lateJournal.visible)

-- CatQuest Compat.lua can create replacement-panel buttons after our login hook.
DUIQuestFrame, ImmersionFrame = surface(), {TalkBox=surface()}
command('on')
event('PLAYER_LOGIN')
local lateDialogue = readButton(DUIQuestFrame, CatQuest_Toggle)
local lateImmersion = readButton(ImmersionFrame.TalkBox, CatQuest_Toggle)
deferred()
assert(not lateDialogue.visible and not lateImmersion.visible, 'deferred login covers CatQuest Compat.lua creation order')
local onOpen = readButton(DUIQuestFrame, CatQuest_Toggle)
DUIQuestFrame:Hide(); DUIQuestFrame:Show()
assert(not onOpen.visible, 'opening DialogueUI discovers an additional CatQuest button')
command('off')
assert(lateDialogue.visible and lateImmersion.visible and onOpen.visible)
DUIQuestFrame, ImmersionFrame = nil, nil

-- Missing optional APIs/frames must be harmless with CatQuest absent.
CatQuestDB = nil
WV:UpdateCatQuestIntegration()
assert(book.visible and gossip.visible and other.visible)
print('PASS: CatQuest quest/gossip/read buttons, locale-independent identity, book exclusion, prior visibility, late journal/login and restoration')

-- Tracker icons have a private click handler and are created during layout.
CatQuestDB = {autoDetail=true, autoComplete=true}
local function trackerIcon(block, atlas, questID)
    local button = readButton(block, function() end)
    button.questId = questID
    button.texture = {GetAtlas=function() return atlas end}
    return button
end
local function trackerModule()
    local tracker = {active={}}
    function tracker:LayoutBlock(block)
        self.active[block] = true
        if not block.testCatIcon then block.testCatIcon = trackerIcon(block, 'voicechat-icon-speaker', block.id) end
        block.testCatIcon.questId = block.id
        block.testCatIcon:Show()
    end
    function tracker:OnFreeBlock(block)
        self.active[block] = nil
        block.testCatIcon:Hide()
    end
    function tracker:EnumerateActiveBlocks(callback)
        for block in pairs(self.active) do callback(block) end
    end
    return tracker
end
QuestObjectiveTracker = trackerModule()
local block = surface(); block.id=179
QuestObjectiveTracker:LayoutBlock(block)
local unrelated = trackerIcon(block, 'other-atlas', block.id)
local noQuest = trackerIcon(block, 'voicechat-icon-speaker', nil)
command('on')
assert(not block.testCatIcon.visible and unrelated.visible and noQuest.visible)
block.testCatIcon:Show()
assert(not block.testCatIcon.visible, 'native Show cannot restore the tracker icon')
local created = surface(); created.id=180
QuestObjectiveTracker:LayoutBlock(created)
assert(not created.testCatIcon.visible, 'hide newly created icons after layout')
QuestObjectiveTracker:OnFreeBlock(created)
command('off')
assert(block.testCatIcon.visible and not created.testCatIcon.visible, 'never restore a freed block')
command('on')
created.id=181
QuestObjectiveTracker:LayoutBlock(created)
assert(not created.testCatIcon.visible, 'reused pooled blocks remain suppressed')
command('off')
assert(created.testCatIcon.visible, 'restore the current quest after reusing a block')
command('on')
CampaignQuestObjectiveTracker = trackerModule()
local campaign = surface(); campaign.id=182
CampaignQuestObjectiveTracker:LayoutBlock(campaign)
frame.scripts.OnEvent(frame, 'ADDON_LOADED', 'Blizzard_ObjectiveTracker')
deferred()
assert(not campaign.testCatIcon.visible, 'late campaign tracker is covered')
-- Simulate an upstream layout hook installed after TalkingHead Ru's hook.
local after = surface(); after.id=183
hooksecurefunc(CampaignQuestObjectiveTracker, 'LayoutBlock', function(_, b)
    if b == after and not b.extraIcon then b.extraIcon=trackerIcon(b, 'voicechat-icon-speaker', b.id) end
end)
CampaignQuestObjectiveTracker:LayoutBlock(after)
deferred()
assert(not after.extraIcon.visible, 'deferred scan covers the reverse hook order')
event('PLAYER_LOGOUT')
assert(block.testCatIcon.visible and created.testCatIcon.visible and campaign.testCatIcon.visible and after.extraIcon.visible)
assert(book.visible and unrelated.visible and noQuest.visible)
print('PASS: CatQuest normal/campaign tracker icons, new and recycled blocks, late hooks, unrelated buttons and restoration')

-- CatQuest 1.0.7 uses the same private icons on Questie's pooled title rows.
-- Exercise both readiness/hook orders and an initially unavailable module pool.
for _, order in ipairs({'catquest-first', 'talkinghead-first'}) do
    command('off')
    local pending, ready, lines, icons = {}, {}, {}, {}
    C_Timer = {After=function(delay, callback) assert(delay == 0); pending[#pending+1] = callback end}
    local function flush()
        local callbacks = pending; pending = {}
        for _, callback in ipairs(callbacks) do callback() end
    end
    local function line(id, mode)
        local row = surface()
        row.mode, row.Quest, row.label = mode or 'quest', {Id=id}, {}
        lines[#lines+1] = row
        return row
    end
    local first, objective, zone = line(179), line(179, 'objective'), line(0, 'zone')
    local hiddenLine, recipe = line(180), line(181)
    hiddenLine:Hide(); recipe.Recipe = {}
    local tracker = {UpdateFormatting=function() end}
    local pool = {GetHighestIndex=function() return #lines end, GetLine=function(i) return lines[i] end}
    QuestieLoader = {_modules={}}
    Questie = {db={profile={trackerEnabled=true}}, API={RegisterOnReady=function(callback)
        ready[#ready+1] = callback
    end}}
    command('on')
    assert(#ready == 1, 'register once while optional Questie modules are not ready')
    WV:UpdateCatQuestIntegration()
    assert(#ready == 1)
    QuestieLoader._modules = {QuestieTracker=tracker, TrackerLinePool=pool}
    local function upstreamSync()
        for _, icon in pairs(icons) do icon:Hide() end
        if not Questie.db.profile.trackerEnabled then return end
        for _, row in ipairs(lines) do
            if row:IsShown() and row.mode == 'quest' and not row.Recipe then
                local icon = icons[row] or trackerIcon(row, 'voicechat-icon-speaker', row.Quest.Id)
                icons[row] = icon
                icon.questId = row.Quest.Id
                icon:Show()
            end
        end
    end
    local function upstreamReady()
        hooksecurefunc(tracker, 'UpdateFormatting', upstreamSync)
        upstreamSync()
    end
    if order == 'catquest-first' then upstreamReady(); ready[1]()
    else ready[1](); upstreamReady() end
    flush()
    assert(icons[first] and not icons[first].visible, 'hide existing CatQuest Questie speaker')
    assert(not icons[objective] and not icons[zone] and not icons[hiddenLine] and not icons[recipe])
    local ourPlay = readButton(first, function() end)
    local native = trackerIcon(first, 'other-atlas', first.Quest.Id)
    local wrongQuest = trackerIcon(first, 'voicechat-icon-speaker', 9999)
    local fresh = line(182)
    tracker:UpdateFormatting(); flush()
    assert(icons[fresh] and not icons[fresh].visible, 'new rows hidden regardless of hook order')
    local afterCombat = line(185)
    event('PLAYER_REGEN_ENABLED')
    upstreamSync() -- CatQuest's handler runs after ours without UpdateFormatting.
    flush()
    assert(icons[afterCombat] and not icons[afterCombat].visible, 'combat-end creation is suppressed')
    assert(ourPlay.visible and native.visible and wrongQuest.visible, 'preserve our play button and unrelated controls')
    icons[first]:Show()
    assert(not icons[first].visible, 'upstream Show cannot defeat suppression')
    fresh:Hide()
    tracker:UpdateFormatting(); flush()
    command('off')
    assert(icons[first].visible and not icons[fresh].visible, 'do not restore a freed/hidden Questie row')
    tracker:UpdateFormatting(); flush()
    assert(icons[first].visible, 'installed hooks stay passive while disabled')
    command('on')
    fresh:Show(); fresh.Quest.Id = 183
    tracker:UpdateFormatting(); flush()
    assert(not icons[fresh].visible and icons[fresh].questId == 183, 'recycled row receives the new quest')
    first.mode = 'objective'
    tracker:UpdateFormatting(); flush()
    command('off')
    assert(not icons[first].visible and icons[fresh].visible, 'do not restore an objective recycled from a quest title')
    command('on')
    Questie.db.profile.trackerEnabled = false
    tracker:UpdateFormatting(); flush()
    command('off')
    assert(not icons[fresh].visible, 'disabled Questie tracker cannot regain stale icons')
    Questie.db.profile.trackerEnabled = true
    tracker:UpdateFormatting(); flush()
    command('on')
    local late = line(184)
    tracker:UpdateFormatting()
    command('off'); flush()
    assert(icons[late].visible, 'pending suppression must not run after disabling TalkingHead Ru')
    command('on')
    event('PLAYER_LOGOUT')
    assert(icons[fresh].visible and icons[late].visible, 'restore live Questie speakers on logout')
    assert(ourPlay.visible and native.visible and wrongQuest.visible)
end
print('PASS: CatQuest Questie speakers, both readiness/hook orders, late/new/recycled rows, disabled tracker, unrelated controls and restoration')

Questie, QuestieLoader = nil, nil
QuestLogDetailFrame = surface()
local classicJournal = readButton(QuestLogDetailFrame, CatQuest_ReadQuestLog)
QuestLogDetailFrame.catQuestButton = classicJournal
command('on')
assert(not classicJournal.visible)
QuestLogDetailFrame:Hide(); QuestLogDetailFrame:Show(); classicJournal:Show()
assert(not classicJournal.visible, 'ordinary quest log reader stays hidden after reopening and upstream refresh')
command('off')
assert(classicJournal.visible, 'ordinary quest log reader is restored when disabled')
print('PASS: CatQuest ordinary quest log detail button, reopen, refresh and restoration')

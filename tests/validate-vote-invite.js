const fs = require('fs'), path = require('path'), assert = require('assert/strict');
const {lua,lauxlib,lualib,to_luastring,to_jsstring} = require('fengari');
const root = path.resolve(__dirname, '..');
const source = process.argv[2] || path.join(root,'src');
const toc=fs.readFileSync(path.join(source,'TalkingHeadRu.toc'),'utf8');
const releaseVersion=toc.match(/^## Version:\s*(\S+)/m)[1];
const invitePolicy=toc.match(/^## X-Vote-Invite:\s*(\S+)/m)?.[1];
assert.equal(invitePolicy,'disabled','This technical release must not automatically invite voters');
for(const name of fs.readdirSync(source).filter(name=>name.endsWith('.toc')))
  assert.equal(fs.readFileSync(path.join(source,name),'utf8').match(/^## X-Vote-Invite:\s*(\S+)/m)?.[1],invitePolicy);
const texture = fs.readFileSync(path.join(source,'Media/VoteAdventurers.tga'));
assert.equal(texture[2],2);
assert.equal(texture.readUInt16LE(12),512);
assert.equal(texture.readUInt16LE(14),512);
assert.equal(texture[16],32);
assert.equal(texture[17],40);
assert.equal(texture.length,18+512*512*4);
assert(fs.readFileSync(path.join(source,'Media/Fonts/frizqt___cyr.ttf'))
  .equals(fs.readFileSync(path.join(root,'web/voice-vote/public/fonts/frizqt___cyr.ttf'))));
for (const locale of ['ruRU','enUS','enGB']) {
  const state = lauxlib.luaL_newstate(); lualib.luaL_openlibs(state);
  function run(code) {
    const status = lauxlib.luaL_dostring(state,to_luastring(code));
    if (status !== lua.LUA_OK) throw Error(`${locale}: ${to_jsstring(lua.lua_tostring(state,-1))}`);
  }
  function file(name) {run(fs.readFileSync(name,'utf8'));}
  for (const name of ['mock.lua','journal-mock.lua','portrait-mock.lua','local-debug-mock.lua']) file(path.join(__dirname,name));
  run(`
    function GetLocale() return '${locale}' end
    nativeWordWrap=true
    installedVersion='1.3.2-forever'
    C_AddOns.GetAddOnMetadata=function(addon,key)
      if addon=='TalkingHeadRu' then
        if key=='Version' then return installedVersion end
        if key=='X-Vote-Invite' then return releaseInvitePolicy end
      end
    end
    callbacks={}
    C_Timer={After=function(_,callback) callbacks[#callbacks+1]=callback end}
    function flush() local old=callbacks; callbacks={}; for _,cb in ipairs(old) do cb() end end
    function InCombatLockdown() return combat end
    local originalCreate=CreateFrame
    function CreateFrame(kind,...)
      local f=originalCreate(kind,...)
      function f:UnregisterEvent(name) self.events[name]=nil end
      if kind=='EditBox' then
        function f:SetFont(font,size) self.font,self.fontSize=font,size end
        function f:SetTextColor(...) self.textColor={...} end
        function f:HighlightText() self.selected=true end
      end
      return f
    end
  `);
  for (const name of fs.readFileSync(path.join(source,'TalkingHeadRu.toc'),'utf8').split(/\r?\n/).filter(x=>x.endsWith('.lua'))) file(path.join(source,name));
  run(`
    event('ADDON_LOADED')
    assert(WowVoice:GetVoiceSelectionMode()=='ranking', 'fresh install uses community ranking')
    function login()
      local f=frames.TalkingHeadRuVoteInviteEvents
      f.scripts.OnEvent(f,'PLAYER_ENTERING_WORLD')
    end
    login(); login()
    assert(#callbacks==1, 'only schedule on first entry')
    assert(not TalkingHeadRuDB.voteInviteSeenVersions, 'do not mark a pending popup as seen')
    flush()
    popup=frames.TalkingHeadRuVoteInvite
    assert(popup:IsShown() and TalkingHeadRuDB.voteInviteSeenVersions[installedVersion])
    assert(not EllesmereUI, 'standalone styling requires no upstream addon')
    assert(popup.Title:GetText()=='Голосуйте за лучшую озвучку', 'invitation stays Russian on every client')
    assert(popup.Description:GetText():gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')==
      'Сравните голоса из WowVoice, CatQuest и Wayfarer. Ваш выбор поможет подобрать озвучку для заданий и персонажей WoW Forever.')
    assert(popup.CopyHint:GetText()=='Нажмите на ссылку, затем Ctrl+C')
    assert(popup.VoiceSettingsHint:GetText():gsub('|T.-|t ','')==
      'В настройках «Выбор озвучки» можно прослушать примеры и задать свой порядок библиотек — общий или отдельно для каждой расы и пола.')
    assert(popup.Options.Text:GetText()=='Опции' and popup.Close.Text:GetText()=='Закрыть')
    assert(popup.Title:GetStringWidth()<=popup.Title:GetWidth(), 'heading fits')
    assert(popup.Description:GetStringHeight()<=popup.Description.height, 'body fits')
    assert(popup.VoiceSettingsHint:GetStringHeight()<=popup.VoiceSettingsHint.height, 'voice settings hint fits')
    assert(popup.Link:GetText()=='https://talkingheadru.tw1.ru/' and not popup.Link.focus)
    popup.Link.scripts.OnMouseUp(popup.Link)
    assert(popup.Link.focus and popup.Link.selected)
    popup.Link:SetText('changed')
    popup.Link.scripts.OnTextChanged(popup.Link)
    assert(popup.Link:GetText()=='https://talkingheadru.tw1.ru/')
    popup.Close.scripts.OnClick()
    assert(not popup:IsShown() and not popup.Link.focus)
    login(); flush()
    assert(not popup:IsShown())
    command('vote')
    assert(popup:IsShown(), 'manual command reopens a seen invitation')
    popup.Link.scripts.OnEscapePressed()
    assert(not popup:IsShown())
    WowVoice:OpenOptions()
    local options=frames.WowVoiceOptionsPanel
    options:SetSize(720,800)
    WowVoice:OpenVoiceRanking()
    options.Scroll:SetVerticalScroll(300)
    command('vote')
    popup.Link.scripts.OnMouseUp(popup.Link)
    popup.Options.scripts.OnClick()
    assert(not popup:IsShown() and not popup.Link.focus, 'options button dismisses invitation and copy focus')
    assert(options:IsShown() and options.Scroll:IsShown(), 'options button returns to main options')
    assert(not frames.TalkingHeadRuRankingView:IsShown(), 'options button closes nested ranking view')
    assert(options.Scroll:GetVerticalScroll()==0, 'options button starts at voice selection')
    options:Hide()
  `);
  // New Lua module state models a reload/another character with account-wide saves.
  file(path.join(source,'VoteInvite.lua'));
  run(`
    login(); flush()
    assert(not frames.TalkingHeadRuVoteInvite:IsShown(), 'same version stays dismissed on reload')
    installedVersion='1.3.3-forever'
    combat=true
  `);
  file(path.join(source,'VoteInvite.lua'));
  run(`
    login(); flush()
    assert(not TalkingHeadRuDB.voteInviteSeenVersions[installedVersion], 'combat does not consume the invitation')
    local events=frames.TalkingHeadRuVoteInviteEvents
    assert(events.events.PLAYER_REGEN_ENABLED)
    combat=false
    events.scripts.OnEvent(events,'PLAYER_REGEN_ENABLED')
    assert(frames.TalkingHeadRuVoteInvite:IsShown() and TalkingHeadRuDB.voteInviteSeenVersions[installedVersion])
    frames.TalkingHeadRuVoteInvite:Hide()
    installedVersion='1.3.2-forever'
    assert(not WowVoice:ShowVoteInvite(), 'rollback to an already seen version stays quiet')
    installedVersion='1.3.4-forever'
    TalkingHeadRuDB.enabled=false
    assert(not WowVoice:ShowVoteInvite() and not TalkingHeadRuDB.voteInviteSeenVersions[installedVersion])
    command('vote')
    assert(frames.TalkingHeadRuVoteInvite:IsShown(), 'manual command works while quest playback is disabled')
    frames.TalkingHeadRuVoteInvite:Hide()
    TalkingHeadRuDB.enabled=true
    installedVersion=nil
    assert(not WowVoice:ShowVoteInvite(), 'unknown metadata does not repeatedly nag')
  `);
  run(`
    installedVersion='${releaseVersion}'
    releaseInvitePolicy='${invitePolicy}'
    TalkingHeadRuDB={enabled=true}
    combat=true
  `);
  file(path.join(source,'VoteInvite.lua'));
  run(`
    login(); login(); flush()
    assert(#callbacks==0, 'disabled release must not schedule the popup')
    assert(not frames.TalkingHeadRuVoteInviteEvents.events.PLAYER_REGEN_ENABLED, 'disabled release must not defer until combat ends')
    combat=false
    assert(not WowVoice:ShowVoteInvite(), 'direct automatic calls respect the release policy')
    assert(not frames.TalkingHeadRuVoteInvite:IsShown())
    assert(not TalkingHeadRuDB.voteInviteSeenVersions, 'suppression does not fabricate a viewed invitation')
    command('vote')
    assert(frames.TalkingHeadRuVoteInvite:IsShown(), 'manual invitation remains available in a silent release')
    frames.TalkingHeadRuVoteInvite:Hide()
    TalkingHeadRuDB={enabled=true}
  `);
  file(path.join(source,'VoteInvite.lua'));
  run(`
    login(); flush()
    assert(not frames.TalkingHeadRuVoteInvite:IsShown(), 'fresh account or reload remains quiet')
    assert(not TalkingHeadRuDB.voteInviteSeenVersions)
  `);
  lua.lua_close(state);
}
console.log('PASS: Russian voting invitation on ruRU/enUS/enGB, locale layout, manual command, copy field, version history, reload and combat deferral');

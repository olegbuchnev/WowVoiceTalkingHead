const fs = require('fs'), path = require('path'), assert = require('assert/strict');
const {lua,lauxlib,lualib,to_luastring,to_jsstring} = require('fengari');
const root = path.resolve(__dirname, '..');
const source = process.argv[2] || path.join(root,'src');
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
  for (const name of ['mock.lua','journal-mock.lua','portrait-mock.lua']) file(path.join(__dirname,name));
  run(`
    function GetLocale() return '${locale}' end
    nativeWordWrap=true
    installedVersion='1.3.2-forever'
    C_AddOns.GetAddOnMetadata=function(addon,key) if addon=='TalkingHeadRu' and key=='Version' then return installedVersion end end
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
    assert(popup.Title:GetStringWidth()<=popup.Title:GetWidth(), 'heading fits')
    assert(popup.Description:GetStringHeight()<=popup.Description.height, 'body fits')
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
  lua.lua_close(state);
}
console.log('PASS: voting invitation, locale layout, manual command, copy field, version history, reload and combat deferral');

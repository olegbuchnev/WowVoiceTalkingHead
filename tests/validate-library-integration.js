const fs = require('fs'), path = require('path');
const {lua,lauxlib,lualib,to_luastring,to_jsstring} = require('fengari');
const source = process.argv[2] || path.join(__dirname,'../src');
const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
function run(code) {
  const status = lauxlib.luaL_dostring(L,to_luastring(code));
  if (status !== lua.LUA_OK) throw Error(to_jsstring(lua.lua_tostring(L,-1)));
}
run(`
  WowVoice = {}
  TalkingHeadRuDB = {enabled=true}
  db = {loreAuto=true, loreMark='toast', autoBooks=true}
  settings = {}
  for key in pairs(db) do
    local name = key
    settings['CATQUEST_'..key] = {SetValue=function(_,value) db[name]=value end}
  end
  Settings = {GetSetting=function(id) return settings[id] end}
  function hooksecurefunc(object,key,callback)
    local original = object[key]
    object[key] = function(...) original(...); callback(...) end
  end
  chatCalls=0
  originalChat=function() chatCalls=chatCalls+1 end
  DEFAULT_CHAT_FRAME={AddMessage=originalChat}
`);
const integration = fs.readFileSync(path.join(source,'LibraryIntegration.lua'),'utf8');
run(integration);
run(`
  assert(DEFAULT_CHAT_FRAME.AddMessage==originalChat, 'loading integration must preserve the native chat handler')
  function update(active)
    WowVoice:UpdateLibraryPreferences('CATQUEST_',db,
      {loreAuto=false,loreMark='hidden',autoBooks=false},active,nil,{loreAuto=true,loreMark=true})
  end
  update(true)
  assert(not db.loreAuto and db.loreMark=='hidden' and not db.autoBooks)
  update(true); update(false)
  assert(db.loreAuto and db.loreMark=='toast' and db.autoBooks, 'restore original defaults')
  update(true)
  settings.CATQUEST_loreAuto:SetValue(true)
  settings.CATQUEST_loreMark:SetValue('free')
  assert(db.loreAuto and db.loreMark=='free', 'explicit settings take effect immediately')
  update(true)
  assert(db.loreAuto and db.loreMark=='free', 'refresh respects user choices')
  settings.CATQUEST_autoBooks:SetValue(false)
  update(false)
  assert(db.loreAuto and db.loreMark=='free' and not db.autoBooks, 'restore only our changes')
  db.loreAuto=false
  update(true)
  assert(not db.loreAuto, 'changes while disabled also remain user-owned')
  update(false)
  DEFAULT_CHAT_FRAME:AddMessage('|cffffffffCatQuest:|r hello')
  DEFAULT_CHAT_FRAME:AddMessage('Player: CatQuest: quoted')
  assert(chatCalls==2)
  WowVoice:UpdateCatQuestPlayback(false)
  DEFAULT_CHAT_FRAME:AddMessage('CatQuest: hello')
  assert(chatCalls==3 and DEFAULT_CHAT_FRAME.AddMessage==originalChat)
  WowVoice:UpdateCatQuestPlayback(true)
  assert(DEFAULT_CHAT_FRAME.AddMessage==originalChat, 'takeover must preserve the native chat handler')
  -- An opaque payload stands in for restricted battleground chat data.
  local payload=setmetatable({}, {__tostring=function() error('opaque chat payload inspected') end})
  local replacement=function(self, text, ...) assert(text==payload); return ... end
  DEFAULT_CHAT_FRAME={AddMessage=replacement}
  WowVoice:UpdateCatQuestPlayback(true)
  assert(DEFAULT_CHAT_FRAME.AddMessage==replacement, 'replacement chat frame must remain untouched')
  assert(DEFAULT_CHAT_FRAME:AddMessage(payload, 42)==42)
  -- Simulate a reload with only saved databases surviving.
  WowVoice = {}
`);
run(integration);
run(`
  update(true)
  assert(not db.loreAuto and db.loreMark=='free', 'ownership survives reload')
  settings.CATQUEST_loreAuto:SetValue(true)
  update(true)
  assert(db.loreAuto, 'settings hooks remain usable after reinitialization')
  update(false)
  -- Direct edits and selecting the already-forced value must also survive.
  TalkingHeadRuDB.libraryPreferences = nil
  db.loreAuto=true; db.loreMark='toast'
  update(true)
  settings.CATQUEST_loreAuto:SetValue(false)
  db.loreMark='badge'
  update(true); update(false)
  assert(not db.loreAuto and db.loreMark=='badge')
  assert(WowVoice:IsLibraryPreferenceCustomized('CATQUEST_','loreAuto'))
  -- Replacing a loaded library restores the old database first.
  TalkingHeadRuDB.libraryPreferences=nil
  db={loreAuto=true,autoBooks=true}
  update(true)
  local old=db
  db={loreAuto=true,autoBooks=true}
  update(true)
  assert(old.loreAuto and old.autoBooks and not db.loreAuto)
  update(false)
  assert(db.loreAuto and db.autoBooks)
`);
lua.lua_close(L);
console.log('PASS: reversible library preferences, explicit lore choices, reloads, replacement and native chat preservation');

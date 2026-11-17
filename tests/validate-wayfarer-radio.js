const fs=require('fs'),path=require('path');
const {lua,lauxlib,lualib,to_luastring,to_jsstring}=require('fengari');
const source=process.argv[2]||path.join(__dirname,'../src');
for(const mode of ['early','late','disabled','running-auto','running-manual']) {
 const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 function run(code){if(lauxlib.luaL_dostring(L,to_luastring(code))!==lua.LUA_OK)throw Error(mode+': '+to_jsstring(lua.lua_tostring(L,-1)));}
 try{
 run(`
 WowVoice={}; TalkingHeadRuDB={enabled=${mode!=='disabled'}}; WayfarerRU={}
 Wayfarer_RadioDB={mode='auto',taxi=true,heard={old=true},marks={chapter=2}}
 starts,stops=0,0; panelShown=false; queued={quest=true}
 local original
 original=function(self,kind,opts,extra)
   starts=starts+1;self.session={auto=opts and opts.auto,taxi=opts and opts.taxi}
   queued.radio=true;panelShown=true;return kind,opts,extra
 end
 function makeRadio()
   return {Start=original,Stop=function(self,quiet)
     assert(quiet==true);stops=stops+1;self.session=nil;queued.radio=nil;panelShown=false
   end}
 end
 ${mode==='late'?'':'WayfarerRU.Radio=makeRadio()'}
 ${mode==='running-auto'?"WayfarerRU.Radio:Start('book',{auto=true,taxi=true})":''}
 ${mode==='running-manual'?"WayfarerRU.Radio:Start('radio')":''}
 originalStart=original
 `);
 for(const f of ['LibraryIntegration.lua','WayfarerIntegration.lua'])run(fs.readFileSync(path.join(source,f),'utf8'));
 if(mode==='late')run(`WayfarerRU.Radio=makeRadio();WowVoice:UpdateWayfarerIntegration()`);
 run(`
 local radio=WayfarerRU.Radio
 assert(stops==${mode==='running-auto'?1:0})
 assert(queued.quest and Wayfarer_RadioDB.mode=='auto' and Wayfarer_RadioDB.taxi)
 assert(Wayfarer_RadioDB.heard.old and Wayfarer_RadioDB.marks.chapter==2)
 ${mode==='running-manual'?"assert(panelShown and radio.session and not radio.session.auto)":''}
 local wrapped=radio.Start
 for i=1,3 do WowVoice:UpdateWayfarerIntegration() end
 assert(radio.Start==wrapped, 'refresh must not stack wrappers')
 local count=starts
 for _,opts in ipairs({{auto=true},{auto=true,taxi=true}}) do
   local result=radio:Start('book',opts)
   ${mode==='disabled'?"assert(result=='book')":"assert(result==false)"}
 end
 assert(starts==count+${mode==='disabled'?2:0})
 local options={auto=false,focus='place'}
 local kind,opts,extra=radio:Start('radio',options,42)
 assert(kind=='radio' and opts==options and extra==42 and panelShown)
 WowVoice:UpdateWayfarerIntegration()
 assert(panelShown, 'manual session stays available')
 TalkingHeadRuDB.enabled=false;WowVoice:UpdateWayfarerIntegration()
 assert(radio.Start==originalStart)
 radio:Start('book',{auto=true,taxi=true});assert(radio.session.auto)
 TalkingHeadRuDB.enabled=true;WowVoice:UpdateWayfarerIntegration()
 assert(not radio.session and not panelShown and queued.quest)
 local old=radio
 WayfarerRU.Radio=makeRadio();WowVoice:UpdateWayfarerIntegration()
 assert(old.Start==originalStart and WayfarerRU.Radio.Start~=originalStart)
 local replacement=function()return 'third-party' end
 WayfarerRU.Radio.Start=replacement
 WowVoice:UpdateWayfarerIntegration(true)
 assert(WayfarerRU.Radio.Start==replacement,'release must preserve third-party replacements')
 WowVoice:UpdateWayfarerIntegration()
 assert(WayfarerRU.Radio:Start('book',{auto=true,taxi=true})==false)
 WowVoice:UpdateWayfarerIntegration(true)
 assert(WayfarerRU.Radio.Start==replacement,'logout restores only our wrapper')
 `);
 }finally{lua.lua_close(L);}
}
console.log('PASS: Radio taxi/running autostart suppressed before UI/audio; manual playback, saved history, late loading, active sessions and restoration preserved');

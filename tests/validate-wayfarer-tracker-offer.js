const fs=require('fs'),path=require('path');
const {lua,lauxlib,lualib,to_luastring,to_jsstring}=require('fengari');
const source=process.argv[2]||path.join(__dirname,'../src');
for(const offer of [{component:'QuestZones',method:'Offer',db:'db',flag:'qzAsked'},
 {component:'Zones',method:'OfferKnown',db:'charDB',flag:'knownAsked'}])
for(const mode of ['early','late','disabled','answered','no-saved-settings']) {
 const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 function run(code,fixture=true){
  if(fixture) code=code.replaceAll('QuestZones',offer.component).replaceAll('Offer',offer.method).replaceAll('qzAsked',offer.flag).replaceAll('WayfarerRU.db','WayfarerRU.'+offer.db).replaceAll('WayfarerRU={db=','WayfarerRU={'+offer.db+'=');
  if(lauxlib.luaL_dostring(L,to_luastring(code))!==lua.LUA_OK)throw Error(offer.component+'/'+mode+': '+to_jsstring(lua.lua_tostring(L,-1)));
 }
 try {
 run(`WowVoice={};TalkingHeadRuDB=${mode==='no-saved-settings'?'nil':`{enabled=${mode!=='disabled'}}`}
 WayfarerRU={db={qzAsked=${mode==='answered'},qzEnabled=false}};shown=0
 function originalOffer(self,extra)
   if WayfarerRU.db.qzAsked then return end
   WayfarerRU.db.qzAsked=true;shown=shown+1;return extra
 end
 function makeTracker() return {Offer=originalOffer} end
 ${mode==='late'?'':'WayfarerRU.QuestZones=makeTracker()'}
 `);
 for(const f of ['LibraryIntegration.lua','WayfarerIntegration.lua'])run(fs.readFileSync(path.join(source,f),'utf8'),false);
 if(mode==='late')run('WayfarerRU.QuestZones=makeTracker();WowVoice:UpdateWayfarerIntegration()');
 run(`WayfarerRU.QuestZones:Offer()
 assert(shown==${mode==='disabled'?1:0})
 assert(WayfarerRU.db.qzAsked==${mode==='answered'||mode==='disabled'})
 assert(WayfarerRU.db.qzEnabled==false)
 TalkingHeadRuDB={enabled=true};WowVoice:UpdateWayfarerIntegration()
 local wrapped=WayfarerRU.QuestZones.Offer
 WowVoice:UpdateWayfarerIntegration();assert(WayfarerRU.QuestZones.Offer==wrapped)
 local old=WayfarerRU.QuestZones
 WayfarerRU.QuestZones=makeTracker();WowVoice:UpdateWayfarerIntegration()
 assert(old.Offer==originalOffer)
 TalkingHeadRuDB.enabled=false;WowVoice:UpdateWayfarerIntegration()
 assert(WayfarerRU.QuestZones.Offer==originalOffer)
 ${mode==='answered'||mode==='disabled'?'':"assert(WayfarerRU.QuestZones:Offer(42)==42 and shown==1)"}
 TalkingHeadRuDB.enabled=true;WowVoice:UpdateWayfarerIntegration()
 local replacement=function()return 'other' end
 WayfarerRU.QuestZones.Offer=replacement;WowVoice:UpdateWayfarerIntegration(true)
 assert(WayfarerRU.QuestZones.Offer==replacement)
 WowVoice:UpdateWayfarerIntegration();WowVoice:UpdateWayfarerIntegration(true)
 assert(WayfarerRU.QuestZones.Offer==replacement)
 `);
 } finally {lua.lua_close(L);}
}
console.log('PASS: tracker and known-places offers suppressed before saved first-run flag; early/late loading, disabled addon, prior answers, namespace replacement and restoration');

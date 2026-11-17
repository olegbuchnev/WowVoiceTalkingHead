const fs=require('fs'),path=require('path');
const {lua,lauxlib,lualib,to_luastring,to_jsstring}=require('fengari');
const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
function run(s){if(lauxlib.luaL_dostring(L,to_luastring(s))!==lua.LUA_OK)throw Error(to_jsstring(lua.lua_tostring(L,-1)));}
run(`WowVoice={};TalkingHeadRuDB={enabled=true};CatQuestDB={world=true,newsSeen={old=true}}
starts,stops,worldStops,ducks=0,0,0,0
function play() starts=starts+1;return 'played' end
PlaySoundFile=play
CatQuestCore={state={playing=true},queue={1},Speak=play,Enqueue=play,BridgeSpeak=play,SelfTest=play,
 ShowNews=play,NewsCheck=play,ShowWelcome=play,PlayNext=play,Resume=play,PlayQueued=play,
 WorldQueue={Take=play},ClearQueue=function() stops=stops+1;CatQuestCore.state.playing=false;CatQuestCore.queue={} end,
 WorldSlash=function(cmd) worldStops=worldStops+1;CatQuestDB.world=false;return true end,
 Unduck=function()ducks=ducks+1 end}
CatQuest_Toggle=play;SlashCmdList={CATQUEST=function(cmd) return play() end}
CatQuestNewsFrame={Hide=function()end};savedSpeak=CatQuestCore.Speak
`);
run(fs.readFileSync(path.join(process.argv[2]||'src','LibraryIntegration.lua'),'utf8'));
run(`local settings={};WowVoice:UpdateLibraryPreferences('test',settings,{dungeonMaster=false},true,nil,nil,{dungeonMaster=true})
assert(settings.dungeonMaster==false)
WowVoice:UpdateLibraryPreferences('test',settings,{dungeonMaster=false},false)
assert(settings.dungeonMaster==nil,'restore implicit enabled default')
assert(stops==1 and worldStops==2 and ducks==1 and CatQuestDB.world==true)
for _,key in ipairs({'Speak','Enqueue','BridgeSpeak','SelfTest','ShowNews','NewsCheck','ShowWelcome','PlayNext','Resume','PlayQueued'}) do assert(CatQuestCore[key]()==false,key) end
assert(not CatQuestCore.WorldQueue.Take());assert(not CatQuest_Toggle())
assert(CatQuestCore.WorldSlash('world test'));assert(not CatQuestCore.WorldSlash('options'))
for _,cmd in ipairs({'test','tts','bridge','pack 5','  TTS '}) do assert(SlashCmdList.CATQUEST(cmd)==false) end
assert(starts==0 and CatQuestDB.newsSeen.old)
assert(PlaySoundFile('Interface\\\\AddOns\\\\CatQuest_Voices\\\\Sounds\\\\q\\\\5.ogg')=='played')
assert(SlashCmdList.CATQUEST('options')=='played')
WowVoice:UpdateCatQuestPlayback(true);assert(stops==1 and worldStops==2)
local replacement=play;CatQuestCore.Speak=replacement;WowVoice:UpdateCatQuestPlayback(true);assert(not CatQuestCore.Speak())
WowVoice:UpdateCatQuestPlayback(false);assert(CatQuestCore.Speak==replacement and CatQuest_Toggle==play)
assert(CatQuestCore.Speak()=='played' and SlashCmdList.CATQUEST('tts')=='played')
WowVoice:UpdateCatQuestPlayback(true)
local third=function()return 'third' end;CatQuestCore.Speak=third
WowVoice:UpdateCatQuestPlayback(false);assert(CatQuestCore.Speak==third)
CatQuestCore=nil;WowVoice:UpdateCatQuestPlayback(true)
CatQuestCore={Speak=play};WowVoice:UpdateCatQuestPlayback(true);assert(not CatQuestCore.Speak())
WowVoice:UpdateCatQuestPlayback(false);assert(CatQuestCore.Speak==play)
`);
console.log('PASS: CatQuest playback/news guards, takeover, direct source audio, commands, late loading, replacement and restoration');

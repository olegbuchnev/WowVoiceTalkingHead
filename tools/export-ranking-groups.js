// Export only known NPC group keys; no audio or personal installation paths.
const fs=require('node:fs');
const path=require('node:path');
const {dataTable}=require('./import-forever-audio.js');
const root=path.resolve(__dirname,'..');
const speakers=dataTable(path.join(root,'src/Speakers.lua'));
const groups=new Map();
for(const npc of Object.values(speakers.npcs)) {
  if(npc.race && ['male','female'].includes(npc.sex)) groups.set(`${npc.race}/${npc.sex}`,{race:npc.race,sex:npc.sex});
}
const result=[...groups.entries()].sort(([a],[b])=>a<b?-1:a>b?1:0).map(([,group])=>group);
fs.writeFileSync(path.join(root,'server/voice-vote/src/main/resources/ranking-groups.json'),JSON.stringify(result,null,2)+'\n');
console.log(`Ranking group registry: ${result.length}`);
const quests=Object.entries(speakers.givers).flatMap(([questID,giver])=>{
  const npc=speakers.npcs[giver.npcID];
  if(!npc?.race || !['male','female'].includes(npc.sex)) return [];
  return [{questID:Number(questID),npc:{id:giver.npcID,displayID:0,modelFileID:0,race:npc.race,sex:npc.sex}}];
}).sort((a,b)=>a.questID-b.questID);
fs.writeFileSync(path.join(root,'server/voice-vote/src/main/resources/ranking-speakers.json'),JSON.stringify(quests)+'\n');

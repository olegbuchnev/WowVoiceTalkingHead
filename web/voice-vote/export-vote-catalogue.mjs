import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {buildCatalogue, modelAsset, repo} from './server.mjs';
import historyTools from '../../tools/audio-recording-history.js';

export function revisionHashes(history, {pack,file,sha256}) {
  const revisions=historyTools.supportedRevisions(history,pack,file).map(r=>r.sha256);
  if(!revisions.includes(sha256)) throw Error(`Recording is outside the audited history window: ${pack}/${file}`);
  return revisions;
}

export async function exportVoteCatalogue(destination = path.join(repo,'data/voice-vote/catalogue.json'), {questIDs, onProgress=()=>{}} = {}) {
  // Installed files are verified here, on the preparation machine only.
  const {catalogue}=buildCatalogue(undefined,{questIDs});
  const history=historyTools.validate(JSON.parse(await fs.readFile(path.join(repo,historyTools.historyPath),'utf8')));
  if (!catalogue.quests.length) throw Error('No verified comparisons available');
  const models=new Map(), modelErrors=[];
  const displays=[...new Set(catalogue.quests.map(q=>q.npc.displayID).filter(Boolean))];
  let cursor=0, completed=0;
  // Resolve each appearance once, with bounded concurrency. Missing portraits
  // do not discard otherwise valid audio comparisons or invent race/sex data.
  await Promise.all(Array.from({length:6},async()=>{
    while(cursor<displays.length) {
      const displayID=displays[cursor++];
      try {
        const meta=JSON.parse(await modelAsset(`/modelviewer/classicplus/meta/npc/${displayID}.json`));
        const model=meta.Model || (meta.Character?.ChrModelId && JSON.parse(await modelAsset(
          `/modelviewer/classicplus/meta/character/${meta.Character.ChrModelId}.json`)).Model);
        if(!Number.isSafeInteger(model) || model<=0) throw Error('Unknown model file');
        models.set(displayID,model);
      } catch(error) {modelErrors.push({displayID,error:error.message});}
      onProgress(++completed,displays.length);
    }
  }));
  const quests=catalogue.quests.map(quest=>{
    const modelFileID=models.get(quest.npc.displayID) || 0;
    const {id,displayID,race,sex}=quest.npc;
    return {questID:quest.questID,npc:{id,displayID,modelFileID,race,sex},
      variants:quest.variants.map(variant=>{
        const {id,source,pack,version,sha256}=variant;
        const recording=history.packs[pack]?.recordings[variant.file];
        if(recording?.questID!==quest.questID || recording?.section!=='a')
          throw Error(`Expected a quest description: ${pack}/${variant.file}`);
        return {id,source,pack,version,sha256,revisions:revisionHashes(history,variant)};
      })};
  });
  await fs.mkdir(path.dirname(destination),{recursive:true});
  const temporary=`${destination}.${process.pid}.tmp`;
  const snapshot={schemaVersion:2,quests};
  await fs.writeFile(temporary,JSON.stringify(snapshot,null,2)+'\n');
  await fs.rename(temporary,destination);
  // Keep diagnostics separate from the portable API schema.
  const missing=quests.filter(q=>!q.npc.id || !q.npc.race || !q.npc.sex || !q.npc.displayID || !q.npc.modelFileID)
    .map(q=>({questID:q.questID,...q.npc}));
  await fs.writeFile(destination.replace(/\.json$/,'')+'.coverage.json',JSON.stringify({
    comparisons:quests.length,
    twoLibraries:quests.filter(q=>q.variants.length===2).length,
    threeLibraries:quests.filter(q=>q.variants.length===3).length,
    missingGiver:quests.filter(q=>!q.npc.id).length,
    missingRace:quests.filter(q=>!q.npc.race).length,
    missingSex:quests.filter(q=>!q.npc.sex).length,
    missingPortrait:quests.filter(q=>!q.npc.modelFileID).length,
    warnings:catalogue.warnings,modelErrors:modelErrors.sort((a,b)=>a.displayID-b.displayID),missing
  },null,2)+'\n');
  return snapshot;
}
if (process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const snapshot=await exportVoteCatalogue(process.argv[2],{onProgress:(done,total)=>{
    if(done%100===0 || done===total) console.log(`Portrait metadata: ${done}/${total}`);
  }});
  console.log(`Voting catalogue: ${snapshot.quests.length} comparisons`);
}

import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {buildCatalogue,addonsDirectory,repo} from './server.mjs';
import {exportVoteCatalogue} from './export-vote-catalogue.mjs';

// Metadata only. The externally installed libraries are never copied.
export async function exportSite(destination,{questIDs}={}) {
  await fs.mkdir(destination,{recursive:true});
  const trusted=await exportVoteCatalogue(path.join(destination,'catalogue.json'),{questIDs});
  const addons=addonsDirectory(),{catalogue,audio}=buildCatalogue(addons,{questIDs});
  const byID=new Map(trusted.quests.map(q=>[q.questID,q]));
  for(const quest of catalogue.quests) {
    const vote=byID.get(quest.questID);
    if(!vote || JSON.stringify(vote.variants.map(v=>v.id))!==JSON.stringify(quest.variants.map(v=>v.id)))
      throw Error('Libraries changed while exporting. Prepare a new snapshot.');
    quest.npc={...quest.npc,...vote.npc};
  }
  const manifest={schemaVersion:1,files:{}};
  for(const quest of catalogue.quests) for(const variant of quest.variants) {
    const relative=path.relative(addons,audio.get(variant.id)).split(path.sep).join('/');
    if(relative.startsWith('../') || path.isAbsolute(relative)) throw Error('Audio path leaves the libraries directory');
    manifest.files[variant.id]={path:relative,sha256:variant.sha256};
  }
  catalogue.warnings=[];
  await fs.writeFile(path.join(destination,'site-catalogue.json'),JSON.stringify(catalogue));
  await fs.writeFile(path.join(destination,'audio-manifest.json'),JSON.stringify(manifest));
  return {quests:catalogue.quests.length,recordings:Object.keys(manifest.files).length};
}
if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  console.log(await exportSite(path.resolve(process.argv[2] || path.join(repo,'artifacts/voice-vote-deploy/catalogue'))));
}

import fs from 'node:fs';
import path from 'node:path';

export function loadPortableData(directory,libraries) {
  const read=name=>JSON.parse(fs.readFileSync(path.join(directory,name),'utf8'));
  const catalogue=read('site-catalogue.json'),manifest=read('audio-manifest.json'),trusted=read('catalogue.json');
  if(manifest.schemaVersion!==1 || trusted.schemaVersion!==2 || !Array.isArray(catalogue.quests)) throw Error('Invalid site snapshot');
  const backend=new Map(trusted.quests.map(q=>[q.questID,q]));
  if(catalogue.quests.length!==backend.size) throw Error('Site and API catalogue differ');
  const root=fs.realpathSync(libraries),audio=new Map();
  for(const quest of catalogue.quests) {
    const accepted=backend.get(quest.questID);
    if(!accepted || JSON.stringify(accepted.npc)!==JSON.stringify(Object.fromEntries(Object.keys(accepted.npc).map(k=>[k,quest.npc[k]]))))
      throw Error('Site and API speaker metadata differ');
    if(accepted.variants.length!==quest.variants.length) throw Error('Site and API recordings differ');
    for(const variant of quest.variants) {
      const entry=manifest.files[variant.id];
      const recording=accepted.variants.find(v=>v.id===variant.id && v.sha256===variant.sha256 && v.source===variant.source && v.version===variant.version);
      if(!recording || !entry || entry.sha256!==variant.sha256 || !/^[a-f0-9]{24}$/.test(variant.id)
        || typeof entry.path!=='string' || entry.path.includes('\\') || entry.path.split('/').some(p=>!p || p==='.' || p==='..')
        || path.isAbsolute(entry.path) || /^[A-Za-z]:/.test(entry.path) || !entry.path.endsWith('.ogg')) throw Error('Invalid audio mapping');
      const file=fs.realpathSync(path.join(root,entry.path));
      if(!file.startsWith(root+path.sep) || !fs.statSync(file).isFile()) throw Error('Audio file leaves the libraries directory');
      if(variant.url!==`/api/audio/${variant.id}`) throw Error('Invalid audio URL');
      audio.set(variant.id,file);
    }
  }
  return {catalogue,audio};
}

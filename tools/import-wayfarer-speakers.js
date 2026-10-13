// Import quest roles and portraits without executing Lua or requiring OGG files.
const fs = require('fs'), path = require('path');
const {readPack} = require('./generate-wayfarer-metadata');
const {sha256} = require('./generate-speakers');
const {childVoiceMetadata} = require('./child-voice-metadata');
const positive = id => Number.isSafeInteger(id) && id > 0;
function collect(addons) {
  const packs = [];
  for (const name of fs.readdirSync(addons).filter(name => /^Wayfarer_Voices(?:_|$)/.test(name)).sort()) {
    const directory = path.join(addons,name);
    if (!fs.statSync(directory).isDirectory()) continue;
    const bytes = fs.readFileSync(path.join(directory,'Index.lua'));
    const pack = readPack(bytes);
    const version = fs.readFileSync(path.join(directory,name+'.toc'),'utf8').match(/^##\s*Version:\s*(\S+)/m)?.[1];
    if (pack.name !== name || pack.format !== 1 || !version || version !== pack.version || !pack.q) throw Error('Unsupported Wayfarer pack: '+name);
    packs.push({pack,sha256:sha256(bytes)});
  }
  if (!packs.length) throw Error('No Wayfarer voice packs found');
  // Same deterministic pack order as the text importer, independent of runtime settings.
  packs.sort((a,b)=>Number(b.pack.model==='v4')-Number(a.pack.model==='v4') || a.pack.name.localeCompare(b.pack.name));
  const result = {schemaVersion:1,packs:{},givers:{},finishers:{},npcs:{},conflicts:[]};
  function reference(role,id,npc,pack) {
    if (npc == null) return;
    if (!positive(Number(id)) || (npc !== 'narrator' && !positive(npc))) throw Error(`Invalid Wayfarer ${role} reference: ${pack}/${id}`);
    const previous = result[role][id];
    if (previous != null && previous !== npc) {
      result.conflicts.push({role,questId:Number(id),previous,incoming:npc,pack});
      result[role][id] = false; // conflicting identities must not become one guessed NPC
    } else result[role][id] = npc;
  }
  for (const {pack,sha256} of packs) {
    result.packs[pack.name] = {version:pack.version,model:pack.model || '',indexSha256:sha256};
    // A description's explicit narrator is more specific than generic qg data.
    for (const [id,npc] of Object.entries(pack.qg || {}))
      if (pack.q[id]?.a?.v !== 'narrator') reference('givers',id,npc,pack.name);
    for (const [id,quest] of Object.entries(pack.q)) {
      if (!positive(Number(id))) throw Error('Invalid Wayfarer quest ID');
      reference('givers',id,quest.a?.v === 'narrator' ? 'narrator' : quest.a?.s,pack.name);
      reference('finishers',id,quest.c?.s,pack.name);
      reference('finishers',id,quest.p?.s,pack.name);
    }
    for (const [id,npc] of Object.entries(pack.npc || {})) {
      if (!positive(Number(id)) || (npc.d != null && !positive(npc.d)) || (npc.n != null && typeof npc.n !== 'string')) throw Error('Invalid Wayfarer NPC metadata');
      const previous = result.npcs[id] ||= {};
      if (npc.d && previous.displayID && npc.d !== previous.displayID) {
        result.conflicts.push({npcID:Number(id),field:'displayID',selected:previous.displayID,rejected:npc.d,pack:pack.name});
      }
      if (npc.d && !previous.displayID) previous.displayID = npc.d;
      if (npc.n?.trim() && (!previous.name || (/[А-Яа-яЁё]/.test(npc.n) && !/[А-Яа-яЁё]/.test(previous.name)))) previous.name = npc.n;
    }
  }
  const observations = [];
  for (const {pack} of packs) for (const [id, quest] of Object.entries(pack.q)) {
    for (const stage of ['a','p','c']) {
      const entry = quest[stage];
      const npcID = entry?.s ?? (stage === 'a' ? pack.qg?.[id] : undefined);
      const role = stage === 'a' ? 'givers' : 'finishers';
      if (npcID === result[role][id]) observations.push({npcID,voice:entry?.v});
    }
  }
  for (const [id, metadata] of Object.entries(childVoiceMetadata(observations))) {
    Object.assign(result.npcs[id] ||= {}, metadata);
  }
  return result;
}
function importSpeakers(addons, check = false) {
  const result = collect(addons);
  const file = path.join(__dirname,'../docs/internal/wayfarer-speakers-source.json');
  const content = JSON.stringify(result,null,2)+'\n';
  if (check) {
    if (fs.readFileSync(file,'utf8').replace(/\r\n/g,'\n') !== content) throw Error('Wayfarer speaker snapshot differs from installed packs');
  } else fs.writeFileSync(file,content);
  return require('./generate-speakers').generate(check);
}
module.exports = {collect,importSpeakers};
if (require.main === module) {
  if (!process.argv[2]) throw Error('Usage: node tools/import-wayfarer-speakers.js <AddOns directory> [--check]');
  console.log(JSON.stringify(importSpeakers(process.argv[2],process.argv.includes('--check')).counts));
}

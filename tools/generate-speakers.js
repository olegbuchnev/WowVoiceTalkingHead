// Merge speaker facts at build time. The game loads only Speakers.lua.
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const { dataTable } = require('./import-forever-audio');
const root = path.resolve(__dirname, '..');
const positive = n => Number.isSafeInteger(n) && n > 0;
const sha256 = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const sorted = object => Object.entries(object).sort((a,b) => Number(a[0])-Number(b[0]));
const read = file => JSON.parse(fs.readFileSync(path.join(root, file), 'utf8'));
// Fixed policy based on expected maintenance frequency, not version-number
// comparisons between unrelated projects. Explicit exclusions are applied first.
const POLICY = {
  basis:'maintenance-frequency',
  givers:['catquest','wayfarer','pins','classic'],
  finishers:['catquest','wayfarer','classic'],
  names:{preferRussian:true, sources:['catquest','wayfarer','classic']},
  appearances:['catquest','wayfarer'],
  protectedExclusions:['multiple-or-conflicting-starters']
};

function merge({ classic, pins, cat, wayfarer = {givers:{},finishers:{},npcs:{}} }) {
  const givers = {}, finishers = {}, npcs = {}, origins = {givers:{}, finishers:{}, npcs:{}}, conflicts = [];
  const names = new Map();
  function addName(id, name, source) {
    if (!positive(id) || typeof name !== 'string' || !name.trim()) return;
    if (!names.has(id)) names.set(id, []);
    names.get(id).push({name, source});
  }
  function collectClassic(idField, nameField) {
    const result = {};
    for (const [title, rows] of Object.entries(classic)) for (const row of Object.values(rows)) {
      if (!positive(row.q)) continue;
      const id = positive(row[idField]) ? row[idField] : null;
      addName(id, row[nameField], 'classic');
      const value = id ? {npcID:id, title} : null;
      if (!(row.q in result)) result[row.q] = value;
      else if (result[row.q]?.npcID !== value?.npcID) result[row.q] = false;
    }
    return result;
  }
  const classicGivers = collectClassic('i', 'n'), classicFinishers = collectClassic('ei', 'en');
  // Absence in Classic is unknown, not evidence of an item/object starter.
  function set(role, id, value, source) {
    const target = role === 'givers' ? givers : finishers;
    if (!positive(Number(id)) || (value !== false && !positive(value.npcID))) throw Error('Invalid speaker mapping');
    if (id in target) {
      if (target[id]?.npcID !== value?.npcID) conflicts.push({questId:Number(id), role,
        selected:origins[role][id], selectedNPC:target[id]?.npcID || false, rejected:source, rejectedNPC:value?.npcID || false});
      return;
    }
    target[id] = value; origins[role][id] = source;
  }
  const exclusions = {};
  const npcMap = map => Object.fromEntries(Object.entries(map).map(([id,npcID]) => [id,npcID === false ? false : {npcID}]));
  const giverSources = {catquest:npcMap(cat.tables.QuestGiver), wayfarer:npcMap(wayfarer.givers), pins:npcMap(pins.givers), classic:classicGivers};
  // A lower-priority explicit multiple-starter fact still prevents
  // guessing one NPC. Unknown/missing data does not block the next source.
  for (const source of POLICY.givers) for (const [id, entry] of sorted(giverSources[source])) if (entry === false) {
    set('givers', id, false, source);
    exclusions[id] ||= {source, reason:'multiple-or-conflicting-starters'};
  }
  for (const source of POLICY.givers) for (const [id, entry] of sorted(giverSources[source])) {
    if (entry !== null) set('givers', id, entry, source);
  }
  const finisherSources = {catquest:npcMap(cat.tables.QuestFinisher), wayfarer:npcMap(wayfarer.finishers), classic:classicFinishers};
  for (const source of POLICY.finishers) for (const [id, entry] of sorted(finisherSources[source])) {
    if (entry !== null) set('finishers', id, entry, source);
  }
  for (const [id, npc] of sorted(cat.tables.NpcData)) {
    if (!positive(Number(id)) || (npc[3] != null && !positive(npc[3]))) throw Error('Invalid NPC/model ID');
    npcs[id] = {};
    if (positive(npc[3])) { npcs[id].displayID = npc[3]; origins.npcs[id] = {displayID:'catquest'}; }
    if (typeof npc[1] === 'string') npcs[id].race = npc[1];
    if (typeof npc[2] === 'string') npcs[id].sex = npc[2];
    addName(Number(id), npc[4], 'catquest');
  }
  const appearanceConflicts = [];
  for (const [id,npc] of sorted(wayfarer.npcs)) {
    if (!positive(Number(id)) || (npc.displayID != null && !positive(npc.displayID))) throw Error('Invalid Wayfarer NPC/model ID');
    const existing = npcs[id] ||= {};
    if (npc.displayID && existing.displayID && npc.displayID !== existing.displayID) {
      appearanceConflicts.push({npcID:Number(id),selected:'catquest',selectedDisplay:existing.displayID,rejected:'wayfarer',rejectedDisplay:npc.displayID});
    }
    if (npc.displayID && !existing.displayID) {
      existing.displayID = npc.displayID;
      origins.npcs[id] ||= {}; origins.npcs[id].displayID = 'wayfarer';
    }
    addName(Number(id),npc.name,'wayfarer');
  }
  for (const [id, candidates] of names) {
    // Language preference is independent of the identity/source priority.
    const rank = Object.fromEntries(POLICY.names.sources.map((source,index)=>[source,index]));
    candidates.sort((a,b) => Number(/[А-Яа-яЁё]/.test(b.name))-Number(/[А-Яа-яЁё]/.test(a.name)) || rank[a.source]-rank[b.source]);
    npcs[id] ||= {}; npcs[id].name = candidates[0].name;
    origins.npcs[id] ||= {}; origins.npcs[id].name = candidates[0].source;
  }
  for (const role of [givers, finishers]) for (const [id, record] of Object.entries(role)) if (record) {
    npcs[record.npcID] ||= {};
    const name = npcs[record.npcID].name;
    if (name) record.name = name;
  }
  return {database:{schemaVersion:1, givers, finishers, npcs}, origins, conflicts, exclusions, appearanceConflicts};
}

function luaValue(value) {
  if (value === false) return 'false';
  if (typeof value === 'number') return String(value);
  if (typeof value === 'string') return '"' + value.replace(/[\\"\x00-\x1f\x7f]/g, c =>
    c === '\\' || c === '"' ? '\\' + c : '\\' + c.charCodeAt(0).toString().padStart(3,'0')) + '"';
  return '{ ' + Object.entries(value).map(([key,entry]) => `${key} = ${luaValue(entry)}`).join(', ') + ' }';
}
function render(database) {
  return '-- Generated by tools/generate-speakers.js; do not edit.\n'
    + '-- Unified quest roles and NPC appearances; captured game data takes priority.\n'
    + '-- Input versions, decisions and conflicts: docs/internal/speakers-manifest.json.\n'
    + 'WowVoiceSpeakers = { schemaVersion = 1,\n'
    + ['givers','finishers','npcs'].map(key => key+' = {\n'+sorted(database[key])
      .map(([id,value]) => `    [${id}] = ${luaValue(value)},`).join('\n')+'\n},').join('\n')+'\n}\n';
}
function generate(check = false) {
  const files = {classic:'src/Index.lua',
    pins:'docs/internal/forever-pins-speakers-source.json', cat:'docs/internal/catquest-speakers-source.json', wayfarer:'docs/internal/wayfarer-speakers-source.json'};
  const inputs = {classic:dataTable(path.join(root,files.classic)), pins:read(files.pins), cat:read(files.cat), wayfarer:read(files.wayfarer)};
  const result = merge(inputs);
  const report = {schemaVersion:1, policy:POLICY, sources:{
    pins:{commit:inputs.pins.commit, attCommit:inputs.pins.attCommit},
    catquest:{version:inputs.cat.sourceVersion}, wayfarer:{packs:inputs.wayfarer.packs}},
    inputHashes:Object.fromEntries(Object.entries(files).map(([key,file])=>[key,
      sha256(fs.readFileSync(path.join(root,file),'utf8').replace(/\r\n/g,'\n'))])),
    counts:Object.fromEntries(['givers','finishers','npcs'].map(key => [key,Object.keys(result.database[key]).length])),
    origins:result.origins, protectedExclusions:result.exclusions, conflicts:result.conflicts, appearanceConflicts:result.appearanceConflicts};
  for (const [file, content] of [['src/Speakers.lua',render(result.database)],
    ['docs/internal/speakers-manifest.json',JSON.stringify(report,null,2)+'\n']]) {
    if (check) { if (fs.readFileSync(path.join(root,file),'utf8').replace(/\r\n/g,'\n') !== content) throw Error('Stale speaker data: '+file); }
    else fs.writeFileSync(path.join(root,file),content);
  }
  return report;
}
module.exports = {merge,render,generate,sha256,POLICY};
if (require.main === module) console.log(JSON.stringify(generate(process.argv.includes('--check')).counts));

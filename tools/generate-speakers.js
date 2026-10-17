// Merge speaker facts at build time. The game loads only Speakers.lua.
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const { dataTable } = require('./import-forever-audio');
const {childVoiceMetadata} = require('./child-voice-metadata');
const {creatureVoiceMetadata} = require('./creature-voice-metadata');
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
  names:{preferRussian:true, sources:['catquest','wayfarer','classic','verified-supplement']},
  appearances:['catquest','wayfarer','verified-supplement'],
  raceClassification:'verified-appearance-before-library-voice-label',
  creatureCategories:['verified-appearance','catquest-voice','wayfarer-voice','catquest-npc'],
  unsexedCreatureCategories:{ancient:'male',furbolg:'male',elemental_water:'male'},
  childCategories:{human:'human_child',orc:'orc_child'},
  protectedExclusions:['multiple-or-conflicting-starters'],
  speakerOverrides:'explicit-quest-role-with-expected-NPC; preserve-protected-exclusions'
};

function merge({ classic, pins, cat, catAudio = {entries:{}}, wayfarer = {givers:{},finishers:{},npcs:{}}, supplements = {schemaVersion:1,npcs:{}}, raceClassifications = {schemaVersion:1,appearances:{},models:{}}, speakerOverrides = {schemaVersion:1,givers:{},finishers:{}} }) {
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
    if (!positive(Number(id)) || (value !== false && value.narrator !== true && !positive(value.npcID))) throw Error('Invalid speaker mapping');
    if (id in target) {
      if (target[id]?.npcID !== value?.npcID || target[id]?.narrator !== value?.narrator) conflicts.push({questId:Number(id), role,
        selected:origins[role][id], selectedNPC:target[id]?.npcID || false, rejected:source, rejectedNPC:value?.npcID || false});
      return;
    }
    target[id] = value; origins[role][id] = source;
  }
  const exclusions = {};
  const npcMap = map => Object.fromEntries(Object.entries(map).map(([id,npcID]) => [id,
    npcID === false ? false : npcID === 'narrator' ? {narrator:true} : {npcID}]));
  const giverSources = {catquest:npcMap(cat.tables.QuestGiver), wayfarer:npcMap(wayfarer.givers), pins:npcMap(pins.givers), classic:classicGivers};
  for (const [key, entry] of Object.entries(catAudio.entries)) {
    const match = /^(\d+)a$/.exec(key);
    if (match && entry.voice === 'narrator') giverSources.catquest[match[1]] = {narrator:true};
  }
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
  // Reviewed narration is a quest-role decision, not an NPC race or a voice label.
  if (speakerOverrides.schemaVersion !== 1 || !speakerOverrides.givers || !speakerOverrides.finishers)
    throw Error('Invalid speaker overrides');
  for (const [role,target] of [['givers',givers],['finishers',finishers]]) {
    for (const [id,entry] of Object.entries(speakerOverrides[role])) {
      if (!positive(Number(id)) || !positive(entry.expectedNPC) || entry.narrator !== true || !speakerOverrides.reason?.trim())
        throw Error('Invalid narrator override: '+role+'/'+id);
      const previous=target[id];
      if (previous === false) continue; // Explicit ambiguous identities remain blocked.
      if (!previous || (!previous.narrator && previous.npcID !== entry.expectedNPC))
        throw Error('Narrator override no longer matches its NPC: '+role+'/'+id);
      if (!previous.narrator) conflicts.push({questId:Number(id),role,selected:'manual-narrator',selectedNPC:false,
        rejected:origins[role][id],rejectedNPC:previous.npcID});
      target[id]={narrator:true};
      origins[role][id]='manual-narrator';
    }
  }
  for (const [id, npc] of sorted(cat.tables.NpcData)) {
    if (!positive(Number(id)) || (npc[3] != null && !positive(npc[3]))) throw Error('Invalid NPC/model ID');
    npcs[id] = {};
    if (positive(npc[3])) { npcs[id].displayID = npc[3]; origins.npcs[id] = {displayID:'catquest'}; }
    if (typeof npc[1] === 'string') npcs[id].race = npc[1];
    if (typeof npc[2] === 'string') npcs[id].sex = npc[2];
    addName(Number(id), npc[4], 'catquest');
  }
  // Fill absent child metadata from this source's own speaker references.
  // Never attach a voice to a different NPC chosen from a lower-priority source.
  const childObservations = [];
  for (const [key, entry] of Object.entries(catAudio.entries)) {
    const match = /^(\d+)([apc])$/.exec(key);
    if (!match) continue;
    const role = match[2] === 'a' ? 'QuestGiver' : 'QuestFinisher';
    childObservations.push({npcID:cat.tables[role][match[1]],voice:entry.voice});
  }
  function fillChildMetadata(id, metadata, source) {
    const npc = npcs[id] ||= {};
    for (const field of ['ageGroup','sex']) if (!npc[field] && metadata[field]) {
      npc[field] = metadata[field];
      (origins.npcs[id] ||= {})[field] = source;
    }
  }
  for (const [id, metadata] of Object.entries(childVoiceMetadata(childObservations)))
    fillChildMetadata(id,metadata,'catquest-voice');
  const creatureVoices = creatureVoiceMetadata(childObservations);
  for (const [id, metadata] of Object.entries(creatureVoices)) {
    (npcs[id] ||= {}).race = metadata.voiceRace;
    (origins.npcs[id] ||= {}).race = 'catquest-voice';
    if (metadata.voiceSex) {
      npcs[id].sex = metadata.voiceSex;
      origins.npcs[id].sex = 'catquest-voice';
    }
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
    if ((!creatureVoices[id] || creatureVoices[id].voiceRace === npc.voiceRace)
        && ['ancient','furbolg','banshee','dreadlord','elemental_water','imp','centaur','dragon'].includes(npc.voiceRace)) {
      if (!creatureVoices[id]) {
        existing.race = npc.voiceRace;
        (origins.npcs[id] ||= {}).race = 'wayfarer-voice';
      }
      if (!creatureVoices[id]?.voiceSex && ((['imp','centaur'].includes(npc.voiceRace) && npc.voiceSex === 'male')
          || (npc.voiceRace === 'dragon' && ['male','female'].includes(npc.voiceSex)))) {
        existing.sex = npc.voiceSex;
        (origins.npcs[id] ||= {}).sex = 'wayfarer-voice';
      }
    }
    if (npc.ageGroup === 'child' && ['male','female'].includes(npc.sex))
      fillChildMetadata(id,{ageGroup:npc.ageGroup,sex:npc.sex},'wayfarer-voice');
  }
  // Verified, exact-NPC appearances only fill missing library data. They never
  // infer quest roles or copy an appearance from a similarly named character.
  if (supplements.schemaVersion !== 1 || !supplements.npcs) throw Error('Invalid appearance supplements');
  for (const [id, entry] of sorted(supplements.npcs)) {
    if (!positive(Number(id)) || !positive(entry.displayID)
        || !new RegExp('^https://www\\.wowhead\\.com/forever/(?:ru/)?npc='+id+'(?:/|$)').test(entry.source)
        || !/^\d{4}-\d{2}-\d{2}$/.test(entry.verifiedOn) || !entry.evidence?.trim())
      throw Error('Invalid appearance supplement: '+id);
    if (entry.nameRu !== undefined) {
      if (typeof entry.nameRu !== 'string' || !/[А-Яа-яЁё]/.test(entry.nameRu)
          || !entry.source.startsWith('https://www.wowhead.com/forever/ru/'))
        throw Error('Invalid Russian name supplement: '+id);
      addName(Number(id),entry.nameRu.trim(),'verified-supplement');
    }
    const npc = npcs[id] ||= {};
    if (!npc.displayID) {
      npc.displayID = entry.displayID;
      origins.npcs[id] ||= {}; origins.npcs[id].displayID = 'verified-supplement';
    }
  }
  // Library voice categories may combine distinct races (e.g. furbolgs/tauren).
  // Apply only verified appearances; never guess race from names or voice sex.
  if (raceClassifications.schemaVersion !== 1 || !raceClassifications.appearances || !raceClassifications.models)
    throw Error('Invalid NPC race classifications');
  for (const [displayID, entry] of Object.entries(raceClassifications.appearances)) {
    const model = raceClassifications.models[entry.modelFileID];
    if (!positive(Number(displayID)) || !positive(entry.modelFileID)
        || !/^[a-z][a-z0-9_]*$/.test(entry.race || '') || model?.race !== entry.race
        || !model.file?.endsWith('.m2') || !model.source?.startsWith('https://'))
      throw Error('Invalid NPC race classification: '+displayID);
  }
  for (const [id,npc] of Object.entries(npcs)) {
    const classification = raceClassifications.appearances[npc.displayID];
    if (classification) {
      npc.race = classification.race;
      (origins.npcs[id] ||= {}).race = 'verified-appearance';
    }
    if (npc.ageGroup === 'child' && POLICY.childCategories[npc.race]) {
      npc.race = POLICY.childCategories[npc.race];
      (origins.npcs[id] ||= {}).race = 'known-race-and-child-age';
    }
    if (Object.values(POLICY.childCategories).includes(npc.race) && npc.ageGroup !== 'child') {
      npc.ageGroup = 'child';
      (origins.npcs[id] ||= {}).ageGroup = 'verified-child-category';
    }
    // These vote categories intentionally have no male/female subdivisions.
    // "male" is the schema's canonical grouping value, not a biological claim.
    if (POLICY.unsexedCreatureCategories[npc.race]) {
      npc.sex = POLICY.unsexedCreatureCategories[npc.race];
      (origins.npcs[id] ||= {}).sex = 'unsexed-creature-category';
    }
  }
  for (const [id, candidates] of names) {
    // Language preference is independent of the identity/source priority.
    const rank = Object.fromEntries(POLICY.names.sources.map((source,index)=>[source,index]));
    candidates.sort((a,b) => Number(/[А-Яа-яЁё]/.test(b.name))-Number(/[А-Яа-яЁё]/.test(a.name)) || rank[a.source]-rank[b.source]);
    npcs[id] ||= {}; npcs[id].name = candidates[0].name;
    origins.npcs[id] ||= {}; origins.npcs[id].name = candidates[0].source;
  }
  for (const role of [givers, finishers]) for (const [id, record] of Object.entries(role)) if (record && !record.narrator) {
    npcs[record.npcID] ||= {};
    const name = npcs[record.npcID].name;
    if (name) record.name = name;
  }
  return {database:{schemaVersion:1, givers, finishers, npcs}, origins, conflicts, exclusions, appearanceConflicts};
}

function luaValue(value) {
  if (typeof value === 'boolean') return String(value);
  if (typeof value === 'number') return String(value);
  if (typeof value === 'string') return '"' + value.replace(/[\\"\x00-\x1f\x7f]/g, c =>
    c === '\\' || c === '"' ? '\\' + c : '\\' + c.charCodeAt(0).toString().padStart(3,'0')) + '"';
  return '{ ' + Object.entries(value).map(([key,entry]) => `${key} = ${luaValue(entry)}`).join(', ') + ' }';
}
function render(database) {
  return '-- Generated by tools/generate-speakers.js; do not edit.\n'
    + '-- Unified quest roles and NPC appearances; captured game data takes priority.\n'
    + '-- Input versions, decisions and conflicts: docs/internal/speakers-manifest.json.\n'
    + 'TalkingHeadRuSpeakers = { schemaVersion = 1,\n'
    + ['givers','finishers','npcs'].map(key => key+' = {\n'+sorted(database[key])
      .map(([id,value]) => `    [${id}] = ${luaValue(value)},`).join('\n')+'\n},').join('\n')+'\n}\n';
}
function generate(check = false) {
  const files = {classic:'src/Index.lua',
    pins:'docs/internal/forever-pins-speakers-source.json', cat:'docs/internal/catquest-speakers-source.json', wayfarer:'docs/internal/wayfarer-speakers-source.json',
    supplements:'docs/internal/npc-appearance-supplements.json',raceClassifications:'docs/internal/npc-race-classifications.json',speakerOverrides:'docs/internal/speaker-overrides.json',catAudio:'src/CatQuestAudio.lua'};
  const inputs = {classic:dataTable(path.join(root,files.classic)), pins:read(files.pins), cat:read(files.cat), wayfarer:read(files.wayfarer), supplements:read(files.supplements),raceClassifications:read(files.raceClassifications),speakerOverrides:read(files.speakerOverrides),catAudio:dataTable(path.join(root,files.catAudio))};
  const result = merge(inputs);
  const report = {schemaVersion:1, policy:POLICY, sources:{
    pins:{commit:inputs.pins.commit, attCommit:inputs.pins.attCommit},
    catquest:{version:inputs.cat.sourceVersion,voicesVersion:inputs.catAudio.sourceVersion}, wayfarer:{packs:inputs.wayfarer.packs}},
    inputHashes:Object.fromEntries(Object.entries(files).map(([key,file])=>[key,
      sha256(fs.readFileSync(path.join(root,file),'utf8').replace(/\r\n/g,'\n'))])),
    counts:Object.fromEntries(['givers','finishers','npcs'].map(key => [key,Object.keys(result.database[key]).length])),
    origins:result.origins, protectedExclusions:result.exclusions, conflicts:result.conflicts, appearanceConflicts:result.appearanceConflicts};
  for (const [file, content] of [['src/Speakers.lua',render(result.database)],
    ['docs/internal/speakers-manifest.json',JSON.stringify(report,null,2)+'\n']]) {
    if (check) { if (fs.readFileSync(path.join(root,file),'utf8').replace(/\r\n/g,'\n') !== content) throw Error('Stale speaker data: '+file); }
    else fs.writeFileSync(path.join(root,file),content);
  }
  require('./generate-voice-group-portraits').generate(result.database,check);
  return report;
}
module.exports = {merge,render,generate,sha256,POLICY};
if (require.main === module) console.log(JSON.stringify(generate(process.argv.includes('--check')).counts));

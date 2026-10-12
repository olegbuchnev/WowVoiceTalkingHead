// Build independent quest text metadata. Never execute addon code or require audio files.
const fs = require('fs'), path = require('path');
const crypto = require('crypto');
const {dataTable} = require('./import-forever-audio');
const {readPack, literal} = require('./generate-wayfarer-metadata');
const PRIORITY = ['wowvoice', 'catquest', 'wayfarer'];
function cueText(cues) {
  const lines = Object.values(cues || {}).map(cue => Array.isArray(cue) ? cue?.[1] : cue?.[2]);
  return lines.length && lines.every(line => typeof line === 'string' && line.trim())
    ? lines.map(line => line.trim()).join(' ') : undefined;
}
function valid(text) { return typeof text === 'string' && !!text.trim(); }
// Retain removed subtitles only for the exact same external audio bytes.
// Text-only imports still work when the audio files are not installed.
function retainCatQuestTexts(directory, pack, json, texts, version, history, verifiedFiles) {
  const retained = [];
  for (const id of new Set([...Object.keys(pack), ...Object.keys(json)])) {
    if (!/^[1-9]\d*$/.test(id)) continue;
    for (const section of ['a', 'c']) {
      const entry = section === 'a' ? (pack[id] || json[id]) : (pack[id]?.t || json[id]?.t);
      if (!entry || !(entry.d > 0)) continue;
      const key = id + section, stem = id + (section === 'c' ? '_t' : '');
      for (const variant of entry.g ? ['male', 'female'] : ['common']) {
        const file = stem + (variant === 'common' ? '' : '_' + variant[0]) + '.ogg';
        const location = path.join(directory, 'Sounds/q', file);
        const sha256 = verifiedFiles?.get(file)?.sha256
          || (fs.existsSync(location) ? crypto.createHash('sha256').update(fs.readFileSync(location)).digest('hex') : null);
        if (!sha256) continue;
        const text = texts[key]?.common || texts[key]?.[variant];
        if (valid(text)) {
          history.files[file] ||= {};
          const previous = history.files[file][sha256];
          if (previous?.text !== text) history.files[file][sha256] = {text, sourceVersion:version};
        } else {
          // Do not let a historical common text override current gendered text.
          if (variant === 'common' && (valid(texts[key]?.male) || valid(texts[key]?.female))) continue;
          const previous = history.files[file]?.[sha256];
          if (!valid(previous?.text)) continue;
          texts[key] ||= {};
          texts[key][variant] = previous.text;
          retained.push({key, variant, file, sha256, sourceVersion:previous.sourceVersion});
        }
      }
    }
  }
  return retained;
}
// Resolve each player variant separately: higher-priority common text also wins
// over lower-priority gendered text. A missing variant can come from another source.
function merge(sources) {
  const entries = {}, provenance = {};
  const keys = new Set(PRIORITY.flatMap(source => Object.keys(sources[source] || {})));
  for (const key of [...keys].sort((a,b) => parseInt(a)-parseInt(b) || a.localeCompare(b))) {
    if (!/^[1-9]\d*[apc]$/.test(key)) throw Error(`Invalid text key: ${key}`);
    const selected = {}, origins = {};
    for (const variant of ['male', 'female']) {
      for (const source of PRIORITY) {
        const candidate = sources[source]?.[key];
        const text = valid(candidate?.common) ? candidate.common : candidate?.[variant];
        if (valid(text)) { selected[variant] = text.trim(); origins[variant] = source; break; }
      }
    }
    if (!Object.keys(selected).length) continue;
    if (selected.male === selected.female && origins.male === origins.female) {
      entries[key] = {common: selected.male}; provenance[key] = {common: origins.male};
    } else { entries[key] = selected; provenance[key] = origins; }
  }
  return {entries, provenance};
}
function stats(entries) {
  const quests = new Set(), sections = {a:0,p:0,c:0}; let variants = 0;
  for (const [key, entry] of Object.entries(entries)) {
    quests.add(key.slice(0,-1)); sections[key.slice(-1)]++; variants += Object.keys(entry).length;
  }
  return {quests:quests.size, sections, variants};
}
function collect(addons, options = {}) {
  // Current WowVoice Index.lua has text hashes, titles and NPCs, no transcripts.
  // Keep its reserved first position explicit in the shared merge algorithm.
  const sources = {wowvoice:{}, catquest:{}, wayfarer:{}}, versions = {};
  const historyPath = path.join(options.textHistoryRoot || path.resolve(__dirname,'..'), 'docs/internal/catquest-text-history.json');
  const catquestTextHistory = fs.existsSync(historyPath) ? JSON.parse(fs.readFileSync(historyPath,'utf8'))
    : {schemaVersion:1, files:{}};
  if (catquestTextHistory.schemaVersion !== 1 || !catquestTextHistory.files) throw Error('Invalid CatQuest text history');
  let retainedCatQuestTexts = [];
  const cat = options.catquest || path.join(addons, 'CatQuest_Voices');
  if (fs.existsSync(cat)) {
    versions.catquest = fs.readFileSync(path.join(cat,'CatQuest_Voices.toc'),'utf8')
      .match(/^##\s*Version:\s*(\S+)/m)?.[1] || '';
    const pack = dataTable(path.join(cat,'Index.lua'));
    const jsonPath = path.join(cat,'index.json');
    const json = fs.existsSync(jsonPath) ? JSON.parse(fs.readFileSync(jsonPath,'utf8')) : {};
    // Lua wins within CatQuest; JSON supplies otherwise missing sections/variants.
    // Text import intentionally has no duration or file-availability requirement.
    for (const records of [pack,json]) {
      for (const [id, quest] of Object.entries(records)) {
        if (!/^[1-9]\d*$/.test(id) || !quest) continue;
        for (const [section, entry] of [['a',quest],['c',quest.t]]) {
          if (!entry) continue;
          const candidate = {};
          for (const [variant, field] of [['common','x'],['male','m'],['female','f']]) {
            const text = cueText(entry.c?.[field]);
            if (text) candidate[variant] = text;
          }
          const key = id+section;
          if (Object.keys(candidate).length) {
            const merged = merge({catquest:{[key]:sources.catquest[key]},wayfarer:{[key]:candidate}});
            sources.catquest[key] = merged.entries[key];
          }
        }
      }
    }
    retainedCatQuestTexts = retainCatQuestTexts(cat, pack, json, sources.catquest, versions.catquest,
      catquestTextHistory, options.catquestFiles);
  }
  const packs = [];
  for (const name of fs.readdirSync(addons).filter(name => /^Wayfarer_Voices_/.test(name)).sort()) {
    const directory = path.join(addons,name);
    if (!fs.statSync(directory).isDirectory()) continue;
    const pack = readPack(fs.readFileSync(path.join(directory,'Index.lua')));
    if (pack.name !== name || pack.format !== 1 || !pack.q) throw Error(`Unsupported text pack: ${name}`);
    packs.push(pack); versions[name] = pack.version;
  }
  // Stable preference within Wayfarer, independent of saved UI/audio settings.
  packs.sort((a,b) => Number(b.model === 'v4')-Number(a.model === 'v4') || a.name.localeCompare(b.name));
  for (const pack of packs) {
    for (const [id,quest] of Object.entries(pack.q)) {
      for (const section of ['a','p','c']) {
        const entry = quest[section]; if (!entry) continue;
        const candidate = {};
        for (const [variant,field] of [['common','t'],['male','tm'],['female','tf']]) {
          const text = cueText(entry[field]); if (text) candidate[variant] = text;
        }
        if (!Object.keys(candidate).length) continue;
        const key = id+section;
        sources.wayfarer[key] = merge({catquest:{[key]:sources.wayfarer[key]},wayfarer:{[key]:candidate}}).entries[key];
      }
    }
  }
  return {sources, versions, catquestTextHistory, retainedCatQuestTexts};
}
function importTexts(addons, root = path.resolve(__dirname,'..'), options = {}) {
  const {sources,versions,catquestTextHistory,retainedCatQuestTexts} = collect(addons,{...options,textHistoryRoot:root});
  const {entries,provenance} = merge(sources);
  if (!Object.keys(entries).length) throw Error('No quest transcripts found');
  const report = {schemaVersion:1, priority:PRIORITY, versions,
    sources:Object.fromEntries(PRIORITY.map(source => [source,stats(sources[source])])),
    merged:stats(entries), selectedSections:Object.fromEntries(PRIORITY.map(source => [source,
      Object.values(provenance).filter(record => Object.values(record).includes(source)).length])), retainedCatQuestTexts, provenance};
  const database = '-- Generated by tools/import-quest-texts.js. Fixed priority: WowVoice > CatQuest > Wayfarer.\n'
    + '-- CatQuest: Cathey (daniilcathey), https://t.me/catheyco. Wayfarer: installed voice packs.\n'
    + `WowVoiceQuestTexts = { schemaVersion = 1, sourceVersion = ${literal(versions.catquest || '')}, entries = {\n`
    + Object.entries(entries).map(([key,value]) => `    [${literal(key)}] = { `
      + Object.entries(value).map(([variant,text]) => `${variant} = ${literal(text)}`).join(', ') + ' },').join('\n') + '\n} }\n';
  fs.mkdirSync(path.join(root,'src'),{recursive:true});
  fs.mkdirSync(path.join(root,'docs/internal'),{recursive:true});
  fs.writeFileSync(path.join(root,'docs/internal/catquest-text-history.json'),JSON.stringify(catquestTextHistory,null,2)+'\n');
  fs.writeFileSync(path.join(root,'src/QuestTexts.lua'),database);
  fs.writeFileSync(path.join(root,'docs/internal/quest-texts-manifest.json'),JSON.stringify(report,null,2)+'\n');
  return report;
}
module.exports = {cueText, merge, collect, importTexts};
if (require.main === module) {
  if (!process.argv[2]) throw Error('Usage: node tools/import-quest-texts.js <AddOns directory> [output root]');
  const {provenance,...report} = importTexts(process.argv[2],process.argv[3]);
  console.log(JSON.stringify(report,null,2));
}

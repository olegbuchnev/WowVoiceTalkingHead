// Read-only coverage audit against the installed upstream quest databases.
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const { isDeepStrictEqual } = require('util');
const { dataTable, duration } = require('./import-forever-audio');
const { parse } = require('./import-catquest-speakers');
const root = path.resolve(__dirname, '..');
function audit(catDirectory, voicesDirectory) {
  const errors = [], counts = {}, gaps = {};
  const check = (ok, message) => { if (!ok) errors.push(message); };
  const read = file => dataTable(path.join(root, file));
  const version = (directory, toc) => fs.readFileSync(path.join(directory, toc), 'utf8').match(/^##\s*Version:\s*(\S+)/m)?.[1];
  function compare(label, expected, actual) {
    for (const key of new Set([...Object.keys(expected), ...Object.keys(actual || {})])) {
      check(isDeepStrictEqual(expected[key], actual?.[key]), `${label}: ${key}`);
    }
    counts[label] = Object.keys(expected).length;
  }
  const npcSource = parse(fs.readFileSync(path.join(catDirectory, 'NpcData.lua')));
  const npc = read('src/CatQuestSpeakers.lua');
  check(npc.sourceVersion === version(catDirectory, 'CatQuest.toc'), 'NPC source version differs');
  compare('NPC records', npcSource.NpcData, npc.npcs);
  compare('Quest givers', npcSource.QuestGiver, npc.givers);
  compare('Quest finishers', npcSource.QuestFinisher, npc.finishers);
  const pack = dataTable(path.join(voicesDirectory, 'Index.lua'));
  const json = JSON.parse(fs.readFileSync(path.join(voicesDirectory, 'index.json'), 'utf8'));
  const recovered = new Set();
  for (const [id, entry] of Object.entries(json)) {
    if (/^\d+$/.test(id) && !pack[id] && entry.d == null && entry.t?.d > 0) {
      pack[id] = { t: entry.t }; recovered.add(id);
    }
  }
  const classic = new Set(Object.keys(read('src/Durations.lua')).map(key => key.slice(0, -1)));
  const transcripts = {}, expectedAudio = {}, files = new Set();
  gaps.withoutDescriptionGiver = []; gaps.withoutDescriptionText = []; gaps.withoutTurnInText = [];
  let variants = 0;
  for (const [id, quest] of Object.entries(pack)) {
    if (!/^\d+$/.test(id)) continue;
    if (quest.d && !npcSource.QuestGiver[id]) gaps.withoutDescriptionGiver.push(Number(id));
    for (const [section, entry] of [['a', quest], ['c', quest.t]]) {
      if (!entry?.d) continue;
      const texts = {};
      for (const [variant, field] of entry.g ? [['m', 'male'], ['f', 'female']] : [['x', 'common']]) {
        const cues = Object.values(entry.c?.[variant] || {});
        if (cues.length && cues.every(cue => typeof cue[2] === 'string' && cue[2].trim())) {
          texts[field] = cues.map(cue => cue[2].trim()).join(' '); variants++;
        }
      }
      if (Object.keys(texts).length) transcripts[id + section] = texts;
      else gaps[section === 'a' ? 'withoutDescriptionText' : 'withoutTurnInText'].push(Number(id));
      const stem = id + (section === 'c' ? '_t' : '');
      const names = entry.g ? [stem + '_m.ogg', stem + '_f.ogg'] : [stem + '.ogg'];
      names.forEach(name => files.add(name));
      expectedAudio[id + section] = { indexDuration: entry.d, gender: !!entry.g,
        voice: entry.v || '', jsonOnly: recovered.has(id), files: names };
    }
  }
  const texts = read('src/QuestTexts.lua'), audio = read('src/CatQuestAudio.lua');
  const sourceVersion = version(voicesDirectory, 'CatQuest_Voices.toc');
  for (const [label, db] of [['texts', texts], ['audio', audio]]) {
    check(db.sourceVersion === sourceVersion, `${label} source version differs`);
  }
  // The standalone database also includes Wayfarer-only sections. CatQuest
  // wins each available variant; another source may fill an absent variant.
  for (const [key, entry] of Object.entries(transcripts)) {
    for (const [variant, text] of Object.entries(entry)) {
      const actual = texts.entries[key];
      if (variant === 'common') {
        check((actual?.common || actual?.male) === text && (actual?.common || actual?.female) === text, `Text sections: ${key}/common`);
      } else check((actual?.common || actual?.[variant]) === text, `Text sections: ${key}/${variant}`);
    }
  }
  counts['Text sections'] = Object.keys(transcripts).length;
  const actualAudio = {};
  for (const [key, entry] of Object.entries(audio.entries)) {
    actualAudio[key] = { indexDuration: entry.indexDuration, gender: entry.gender, voice: entry.voice,
      jsonOnly: entry.jsonOnly, files: entry.audio.male ? [entry.audio.male.file, entry.audio.female.file] : [entry.audio.file] };
  }
  compare('Complete CatQuest audio sections', expectedAudio, actualAudio);
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'docs/internal/forever-audio-manifest.json'), 'utf8'));
  const records = new Map(manifest.files.map(entry => [entry.file, entry]));
  for (const file of files) {
    const buffer = fs.readFileSync(path.join(voicesDirectory, 'Sounds/q', file));
    const entry = records.get(file);
    check(entry && crypto.createHash('sha256').update(buffer).digest('hex') === entry.sha256, 'External audio hash: ' + file);
  }
  for (const [key, entry] of Object.entries(audio.entries)) {
    for (const recording of entry.audio.male ? [entry.audio.male, entry.audio.female] : [entry.audio]) {
      check(recording.duration === duration(fs.readFileSync(path.join(voicesDirectory, 'Sounds/q', recording.file))), 'External duration: ' + key);
    }
  }
  counts['Text variants'] = variants;
  counts['External files verified by SHA-256'] = files.size;
  counts['Quests with selectable Classic overlap'] = Object.keys(pack).filter(id => classic.has(id)).length;
  for (const values of Object.values(gaps)) values.sort((a, b) => a - b);
  return { counts, errors, upstreamGaps: gaps };
}
module.exports = { audit };
if (require.main === module) {
  if (!process.argv[2] || !process.argv[3]) throw Error('Usage: node tools/audit-catquest.js <CatQuest directory> <CatQuest_Voices directory>');
  const report = audit(process.argv[2], process.argv[3]);
  console.log(JSON.stringify(report, null, 2));
  if (report.errors.length) process.exitCode = 1;
}

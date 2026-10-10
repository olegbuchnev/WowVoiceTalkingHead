// Import metadata for external CatQuest Voices and all transcripts; never copy audio.
// Parse the Lua index as data; never execute third-party addon code.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const lua = require('luaparse');

function dataTable(file) {
  const ast = lua.parse(fs.readFileSync(file, 'latin1'), { encodingMode: 'pseudo-latin1' });
  const assignment = ast.body.filter(node => node.type === 'AssignmentStatement'
    && node.init[0]?.type === 'TableConstructorExpression').at(-1);
  if (!assignment) throw new Error(`Missing data table: ${file}`);
  function decode(node) {
    if (node.type === 'TableConstructorExpression') {
      let arrayIndex = 0;
      return Object.fromEntries(node.fields.map(field =>
        [field.key?.name ?? field.key?.value ?? ++arrayIndex, decode(field.value)]));
    }
    // luaparse sees byte strings in pseudo-latin1 mode; recover UTF-8 text.
    if (typeof node.value === 'string') return Buffer.from(node.value, 'latin1').toString('utf8');
    if (['NumericLiteral', 'BooleanLiteral', 'NilLiteral'].includes(node.type)) return node.value;
    if (node.type === 'UnaryExpression' && node.operator === '-' && node.argument.type === 'NumericLiteral') {
      return -node.argument.value;
    }
    throw Error(`Unsupported Lua data expression: ${node.type} in ${file}`);
  }
  return decode(assignment.init[0]);
}

function luaString(value) {
  return '"' + value.replace(/[\\"\x00-\x1f\x7f]/g, ch => {
    if (ch === '\\' || ch === '"') return '\\' + ch;
    return '\\' + ch.charCodeAt(0).toString().padStart(3, '0');
  }) + '"';
}

function subtitleText(entry) {
  const variants = entry.g ? [['male', 'm'], ['female', 'f']] : [['common', 'x']];
  const fields = [];
  for (const [name, key] of variants) {
    const cues = entry.c?.[key];
    if (!cues) continue;
    const lines = Object.values(cues).map(cue => Array.isArray(cue) ? cue[1] : cue[2]);
    // Missing/broken cues must not produce a misleading partial transcript.
    if (!lines.length || lines.some(line => typeof line !== 'string' || !line.trim())) continue;
    fields.push(`${name} = ${luaString(lines.map(line => line.trim()).join(' '))}`);
  }
  return fields.length ? { record: `{ ${fields.join(', ')} }`, variants: fields.length } : null;
}

// The pack stores the longer duration for gender variants. Read each actual
// Vorbis stream so both variants stop at their own end, without cutting speech.
function duration(buffer) {
  let offset = 0, rate, serial, granule = 0n, ended = false;
  while (offset < buffer.length) {
    if (offset + 27 > buffer.length || buffer.toString('ascii', offset, offset + 4) !== 'OggS'
        || buffer[offset + 4] !== 0) throw new Error('Invalid OGG page');
    const count = buffer[offset + 26];
    const packet = offset + 27 + count;
    if (packet > buffer.length) throw new Error('Truncated OGG header');
    let size = 0;
    for (let i = offset + 27; i < packet; i++) size += buffer[i];
    if (packet + size > buffer.length) throw new Error('Truncated OGG data');
    const currentSerial = buffer.readUInt32LE(offset + 14);
    if (serial === undefined) {
      serial = currentSerial;
      if (size < 16 || buffer[packet] !== 1
          || buffer.toString('ascii', packet + 1, packet + 7) !== 'vorbis') {
        throw new Error('Expected a Vorbis identification packet');
      }
      rate = buffer.readUInt32LE(packet + 12);
    } else if (serial !== currentSerial) throw new Error('Chained OGG streams are unsupported');
    const position = buffer.readBigUInt64LE(offset + 6);
    if (position !== 0xffffffffffffffffn) granule = position;
    ended = (buffer[offset + 5] & 4) !== 0;
    offset = packet + size;
  }
  if (!ended || !rate || granule <= 0n) throw new Error('Incomplete OGG stream');
  return Number((Number(granule) / rate).toFixed(6));
}

function importPack(source, root = path.resolve(__dirname, '..')) {
  source = path.resolve(source);
  const version = fs.readFileSync(path.join(source, 'CatQuest_Voices.toc'), 'utf8')
    .match(/^##\s*Version:\s*(\S+)/m)?.[1];
  if (!version) throw new Error('Missing CatQuest_Voices version');
  const pack = dataTable(path.join(source, 'Index.lua'));
  // CatQuest 0.2.0, 0.2.2 and 0.3.0 omit quests without descriptions from the Lua index.
  // Recover only JSON-only turn-ins; never override loaded Lua entries or import
  // unreferenced files just because they happen to be in the sound directory.
  const jsonPath = path.join(source, 'index.json');
  const recoveredTurnIns = [];
  if (fs.existsSync(jsonPath)) {
    const json = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
    for (const [id, entry] of Object.entries(json)) {
      if (/^\d+$/.test(id) && !pack[id] && entry && entry.d == null
          && Number.isFinite(entry.t?.d) && entry.t.d > 0) {
        pack[id] = { t: entry.t };
        recoveredTurnIns.push(id);
      }
    }
  }
  const allIDs = Object.keys(pack).filter(id => /^\d+$/.test(id)).sort((a, b) => Number(a) - Number(b));
  const textQuests = new Set();
  const textStats = { quests: 0, sections: { a: 0, c: 0 }, variants: 0 };
  // Text coverage is independent of audio selection and has no Classic exclusion.
  for (const id of allIDs) {
    for (const [section, entry] of [['a', pack[id]], ['c', pack[id].t]]) {
      const text = entry && subtitleText(entry);
      if (!text) continue;
      textQuests.add(id);
      textStats.sections[section]++;
      textStats.variants += text.variants;
    }
  }
  textStats.quests = textQuests.size;
  const selected = allIDs;
  const files = [], external = [], sections = { a: 0, c: 0 };
  function audio(file) {
    const buffer = fs.readFileSync(path.join(source, 'Sounds', 'q', file));
    const seconds = duration(buffer);
    files.push({ file, bytes: buffer.length, duration: seconds,
      sha256: crypto.createHash('sha256').update(buffer).digest('hex') });
    return `{ file = "${file}", duration = ${seconds} }`;
  }
  for (const id of selected) {
    for (const [section, entry, stem] of [['a', pack[id], id], ['c', pack[id].t, id + '_t']]) {
      if (!entry || (section === 'a' && entry.d == null)) continue;
      if (!Number.isFinite(entry.d) || entry.d <= 0) throw new Error(`Invalid duration: ${id}${section}`);
      const record = entry.g
        ? `{ male = ${audio(stem + '_m.ogg')}, female = ${audio(stem + '_f.ogg')} }`
        : audio(stem + '.ogg');
      external.push(`    ["${id}${section}"] = { indexDuration = ${entry.d}, gender = ${!!entry.g},`
        + ` voice = ${JSON.stringify(entry.v || '')}, jsonOnly = ${recoveredTurnIns.includes(id)}, audio = ${record} },`);
      sections[section]++;
    }
  }
  if (!files.length) throw new Error('No new Forever audio found');

  // Validate all source streams before replacing metadata. No audio pack is generated.
  // Always rebuild from all sibling libraries so a CatQuest refresh cannot erase
  // Wayfarer transcripts from the independent database.
  require('./import-quest-texts').importTexts(path.dirname(source), root, {catquest:source});
  fs.writeFileSync(path.join(root, 'src', 'CatQuestAudio.lua'),
    '-- Generated compatibility metadata; transcripts are in QuestTexts.lua.\n'
    + `WowVoiceCatQuestAudio = { schemaVersion = 1, sourceVersion = ${JSON.stringify(version)}, entries = {\n`
    + external.join('\n') + '\n} }\n');
  const manifest = {
    source: 'CatQuest_Voices', author: 'Cathey (daniilcathey)',
    authorUrl: 'https://t.me/catheyco', version,
    selection: 'Complete loaded Lua index plus JSON-only turn-ins without descriptions; includes WowVoice overlaps',
    jsonOnlyTurnIns: recoveredTurnIns.sort((a, b) => Number(a) - Number(b)),
    quests: selected.length, sections, texts: textStats,
    files,
  };
  fs.mkdirSync(path.join(root, 'docs', 'internal'), { recursive: true });
  fs.writeFileSync(path.join(root, 'docs', 'internal', 'forever-audio-manifest.json'),
    JSON.stringify(manifest, null, 2) + '\n');
  return manifest;
}

module.exports = { importPack, dataTable, subtitleText, duration, luaString };
if (require.main === module) {
  if (!process.argv[2]) throw new Error('Usage: node tools/import-forever-audio.js <CatQuest_Voices directory>');
  const manifest = importPack(process.argv[2]);
  console.log(`Indexed external CatQuest ${manifest.version}: ${manifest.quests} quests, ${manifest.files.length} OGG files, `
    + `${manifest.files.reduce((sum, f) => sum + f.bytes, 0)} bytes; sections: ${JSON.stringify(manifest.sections)}`);
  console.log(`Texts: ${manifest.texts.quests} quests; sections: ${JSON.stringify(manifest.texts.sections)}; ${manifest.texts.variants} variants`);
}

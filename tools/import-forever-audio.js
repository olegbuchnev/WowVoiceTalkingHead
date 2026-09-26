// Import only quests absent from WowVoice's Classic pack.
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
      return Object.fromEntries(node.fields.map(field =>
        [field.key?.name ?? field.key?.value, decode(field.value)]));
    }
    return node.value;
  }
  return decode(assignment.init[0]);
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
  const version = fs.readFileSync(path.join(source, 'CatQuest_Voices.toc'), 'utf8')
    .match(/^##\s*Version:\s*(\S+)/m)?.[1];
  if (!version) throw new Error('Missing CatQuest_Voices version');
  const pack = dataTable(path.join(source, 'Index.lua'));
  // CatQuest 0.2.0 omits quests without descriptions from its Lua index.
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
  const classic = dataTable(path.join(root, 'src', 'Durations.lua'));
  const originalQuests = new Set(Object.keys(classic).map(key => key.replace(/[apc]$/, '')));
  const selected = Object.keys(pack).filter(id => /^\d+$/.test(id)
    && !originalQuests.has(id)).sort((a, b) => Number(a) - Number(b));
  const files = [], records = [], sections = { a: 0, c: 0 };
  function audio(file) {
    const buffer = fs.readFileSync(path.join(source, 'Sounds', 'q', file));
    const seconds = duration(buffer);
    files.push({ file, buffer, duration: seconds,
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
      records.push(`    ["${id}${section}"] = ${record},`);
      sections[section]++;
    }
  }
  if (!files.length) throw new Error('No new Forever audio found');

  // All source streams have been validated before modifying the output.
  const destination = path.join(root, 'catvoices');
  fs.mkdirSync(destination, { recursive: true });
  for (const file of files) fs.writeFileSync(path.join(destination, file.file), file.buffer);
  const wanted = new Set(files.map(file => file.file));
  for (const name of fs.readdirSync(destination)) {
    if (/^\d+(?:_t)?(?:_[mf])?\.ogg$/.test(name) && !wanted.has(name)) {
      fs.unlinkSync(path.join(destination, name));
    }
  }
  fs.writeFileSync(path.join(root, 'src', 'ForeverAudio.lua'),
    '-- Generated by tools/import-forever-audio.js from CatQuest_Voices.\n'
    + '-- Quests absent from Classic only; Classic recordings always take priority.\n'
    + 'WowVoiceForeverAudio = {\n' + records.join('\n') + '\n}\n');
  const manifest = {
    source: 'CatQuest_Voices', author: 'Cathey (daniilcathey)',
    authorUrl: 'https://t.me/catheyco', version,
    selection: 'Loaded Lua index plus JSON-only turn-ins without descriptions; entire quest absent from WowVoiceDur (all sections)',
    jsonOnlyTurnIns: recoveredTurnIns.filter(id => !originalQuests.has(id)).sort((a, b) => Number(a) - Number(b)),
    quests: selected.length, sections,
    files: files.map(({ buffer, ...file }) => ({ ...file, bytes: buffer.length })),
  };
  fs.mkdirSync(path.join(root, 'docs', 'internal'), { recursive: true });
  fs.writeFileSync(path.join(root, 'docs', 'internal', 'forever-audio-manifest.json'),
    JSON.stringify(manifest, null, 2) + '\n');
  return manifest;
}

module.exports = { importPack };
if (require.main === module) {
  if (!process.argv[2]) throw new Error('Usage: node tools/import-forever-audio.js <CatQuest_Voices directory>');
  const manifest = importPack(process.argv[2]);
  console.log(`Imported CatQuest ${manifest.version}: ${manifest.quests} quests, ${manifest.files.length} OGG files, `
    + `${manifest.files.reduce((sum, f) => sum + f.bytes, 0)} bytes; sections: ${JSON.stringify(manifest.sections)}`);
}

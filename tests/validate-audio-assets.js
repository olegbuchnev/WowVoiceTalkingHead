const fs = require('fs'), path = require('path'), assert = require('assert');
const crypto = require('crypto'), lua = require('luaparse');
const root = path.resolve(__dirname, '..');
for (const name of fs.readdirSync(path.join(root, 'src')).filter(name => name.endsWith('.toc'))) {
  const toc = fs.readFileSync(path.join(root, 'src', name), 'utf8');
  assert(!/^##\s*(?:Dependencies|RequiredDeps):/mi.test(toc), `${name} must load without audio packs`);
  assert.match(toc, /^## OptionalDeps: WowVoice, WowVoiceSounds, CatQuest_Voices\s*$/m,
    'Upstream takeover and sound libraries may only set optional loading order');
  assert.deepStrictEqual(toc.split(/\r?\n/).filter(line => line.endsWith('.lua')).slice(0, 2), ['LegacyAddonBlocker.lua', 'WowVoiceIntegration.lua'],
    'Detach upstream before replacing its globals');
}
const { duration } = require('../tools/import-forever-audio');
const { check } = require('../tools/generate-classic-metadata');
const classicManifest = check(path.join(root, 'soundpack'), root);
console.log(`PASS: ${classicManifest.files.length} Classic OGG durations, sizes and SHA-256 match generated metadata`);
const silence = fs.readFileSync(path.join(root, 'src/Media/silence.ogg'));
assert.strictEqual(duration(silence), 0.1, 'Music stop requires the bundled 100 ms Vorbis service asset');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'docs/internal/forever-audio-manifest.json'), 'utf8'));
const index = lua.parse(fs.readFileSync(path.join(root, 'src/CatQuestAudio.lua'), 'utf8'),
  {encodingMode:'pseudo-latin1'}).body.find(n => n.type === 'AssignmentStatement').init[0].fields.find(f => f.key.name === 'entries').value;
const classic = new Set([...fs.readFileSync(path.join(root, 'src/Durations.lua'), 'utf8')
  .matchAll(/\["(\d+[apc])"\]/g)].map(m => m[1]));
const quests = new Set([...classic].map(k => k.slice(0, -1)));
const expected = new Map(manifest.files.map(f => [f.file, f]));
const indexed = new Set(), newQuests = new Set();
const sections = { a: 0, c: 0 };
function record(table) {
  const obj = Object.fromEntries(table.fields.map(f => [f.key.name, f.value]));
  if (obj.male) { record(obj.male); record(obj.female); return; }
  const file = obj.file.value, duration = obj.duration.value;
  assert(/^[0-9]+(?:_t)?(?:_[mf])?\.ogg$/.test(file));
  assert(!indexed.has(file), `Duplicate supplemental file: ${file}`);
  indexed.add(file);
  assert(duration > 0 && duration === expected.get(file)?.duration, `Bad duration: ${file}`);
}
for (const field of index.fields) {
  const key = field.key.value, id = key.slice(0, -1);
  assert(/^\d+[ac]$/.test(key));
  newQuests.add(id);
  sections[key.slice(-1)]++;
  record(field.value.fields.find(f => f.key.name === 'audio').value);
}
assert.strictEqual(newQuests.size, manifest.quests);
assert.deepStrictEqual(sections, manifest.sections);
assert.deepStrictEqual([...indexed].sort(), [...expected.keys()].sort());
assert.deepStrictEqual(fs.readdirSync(path.join(root, 'soundpack')).filter(f => f.endsWith('.ogg')).sort(),
  [...classic].map(k => k + '.ogg').sort());
for (const key of classic) {
  const buffer = fs.readFileSync(path.join(root, 'soundpack', key + '.ogg'));
  assert.strictEqual(buffer.toString('ascii', 0, 4), 'OggS');
}
assert([...newQuests].some(id => quests.has(id)), 'External index must include shared quests');
console.log(`PASS: ${classic.size} Classic files; ${indexed.size} external audio references for ${newQuests.size} quests, verified metadata coverage and durations`);

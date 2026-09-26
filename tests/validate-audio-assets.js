const fs = require('fs'), path = require('path'), assert = require('assert');
const crypto = require('crypto'), lua = require('luaparse');
const root = path.resolve(__dirname, '..');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'docs/internal/forever-audio-manifest.json'), 'utf8'));
const index = lua.parse(fs.readFileSync(path.join(root, 'src/ForeverAudio.lua'), 'utf8'),
  {encodingMode:'pseudo-latin1'}).body.find(n => n.type === 'AssignmentStatement').init[0];
const classic = new Set([...fs.readFileSync(path.join(root, 'src/Durations.lua'), 'utf8')
  .matchAll(/\["(\d+[apc])"\]/g)].map(m => m[1]));
const quests = new Set([...classic].map(k => k.slice(0, -1)));
const expected = new Map(manifest.files.map(f => [f.file, f]));
const indexed = new Set(), newQuests = new Set();
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
  assert(!quests.has(id), `Classic quest duplicated in supplement: ${id}`);
  newQuests.add(id);
  record(field.value);
}
assert.strictEqual(newQuests.size, manifest.quests);
assert.deepStrictEqual([...indexed].sort(), [...expected.keys()].sort());
assert.deepStrictEqual(fs.readdirSync(path.join(root, 'catvoices')).filter(f => f.endsWith('.ogg')).sort(),
  [...indexed].sort());
for (const file of manifest.files) {
  const buffer = fs.readFileSync(path.join(root, 'catvoices', file.file));
  assert.strictEqual(buffer.length, file.bytes);
  assert.strictEqual(buffer.toString('ascii', 0, 4), 'OggS');
  assert.strictEqual(crypto.createHash('sha256').update(buffer).digest('hex'), file.sha256,
    `Changed recording: ${file.file}`);
}
assert.deepStrictEqual(fs.readdirSync(path.join(root, 'soundpack')).filter(f => f.endsWith('.ogg')).sort(),
  [...classic].map(k => k + '.ogg').sort());
for (const key of classic) {
  const buffer = fs.readFileSync(path.join(root, 'soundpack', key + '.ogg'));
  assert.strictEqual(buffer.toString('ascii', 0, 4), 'OggS');
}
console.log(`PASS: ${classic.size} Classic files; ${indexed.size} supplemental files for ${newQuests.size} disjoint quests, verified SHA-256 and durations`);

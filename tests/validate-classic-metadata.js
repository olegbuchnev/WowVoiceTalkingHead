const assert = require('assert/strict');
const fs = require('fs'), path = require('path'), os = require('os');
const { generate, check } = require('../tools/generate-classic-metadata');
const { dataTable } = require('../tools/import-forever-audio');
const project = path.resolve(__dirname, '..');
const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'wowvoice-classic-metadata-'));
try {
  const root = path.join(fixture, 'repo'), source = path.join(fixture, 'external');
  fs.mkdirSync(path.join(root, 'src/Media'), { recursive: true });
  fs.mkdirSync(source);
  const silence = fs.readFileSync(path.join(project, 'src/Media/silence.ogg'));
  fs.writeFileSync(path.join(root, 'src/Media/silence.ogg'), silence);
  const player = path.join(fixture, 'WowVoice');
  fs.mkdirSync(player);
  fs.writeFileSync(path.join(player, 'WowVoice.toc'), '## Version: 1.1.0\n');
  const upstreamIndex = path.join(player, 'Durations.lua');
  const upstreamText = 'WowVoiceDur = {["1a"]=50,["1p"]=20,["2c"]=30}';
  fs.writeFileSync(upstreamIndex, upstreamText);
  fs.writeFileSync(path.join(source, 'WowVoiceSounds.toc'), '## Version: 0.1.0\n');
  fs.writeFileSync(path.join(source, 'WowVoiceSounds_Camelot.toc'), '## Version: 0.1.1\n');
  const index = path.join(root, 'src/Index.lua');
  fs.writeFileSync(index, 'WowVoiceIndex = { ["Old quest"]={{q=999,a=50}} }');
  const files = ['1a.ogg', '1p.ogg', '2c.ogg'];
  for (const name of files) fs.writeFileSync(path.join(source, name), silence);
  // The official pack's stop sound is independent of our own service sound.
  fs.writeFileSync(path.join(source, 'silence.ogg'), 'upstream service asset, not a quest recording');
  const sourceBefore = fs.readdirSync(source).map(name => [name, fs.readFileSync(path.join(source, name))]);
  const output = path.join(root, 'src/Durations.lua');
  // Deliberately stale timer keys must not select which files are measured.
  fs.writeFileSync(output, 'WowVoiceDur = {["999a"]=99}');
  const manifest = generate(source, root);
  assert.equal(manifest.version, '0.1.1');
  assert.equal(manifest.sourceToc, 'WowVoiceSounds_Camelot.toc');
  assert.equal(manifest.index.version, '1.1.0');
  assert.equal(manifest.quests, 2);
  assert.deepEqual(manifest.sections, { a: 1, p: 1, c: 1 });
  assert.deepEqual(manifest.files.map(entry => entry.file), files);
  assert.deepEqual(dataTable(output), { '1a': 0.1, '1p': 0.1, '2c': 0.1, silence: 0.1 });
  assert.deepEqual(check(source, root), manifest);
  assert(!fs.existsSync(path.join(root, 'soundpack')), 'Metadata generation must not copy recordings');
  const saved = fs.readFileSync(output);
  const manifestFile = path.join(root, 'docs/internal/classic-audio-manifest.json');
  const savedManifest = fs.readFileSync(manifestFile);
  generate(source, root);
  assert.deepEqual(fs.readFileSync(output), saved);
  assert.deepEqual(fs.readFileSync(manifestFile), savedManifest, 'Generation must be reproducible');
  assert.deepEqual(fs.readdirSync(source).map(name => [name, fs.readFileSync(path.join(source, name))]), sourceBefore);

  fs.writeFileSync(output, saved.toString().replace('["1a"]=0.1', '["1a"]=9.9'));
  assert.throws(() => check(source, root), /Durations.lua differs/);
  fs.writeFileSync(output, saved);

  // A same-length valid stream with a different serial retains duration/version.
  // Every page serial and CRC is updated, so this also works with a stricter OGG parser.
  const changed = Buffer.from(silence);
  for (let offset = 0; offset < changed.length;) {
    const packet = offset + 27 + changed[offset + 26];
    let end = packet;
    for (let i = offset + 27; i < packet; i++) end += changed[i];
    changed.writeUInt32LE(12345, offset + 14);
    changed.writeUInt32LE(0, offset + 22);
    let crc = 0;
    for (let i = offset; i < end; i++) {
      crc ^= changed[i] << 24;
      for (let bit = 0; bit < 8; bit++) crc = (crc << 1) ^ (crc < 0 ? 0x04c11db7 : 0);
    }
    changed.writeUInt32LE(crc >>> 0, offset + 22);
    offset = end;
  }
  const recording = path.join(source, '1a.ogg');
  fs.writeFileSync(recording, changed);
  assert.throws(() => check(source, root), /measurement\/hash mismatch: 1a.ogg/);
  assert.deepEqual(fs.readFileSync(output), saved, 'Read-only check rewrote metadata');
  generate(source, root);
  assert.notEqual(check(source, root).files[0].sha256, manifest.files[0].sha256);
  fs.writeFileSync(recording, silence);
  generate(source, root);

  function rejected(action, pattern) {
    assert.throws(action, pattern);
    assert.deepEqual(fs.readFileSync(output), saved, 'Invalid input replaced durations');
    assert.deepEqual(fs.readFileSync(manifestFile), savedManifest, 'Invalid input replaced manifest');
  }
  fs.unlinkSync(recording);
  rejected(() => generate(source, root), /coverage mismatch: missing 1/);
  fs.writeFileSync(recording, silence.subarray(0, silence.length - 1));
  rejected(() => generate(source, root), /Invalid Classic OGG 1a.ogg/);
  fs.writeFileSync(recording, Buffer.from('not an OGG'));
  rejected(() => generate(source, root), /Invalid Classic OGG/);
  fs.writeFileSync(recording, silence);
  const extra = path.join(source, '3a.ogg');
  fs.writeFileSync(extra, silence);
  rejected(() => generate(source, root), /unexpected 1/);
  fs.unlinkSync(extra);
  fs.writeFileSync(path.join(source, 'WowVoiceSounds_Camelot.toc'), '## Version: 0.1.2\n');
  rejected(() => check(source, root), /manifest\/pack metadata mismatch/);
  fs.writeFileSync(path.join(source, 'WowVoiceSounds_Camelot.toc'), '## Version: 0.1.1\n');
  for (const invalid of ['["1a"]=-1','["0a"]=1','["01a"]=1','["1x"]=1','["1a"]=os.execute("bad")']) {
    fs.writeFileSync(upstreamIndex, `WowVoiceDur = {${invalid}}`);
    rejected(() => generate(source, root), /Invalid WowVoice|Unsupported Lua data expression/);
  }
  fs.writeFileSync(upstreamIndex, 'WowVoiceDur = {}');
  rejected(() => generate(source, root), /Empty WowVoice/);
  fs.unlinkSync(upstreamIndex);
  rejected(() => generate(source, root), /ENOENT/);
  // A complete replacement at the same pack version removes old keys, accepts
  // new quest IDs absent from the title index, and retains only hash history.
  fs.writeFileSync(upstreamIndex, 'WowVoiceDur = {["3a"]=5,["2c"]=30}');
  fs.unlinkSync(path.join(source, '1a.ogg'));
  fs.unlinkSync(path.join(source, '1p.ogg'));
  fs.writeFileSync(extra, silence);
  const updated = generate(source, root);
  assert.deepEqual(updated.files.map(f => f.file), ['2c.ogg','3a.ogg']);
  assert.deepEqual(dataTable(output), {'2c':0.1,'3a':0.1,silence:0.1});
  assert.deepEqual(check(source, root), updated);
  assert.equal(fs.readFileSync(upstreamIndex,'utf8'), 'WowVoiceDur = {["3a"]=5,["2c"]=30}');
  console.log('PASS: current WowVoice coverage, measured timing, no legacy fallback, replacements at the same version, reproducibility and validation before writes');
} finally {
  assert(path.dirname(fixture) === os.tmpdir() && path.basename(fixture).startsWith('wowvoice-classic-metadata-'));
  fs.rmSync(fixture, { recursive: true, force: true });
}

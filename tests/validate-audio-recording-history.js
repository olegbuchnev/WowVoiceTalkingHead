const assert = require('assert/strict');
const fs = require('fs'), path = require('path'), os = require('os');
const { update, resolve, render, validate, recordSnapshots, snapshotsFromManifests, historyPath } = require('../tools/audio-recording-history');
const pack = 'CatQuest_Voices', file = '1479_m.ogg';
const sha = n => n.toString(16).padStart(64, '0');
const snapshot = (version, n, files) => ({ pack, version,
  files: files || [{ file, sha256: sha(n), bytes: 100, duration: 20 }] });
let history = update(null, [snapshot('0.6.0', 1)]);
assert.deepEqual(history.packs[pack].recordings[file].playerVariant, 'male');
assert.equal(resolve(history, pack, '0.6.0', file).sha256, sha(1));
assert.equal(resolve(history, pack, '0.6.1', file).status, 'unknown-release');
assert.equal(render(update(history, [snapshot('0.6.0', 1)])), render(history), 'Repeated imports must be idempotent');
history = update(history, [snapshot('0.6.1', 1)]);
assert.equal(history.packs[pack].recordings[file].revisions.length, 1, 'An unchanged file must retain its identity across pack updates');
history = update(history, [snapshot('0.7.0', 2)]);
assert.equal(resolve(history, pack, '0.6.0', file).sha256, sha(1));
assert.equal(resolve(history, pack, '0.7.0', file).sha256, sha(2), 'Same size and duration must not hide a replacement');
history = update(history, [snapshot('0.8.0', 3), snapshot('0.9.0', 4)]);
assert.equal(resolve(history, pack, '0.6.1', file).status, 'outside-history-window');
assert.equal(resolve(history, pack, '0.7.0', file).status, 'known');
assert.equal(history.packs[pack].recordings[file].revisions.length, 4, 'Archive must retain revisions outside the supported window');
history = update(history, [snapshot('1.0.0', 1)]);
assert.equal(resolve(history, pack, '0.6.0', file).status, 'known', 'Restoring old bytes reuses their identity');
assert.equal(history.packs[pack].recordings[file].revisions.length, 4);
const count = history.packs[pack].releases.length;
history = update(history, [snapshot('0.6.0', 1)]);
assert.equal(history.packs[pack].releases.length, count, 'Reimporting an audited older pack must not append a snapshot');
assert.equal(resolve(history, pack, '0.7.0', file).status, 'outside-history-window', 'A downgrade must not reorder the audit history');
history = update(history, [snapshot('1.1.0', 5), snapshot('1.1.0', 6)]);
assert.equal(resolve(history, pack, '1.1.0', file).status, 'ambiguous-release', 'Two different packs with one TOC version must not inherit a rating');
history = update(history, [snapshot('1.2.0', 7, [{file:'1479_t_f.ogg', sha256:sha(7), bytes:200, duration:30}])]);
assert.equal(resolve(history, pack, '1.2.0', file).status, 'absent', 'Removed audio must not leak from history into availability');
assert.equal(history.packs[pack].recordings['1479_t_f.ogg'].section, 'c');
assert.equal(history.packs[pack].recordings['1479_t_f.ogg'].playerVariant, 'female');
assert.throws(() => update(history, [snapshot('1.3.0', 1, [
  {file, sha256:sha(1), bytes:999, duration:20},
])]), /Conflicting metadata/);
assert.throws(() => update(history, [snapshot('1.3.0', 1, [
  {file:'../bad.ogg', sha256:sha(1), bytes:100, duration:20},
])]), /Unsupported recording/);
const corrupt = structuredClone(history);
corrupt.packs[pack].recordings[file].revisions[0].releases = [9999];
assert.throws(() => validate(corrupt), /Invalid release mapping/);
const duplicate = snapshot('1.3.0', 1);
duplicate.files.push(duplicate.files[0]);
assert.throws(() => update(history, [duplicate]), /Duplicate recording/);

const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'wowvoice-audio-history-'));
try {
  recordSnapshots([snapshot('0.6.0', 1)], fixture);
  const output = path.join(fixture, historyPath), before = fs.readFileSync(output);
  recordSnapshots([snapshot('0.6.0', 1)], fixture, true);
  assert.throws(() => recordSnapshots([snapshot('0.7.0', 2)], fixture, true), /history is stale/);
  assert.deepEqual(fs.readFileSync(output), before, 'Read-only check must not update history');
  assert.throws(() => recordSnapshots([duplicate], fixture), /Duplicate recording/);
  assert.deepEqual(fs.readFileSync(output), before, 'Invalid input must not replace history');
} finally {
  assert(path.dirname(fixture) === os.tmpdir() && path.basename(fixture).startsWith('wowvoice-audio-history-'));
  fs.rmSync(fixture, {recursive:true, force:true});
}
const root = path.resolve(__dirname, '..');
const saved = recordSnapshots(snapshotsFromManifests(root), root, true);
for (const input of snapshotsFromManifests(root)) {
  const files = Array.isArray(input.files) ? input.files : Object.entries(input.files).map(([file, data]) => ({file, ...data}));
  for (const entry of files) {
    assert(saved.packs[input.pack].recordings[entry.file], 'Every measured recording needs a history');
  }
}
console.log('PASS: audio history baseline, file hashes, per-file revision window, rollback, removals, same-version ambiguity, validation and read-only manifest checks');

// Versioned metadata only: never copies audio or treats a TOC version as a file hash.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const project = path.resolve(__dirname, '..');
const historyPath = 'docs/internal/audio-recording-history.json';
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const shaPattern = /^[a-f0-9]{64}$/;

function identity(pack, file) {
  let match;
  if (pack === 'WowVoiceSounds') {
    match = /^([1-9]\d*)([apc])\.ogg$/.exec(file);
    if (match) return { questID: Number(match[1]), section: match[2], playerVariant: 'common' };
  } else if (pack === 'CatQuest_Voices') {
    match = /^([1-9]\d*)(_t)?(?:_([mf]))?\.ogg$/.exec(file);
    if (match) return { questID: Number(match[1]), section: match[2] ? 'c' : 'a',
      playerVariant: match[3] === 'm' ? 'male' : match[3] === 'f' ? 'female' : 'common' };
  } else if (/^Wayfarer_Voices_(Alliance|Horde|Shared|Narrator)$/.test(pack)) {
    match = /^q\/([1-9]\d*)-([apc])(?:-([mf]))?\.ogg$/.exec(file);
    if (match) return { questID: Number(match[1]), section: match[2],
      playerVariant: match[3] === 'm' ? 'male' : match[3] === 'f' ? 'female' : 'common' };
  }
  throw Error(`Unsupported recording: ${pack}/${file}`);
}

function normalize(snapshot) {
  const { pack, version } = snapshot;
  if (typeof version !== 'string' || !version.trim()) throw Error(`Missing version: ${pack}`);
  const files = Array.isArray(snapshot.files) ? snapshot.files
    : Object.entries(snapshot.files || {}).map(([file, data]) => ({ file, ...data }));
  if (!files.length) throw Error(`Empty audio snapshot: ${pack}`);
  const seen = new Set();
  const normalized = files.map(({ file, sha256, bytes, duration }) => {
    identity(pack, file);
    if (seen.has(file)) throw Error(`Duplicate recording: ${pack}/${file}`);
    seen.add(file);
    if (!shaPattern.test(sha256) || !Number.isSafeInteger(bytes) || bytes <= 0
        || !Number.isFinite(duration) || duration <= 0) throw Error(`Invalid audio metadata: ${pack}/${file}`);
    return { file, sha256, bytes, duration };
  }).sort((a, b) => a.file < b.file ? -1 : a.file > b.file ? 1 : 0);
  return { pack, version, files: normalized };
}

function snapshotHash(version, files) {
  return hash(JSON.stringify([version, files.map(f => [f.file, f.sha256])]));
}

function validate(history) {
  if (history.schemaVersion !== 1 || history.identity !== 'file-sha256'
      || history.supportedRevisionsPerFile !== 3 || !history.packs || Array.isArray(history.packs)) {
    throw Error('Unsupported audio recording history');
  }
  for (const [pack, data] of Object.entries(history.packs)) {
    if (!Array.isArray(data.releases) || !data.releases.length || !data.recordings
        || !Number.isInteger(data.currentRelease) || !data.releases[data.currentRelease - 1]) {
      throw Error(`Invalid history pack: ${pack}`);
    }
    const snapshots = data.releases.map(release => {
      if (!release.version || !shaPattern.test(release.snapshotSha256)) throw Error(`Invalid release: ${pack}`);
      return [];
    });
    for (const [file, recording] of Object.entries(data.recordings)) {
      const expected = identity(pack, file);
      if (Object.entries(expected).some(([key, value]) => recording[key] !== value)
          || !Array.isArray(recording.revisions) || !recording.revisions.length) throw Error(`Invalid recording history: ${file}`);
      const hashes = new Set(), releases = new Set();
      for (const revision of recording.revisions) {
        normalize({ pack, version: 'validation', files: [{ file, ...revision }] });
        if (hashes.has(revision.sha256) || !Array.isArray(revision.releases) || !revision.releases.length) {
          throw Error(`Duplicate or unassigned revision: ${file}`);
        }
        hashes.add(revision.sha256);
        for (const index of revision.releases) {
          if (!Number.isInteger(index) || !snapshots[index - 1] || releases.has(index)) throw Error(`Invalid release mapping: ${file}`);
          releases.add(index);
          snapshots[index - 1].push({ file, sha256: revision.sha256 });
        }
      }
    }
    const fingerprints = new Set();
    snapshots.forEach((files, index) => {
      files.sort((a, b) => a.file < b.file ? -1 : a.file > b.file ? 1 : 0);
      const release = data.releases[index];
      if (!files.length || snapshotHash(release.version, files) !== release.snapshotSha256
          || fingerprints.has(release.snapshotSha256)) throw Error(`Corrupt release snapshot: ${pack}/${release.version}`);
      fingerprints.add(release.snapshotSha256);
    });
  }
  return history;
}

function update(history, inputs) {
  const result = history ? structuredClone(validate(history))
    : { schemaVersion: 1, identity: 'file-sha256', supportedRevisionsPerFile: 3, packs: {} };
  for (const input of inputs) {
    const { pack, version, files } = normalize(input);
    const data = result.packs[pack] ||= { currentRelease: 1, releases: [], recordings: {} };
    const fingerprint = snapshotHash(version, files);
    const existing = data.releases.findIndex(r => r.snapshotSha256 === fingerprint);
    const release = existing < 0 ? data.releases.length + 1 : existing + 1;
    if (existing < 0) data.releases.push({ version, snapshotSha256: fingerprint });
    data.currentRelease = release;
    for (const { file, sha256, bytes, duration } of files) {
      const recording = data.recordings[file] ||= { ...identity(pack, file), revisions: [] };
      let revision = recording.revisions.find(r => r.sha256 === sha256);
      if (!revision) {
        revision = { sha256, bytes, duration, releases: [] };
        recording.revisions.push(revision);
      }
      if (revision.bytes !== bytes || revision.duration !== duration) throw Error(`Conflicting metadata for identical SHA-256: ${pack}/${file}`);
      if (!revision.releases.includes(release)) revision.releases.push(release);
    }
  }
  return validate(result);
}

function supportedRevisions(history, pack, file) {
  return [...(history.packs[pack]?.recordings[file]?.revisions || [])]
    .sort((a, b) => Math.max(...b.releases) - Math.max(...a.releases))
    .slice(0, history.supportedRevisionsPerFile);
}

// Resolve only audited, unambiguous releases. An unknown/new TOC version cannot inherit ratings.
function resolve(history, pack, version, file) {
  const data = history.packs[pack];
  if (!data) return { status: 'unknown-release' };
  const matching = data.releases.map((r, i) => r.version === version ? i + 1 : 0).filter(Boolean);
  if (!matching.length) return { status: 'unknown-release' };
  if (matching.length !== 1) return { status: 'ambiguous-release' };
  const revisions = data.recordings[file]?.revisions || [];
  const revision = revisions.find(r => r.releases.includes(matching[0]));
  if (!revision) return { status: 'absent' };
  const supported = supportedRevisions(history, pack, file);
  if (!supported.includes(revision)) return { status: 'outside-history-window' };
  return { status: 'known', sha256: revision.sha256 };
}

// One recording per line keeps a large generated table reviewable in Git.
function render(history) {
  const lines = ['{', '  "schemaVersion": 1,', '  "identity": "file-sha256",',
    '  "supportedRevisionsPerFile": 3,', '  "packs": {'];
  const packs = Object.entries(history.packs).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0);
  packs.forEach(([pack, data], packIndex) => {
    lines.push(`    ${JSON.stringify(pack)}: {`, `      "currentRelease": ${data.currentRelease},`,
      `      "releases": ${JSON.stringify(data.releases)},`, '      "recordings": {');
    const records = Object.entries(data.recordings).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0);
    records.forEach(([file, record], i) => lines.push(`        ${JSON.stringify(file)}: ${JSON.stringify(record)}${i < records.length - 1 ? ',' : ''}`));
    lines.push('      }', `    }${packIndex < packs.length - 1 ? ',' : ''}`);
  });
  return lines.concat('  }', '}', '').join('\n');
}

function recordSnapshots(inputs, root = project, check = false) {
  const output = path.join(root, historyPath);
  const old = fs.existsSync(output) ? JSON.parse(fs.readFileSync(output, 'utf8')) : null;
  const history = update(old, inputs);
  const content = render(history);
  const previous = old && fs.readFileSync(output, 'utf8').replace(/\r\n/g, '\n');
  if (check) {
    if (previous !== content) throw Error('Audio recording history is stale; run node tools/audio-recording-history.js');
  } else if (previous !== content) {
    fs.mkdirSync(path.dirname(output), { recursive: true });
    const temporary = output + '.tmp';
    fs.writeFileSync(temporary, content);
    fs.renameSync(temporary, output);
  }
  return history;
}

function snapshotsFromManifests(root = project) {
  const read = name => JSON.parse(fs.readFileSync(path.join(root, 'docs/internal', name), 'utf8'));
  const classic = read('classic-audio-manifest.json'), catquest = read('forever-audio-manifest.json');
  const wayfarer = read('wayfarer-audio-manifest.json');
  return [
    { pack: 'WowVoiceSounds', version: classic.version, files: classic.files },
    { pack: 'CatQuest_Voices', version: catquest.version, files: catquest.files },
    ...Object.entries(wayfarer.packs).map(([pack, data]) => ({ pack, version: data.version, files: data.files })),
  ];
}

module.exports = { historyPath, identity, normalize, validate, update, resolve, supportedRevisions, render, recordSnapshots, snapshotsFromManifests };
if (require.main === module) {
  const args = process.argv.slice(2);
  if (args.length > 1 || (args.length && args[0] !== '--check')) throw Error('Usage: node tools/audio-recording-history.js [--check]');
  const history = recordSnapshots(snapshotsFromManifests(), project, args[0] === '--check');
  for (const [name, pack] of Object.entries(history.packs)) {
    const count = Object.keys(pack.recordings).length;
    const revisions = Object.values(pack.recordings).reduce((n, r) => n + r.revisions.length, 0);
    console.log(`${name}: ${pack.releases[pack.currentRelease - 1].version}, ${count} recordings, ${revisions} revisions, ${pack.releases.length} audited snapshots`);
  }
}

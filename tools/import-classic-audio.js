// Populate the release's WowVoiceSounds from a locally extracted Classic pack.
const fs = require('fs');
const path = require('path');
const { readSourceVersion, writeSourceVersion } = require('./audio-source-version');
const { check } = require('./generate-classic-metadata');
function importClassic(source, root = path.resolve(__dirname, '..')) {
  const provenance = readSourceVersion(source, ['WowVoiceSounds_Vanilla.toc', 'WowVoiceSounds.toc']);
  // Never copy changed recordings against stale timers. Regenerate metadata explicitly first.
  const names = check(source, root).files.map(entry => entry.file);
  const destination = path.join(root, 'soundpack');
  fs.mkdirSync(destination, { recursive: true });
  for (const name of names) fs.copyFileSync(path.join(source, name), path.join(destination, name));
  for (const toc of ['WowVoiceSounds.toc', 'WowVoiceSounds_Mainline.toc']) {
    writeSourceVersion(path.join(destination, toc), provenance);
  }
  return names.length;
}
module.exports = { importClassic };
if (require.main === module) {
  const source = process.argv[2];
  if (!source) throw new Error('Usage: node tools/import-classic-audio.js <WowVoiceSounds directory>');
  console.log(`Imported ${importClassic(source)} Classic recordings into soundpack.`);
}

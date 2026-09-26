// Populate the release's WowVoiceSounds from a locally extracted Classic pack.
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..');
const source = process.argv[2];
if (!source) throw new Error('Usage: node tools/import-classic-audio.js <WowVoiceSounds directory>');
const durations = fs.readFileSync(path.join(root, 'src', 'Durations.lua'), 'utf8');
const names = [...new Set([...durations.matchAll(/\["(\d+[apc])"\]/g)].map(m => m[1] + '.ogg'))];
if (!names.length) throw new Error('Empty Classic index');
for (const name of names) {
  const file = path.join(source, name);
  if (!fs.statSync(file).isFile() || fs.statSync(file).size === 0) throw new Error(`Missing Classic audio: ${name}`);
}
const destination = path.join(root, 'soundpack');
fs.mkdirSync(destination, { recursive: true });
for (const name of names) fs.copyFileSync(path.join(source, name), path.join(destination, name));
console.log(`Imported ${names.length} Classic recordings into soundpack.`);

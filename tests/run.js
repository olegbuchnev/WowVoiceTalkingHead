const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const luaparse = require('luaparse');
const root = path.resolve(__dirname, '..');
const source = path.join(root, 'src');
let parsed = 0;
for (const dir of [source, __dirname]) {
  for (const file of fs.readdirSync(dir).filter(name => name.endsWith('.lua'))) {
    luaparse.parse(fs.readFileSync(path.join(dir, file), 'utf8'), { luaVersion: '5.1' });
    parsed++;
  }
}
console.log(`Lua 5.1 syntax validated: ${parsed} files.`);
for (const runner of [
  'validate-audio-import.js',
  'validate-audio-assets.js',
  'validate-forever-speakers.js',
  'validate-full.js', 'validate-portrait.js', 'validate-player-preview.js',
  'validate-block-scroll.js', 'validate-subtitles.js', 'validate-item-speaker.js',
]) {
  const result = spawnSync(process.execPath, [path.join(__dirname, runner), source], {
    cwd: root, stdio: 'inherit',
  });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status || 1);
}

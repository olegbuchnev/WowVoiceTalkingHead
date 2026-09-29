// Original geometric UI artwork: beveled circular playback buttons.
// Neutral grayscale is tinted by the source color in LocalDebug.lua.
const fs = require('fs'), path = require('path');
const size = 128, samples = 4;
function pixel(x, y, selected) {
  const radius = Math.hypot(x - 64, y - 64);
  if (radius > 60) return [0, 0];
  const light = (64 - y) / 128;
  let value;
  if (radius > 55) value = selected ? 1 : .55 + light * .5;
  else if (radius > 51) value = selected ? .6 : .08;
  else value = selected ? .78 + light * .3 : .13 + light * .1;
  // Soft shadow beneath the raised play glyph.
  if (x >= 49 && x <= 87 - Math.abs(y - 66) * 38 / 27) value *= .4;
  if (x >= 47 && x <= 85 - Math.abs(y - 64) * 38 / 27) {
    value = selected ? .07 : .95 + light * .1;
  }
  return [Math.max(0, Math.min(1, value)), 1];
}
for (const selected of [false, true]) {
  const pixels = Buffer.alloc(size * size * 4);
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    let coverage = 0, shade = 0;
    for (let sy = 0; sy < samples; sy++) for (let sx = 0; sx < samples; sx++) {
      const [value, alpha] = pixel(x + (sx + .5) / samples, y + (sy + .5) / samples, selected);
      coverage += alpha; shade += value * alpha;
    }
    const offset = (y * size + x) * 4;
    pixels[offset] = pixels[offset + 1] = pixels[offset + 2] = coverage ? Math.round(shade * 255 / coverage) : 0;
    pixels[offset + 3] = Math.round(coverage * 255 / (samples * samples));
  }
  const header = Buffer.alloc(18);
  header[2] = 2;
  header.writeUInt16LE(size, 12); header.writeUInt16LE(size, 14);
  header[16] = 32; header[17] = 0x28;
  fs.writeFileSync(path.join(__dirname, '../src/Media/', selected ? 'PlaySelected.tga' : 'Play.tga'), Buffer.concat([header, pixels]));
}

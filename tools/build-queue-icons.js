// Original monochrome queue controls, tinted to match their labels in game.
const fs = require('fs');
const path = require('path');
const size = 32, samples = 4;
function insidePolygon(x, y, points) {
  let inside = false;
  for (let i = 0, j = points.length - 1; i < points.length; j = i++) {
    const [xi, yi] = points[i], [xj, yj] = points[j];
    if ((yi > y) !== (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}
const icons = {
  QueueNext: (x, y) => insidePolygon(x, y, [[4, 4], [24, 16], [4, 28]])
    || (x >= 26 && x <= 29 && y >= 4 && y <= 28),
  QueueCheck: (x, y) => insidePolygon(x, y, [[3, 17], [6, 14], [12, 20], [25, 5], [29, 9], [12, 27]])
};
for (const [name, covers] of Object.entries(icons)) {
  const pixels = Buffer.alloc(size * size * 4);
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    let coverage = 0;
    for (let sy = 0; sy < samples; sy++) for (let sx = 0; sx < samples; sx++) {
      if (covers(x + (sx + .5) / samples, y + (sy + .5) / samples)) coverage++;
    }
    const offset = (y * size + x) * 4;
    pixels[offset] = pixels[offset + 1] = pixels[offset + 2] = 255;
    pixels[offset + 3] = Math.round(coverage * 255 / (samples * samples));
  }
  const header = Buffer.alloc(18);
  header[2] = 2;
  header.writeUInt16LE(size, 12); header.writeUInt16LE(size, 14);
  header[16] = 32; header[17] = 0x28;
  fs.writeFileSync(path.join(__dirname, '../src/Media', `${name}.tga`), Buffer.concat([header, pixels]));
}

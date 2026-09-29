const assert = require('assert/strict');
const fs = require('fs'), os = require('os'), path = require('path');
const { parse, render } = require('../tools/import-catquest-speakers');
const { dataTable } = require('../tools/import-forever-audio');
const fixture = Buffer.from(String.raw`local ADDON, ns = ...
ns.NpcData = {
 [123] = {"dwarf", "male", 11740, "Имя \"NPC\""},
 [456] = {false, false, nil, "Другой NPC"},
}
ns.QuestGiver = {[98246] = 123}
ns.QuestFinisher = {[98246] = 456}
`);
const upstream = parse(fixture);
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'wowvoice-npc-import-'));
try {
  const file = path.join(directory, 'Speakers.lua');
  fs.writeFileSync(file, render(fixture, 'test'));
  const result = dataTable(file);
  assert.deepEqual(result.npcs, upstream.NpcData);
  assert.deepEqual(result.givers, upstream.QuestGiver);
  assert.deepEqual(result.finishers, upstream.QuestFinisher);
  assert.equal(result.npcs[123][4], 'Имя "NPC"');
  assert.equal(result.npcs[456][1], false);
  assert.equal(result.npcs[456][3], null);
  assert.equal(result.givers[98246], 123);
  assert.equal(result.finishers[98246], 456);
  assert.throws(() => parse(Buffer.from('ns.NpcData = {}')));
  assert.throws(() => parse(Buffer.from(fixture.toString().replace('11740', 'GetDisplay()'))));
  console.log('PASS: complete NPC import, Unicode/quotes, absent models, distinct giver/finisher and data-only parsing');
} finally {
  fs.unlinkSync(path.join(directory, 'Speakers.lua'));
  fs.rmdirSync(directory);
}

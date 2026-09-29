const assert = require('assert/strict');
const fs = require('fs'), path = require('path'), os = require('os');
const { importPack } = require('../tools/import-forever-audio');
const { readSourceVersion, writeSourceVersion } = require('../tools/audio-source-version');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'wowvoice-audio-import-'));
try {
  const source = path.join(fixture, 'source'), root = path.join(fixture, 'repo');
  fs.mkdirSync(path.join(source, 'Sounds/q'), { recursive: true });
  fs.mkdirSync(path.join(root, 'src'), { recursive: true });

  const adaptedToc = path.join(root, 'Example.toc');
  fs.writeFileSync(adaptedToc, '## Version: 0.2.0-wowvoice.1\n');
  // A client-specific source TOC takes precedence over stale generic metadata.
  fs.writeFileSync(path.join(source, 'WowVoiceSounds.toc'), '## Version: 0.1.0\n');
  fs.writeFileSync(path.join(source, 'WowVoiceSounds_Vanilla.toc'), '## Version: 1.0.1\n');
  const candidates = ['WowVoiceSounds_Vanilla.toc', 'WowVoiceSounds.toc'];
  assert.deepEqual(readSourceVersion(source, candidates), { toc: candidates[0], version: '1.0.1' });
  writeSourceVersion(path.join(source, candidates[0]), { toc: 'Original.toc', version: '2.0' });
  assert.deepEqual(readSourceVersion(source, candidates), { toc: 'Original.toc', version: '2.0' });
  fs.writeFileSync(path.join(root, 'src/Durations.lua'), 'WowVoiceDur = {["179p"]=2}');
  fs.writeFileSync(path.join(source, 'CatQuest_Voices.toc'), '## Version: 0.2.0\n');
  fs.writeFileSync(path.join(source, 'Index.lua'),
    'CatQuestVoicePack = {}\nCatQuestVoicePack.quests = { [490]={d=35,c={x={{0,[=[Привет, "герой".]=]},{2,[=[Строка\nс текстом.]=]}}}}, [179]={d=12,c={x={{0,"Описание Classic"}}},t={d=5,c={x={{0,"Сдача Classic"}}}}} }');
  fs.writeFileSync(path.join(source, 'index.json'), JSON.stringify({
    490: { d: 35, g: 1, t: { d: 3 } }, // Conflicts must not replace the loaded Lua entry.
    179: { t: { d: 5 } }, // Classic overlap must remain available for source selection.
    99080: { t: { d: 33, g: 1, c: {
      m: [[0, 'Спасибо, герой.'], [2, 'Путь C:\\test.']],
      f: [[0, 'Спасибо, героиня.']],
    } } }, // JSON-only completion without a description.
    99999: { d: 20, t: { d: 5 } }, // Do not broaden fallback to JSON-only descriptions.
  }));
  const sample = fs.readFileSync(path.join(__dirname, '../soundpack/179a.ogg'));
  for (const file of ['179.ogg', '179_t.ogg', '490.ogg', '99080_t_m.ogg', '99080_t_f.ogg']) {
    fs.writeFileSync(path.join(source, 'Sounds/q', file), sample);
  }
  const manifest = importPack(source, root);
  assert.match(fs.readFileSync(adaptedToc, 'utf8'), /## Version: 0\.2\.0-wowvoice\.1\n/);
  writeSourceVersion(adaptedToc, { toc: 'CatQuest_Voices.toc', version: '0.3.0' });
  assert.equal((fs.readFileSync(adaptedToc, 'utf8').match(/X-Source-Version:/g) || []).length, 1);
  assert.match(fs.readFileSync(adaptedToc, 'utf8'), /## X-Source-Version: 0\.3\.0\n/);
  assert.equal(manifest.version, '0.2.0');
  assert.equal(manifest.quests, 3);
  assert.deepEqual(manifest.sections, { a: 2, c: 2 });
  assert.deepEqual(manifest.jsonOnlyTurnIns, ['99080']);
  assert.deepEqual(manifest.texts, { quests: 3, sections: { a: 2, c: 2 }, variants: 5 });
  assert.deepEqual(manifest.files.map(f => f.file), ['179.ogg', '179_t.ogg', '490.ogg', '99080_t_m.ogg', '99080_t_f.ogg']);
  assert(manifest.files.every(f => f.duration > 0 && f.duration !== 33));
  const output = path.join(root, 'src/CatQuestAudio.lua');
  const before = fs.readFileSync(output, 'utf8');
  assert(before.includes('["99080c"]') && !before.includes('["99080a"]'));
  assert(!before.includes('["490c"]') && before.includes('["179a"]') && before.includes('["179c"]'));
  const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
  const textFile = path.join(root, 'src/CatQuestTexts.lua');
  const metadata = fs.readFileSync(textFile, 'utf8');
  assert(!fs.readFileSync(path.join(root, 'src/CatQuestAudio.lua'), 'utf8').includes('text = {'));
  function transcript(key, variant) {
    const code = metadata + `\nreturn WowVoiceCatQuestTexts.entries["${key}"].${variant}`;
    const status = lauxlib.luaL_dostring(L, to_luastring(code));
    assert.equal(status, lua.LUA_OK, to_jsstring(lua.lua_tostring(L, -1)));
    const text = to_jsstring(lua.lua_tostring(L, -1));
    lua.lua_settop(L, 0);
    return text;
  }
  assert.equal(transcript('490a', 'common'), 'Привет, "герой". Строка\nс текстом.');
  assert.equal(transcript('99080c', 'male'), 'Спасибо, герой. Путь C:\\test.');
  assert.equal(transcript('99080c', 'female'), 'Спасибо, героиня.');
  assert.equal(transcript('179a', 'common'), 'Описание Classic');
  assert.equal(transcript('179c', 'common'), 'Сдача Classic');
  lua.lua_close(L);

  // Validate every required stream before replacing any installed output.
  const last = path.join(source, 'Sounds/q/99080_t_f.ogg');
  fs.unlinkSync(last);
  assert.throws(() => importPack(source, root), /ENOENT/);
  assert.equal(fs.readFileSync(output, 'utf8'), before);
  assert.equal(fs.readFileSync(textFile, 'utf8'), metadata);
  fs.writeFileSync(last, 'broken ogg');
  assert.throws(() => importPack(source, root), /Invalid OGG/);

  // Older packs without JSON remain supported.
  fs.unlinkSync(path.join(source, 'index.json'));
  const older = importPack(source, root);
  assert.equal(older.quests, 2);
  assert.deepEqual(older.jsonOnlyTurnIns, []);
  assert(!fs.existsSync(path.join(root, 'catvoices')), 'Importer must never generate a CatVoices pack');
  console.log('PASS: audio import, Lua priority, turn-in-only JSON recovery, Classic overlaps, stream validation and older packs');
} finally {
  assert.equal(path.dirname(fixture), path.resolve(os.tmpdir()));
  assert(path.basename(fixture).startsWith('wowvoice-audio-import-'));
  fs.rmSync(fixture, { recursive: true, force: true });
}

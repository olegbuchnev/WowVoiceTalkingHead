// Read-only check of the current resolver against an installed external pack.
// Parse upstream Lua as data; never execute another addon's code or import it.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const {lua, lauxlib, lualib, to_luastring, to_jsstring} = require('fengari');
const {dataTable, duration} = require('./import-forever-audio');
const source = process.argv[2], previous = process.argv[3];
if (!source) throw Error('Usage: node tools/check-catquest-compatibility.js <voices directory> [previous voices directory]');
const root = path.resolve(__dirname, '..');
const version = /^##\s*Version:\s*(\S+)/m.exec(fs.readFileSync(path.join(source, 'CatQuest_Voices.toc'), 'utf8'))?.[1];
const quests = dataTable(path.join(source, 'Index.lua'));
function literal(value) {
  if (value === undefined || value === null) return 'nil';
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  if (typeof value === 'string') return '"' + value.replace(/[\\"\x00-\x1f\x7f]/g, ch =>
    ch === '\\' || ch === '"' ? '\\' + ch : '\\' + ch.charCodeAt(0).toString().padStart(3, '0')) + '"';
  return '{' + Object.entries(value).map(([key, item]) =>
    '[' + (/^\d+$/.test(key) ? key : literal(key)) + ']=' + literal(item)).join(',') + '}';
}
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
function run(code, name) {
  let status = lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring(name));
  if (status === lua.LUA_OK) status = lua.lua_pcall(L, 0, 0, 0);
  if (status !== lua.LUA_OK) throw Error(to_jsstring(lua.lua_tostring(L, -1)));
}
for (const file of ['CatQuestAudio.lua', 'CatQuestTexts.lua', 'AudioSources.lua']) {
  run(fs.readFileSync(path.join(root, 'src', file), 'utf8'), file);
}
run(`CatQuestVoicePack={quests=${literal(quests)}}
C_AddOns={IsAddOnLoaded=function() return true,true end,GetAddOnMetadata=function() return ${literal(version)} end}
local sex=2;UnitSex=function() return sex end
checked={};blocked={};snapshotVersion=WowVoiceCatQuestAudio.sourceVersion
for key in pairs(WowVoiceCatQuestAudio.entries) do
 local id,section=key:match('^(%d+)([ac])$')
 for _,playerSex in ipairs({2,3}) do
  sex=playerSex;local recording=WowVoiceAudioSources.Resolve(tonumber(id),section)
  if recording then
   checked[#checked+1]={key=key,sex=sex,file=recording.path:match('([^\\\\]+)$'),duration=recording.duration}
  else blocked[#blocked+1]=key..':'..sex end
 end
end`, 'parsed-external-index');
const result = {indexedVersion: '', installedVersion: version, eligibleBySex: {male: 0, female: 0},
  blockedBySex: {male: 0, female: 0}, eligibleFiles: 0, missingFiles: [], invalidFiles: [],
  tooShortTimers: [], unchangedAudio: 0, changedAudio: 0};
lua.lua_getglobal(L, to_luastring('snapshotVersion'));
result.indexedVersion = to_jsstring(lua.lua_tostring(L, -1));lua.lua_pop(L, 1);
const files = new Map();
lua.lua_getglobal(L, to_luastring('checked'));
for (let i = 1; i <= lua.lua_rawlen(L, -1); i++) {
  lua.lua_rawgeti(L, -1, i);
  const recording = {};
  for (const field of ['key', 'file', 'sex', 'duration']) {
    lua.lua_getfield(L, -1, to_luastring(field));
    recording[field] = lua.lua_isnumber(L, -1) ? lua.lua_tonumber(L, -1) : to_jsstring(lua.lua_tostring(L, -1));
    lua.lua_pop(L, 1);
  }
  result.eligibleBySex[recording.sex === 3 ? 'female' : 'male']++;
  files.set(recording.file, recording.duration);
  lua.lua_pop(L, 1);
}
lua.lua_pop(L, 1);
lua.lua_getglobal(L, to_luastring('blocked'));
for (let i = 1; i <= lua.lua_rawlen(L, -1); i++) {
  lua.lua_rawgeti(L, -1, i);
  result.blockedBySex[to_jsstring(lua.lua_tostring(L, -1)).endsWith(':3') ? 'female' : 'male']++;
  lua.lua_pop(L, 1);
}
lua.lua_close(L);
result.eligibleFiles = files.size;
const hash = buffer => crypto.createHash('sha256').update(buffer).digest('hex');
for (const [file, timer] of files) {
  const current = path.join(source, 'Sounds', 'q', file);
  if (!fs.existsSync(current)) {result.missingFiles.push(file);continue;}
  const buffer = fs.readFileSync(current);
  let seconds;
  try {seconds = duration(buffer);} catch {result.invalidFiles.push(file);continue;}
  if (seconds > timer) result.tooShortTimers.push({file, seconds, timer});
  if (previous) {
    const old = path.join(previous, 'Sounds', 'q', file);
    if (fs.existsSync(old) && hash(fs.readFileSync(old)) === hash(buffer)) result.unchangedAudio++;
    else result.changedAudio++;
  }
}
const destination = path.join(root, 'artifacts', 'review', 'catquest-compatibility.json');
fs.mkdirSync(path.dirname(destination), {recursive: true});
fs.writeFileSync(destination, JSON.stringify(result, null, 2) + '\n');
process.stdout.write(JSON.stringify(result, null, 2) + '\n');
if (result.missingFiles.length || result.invalidFiles.length || result.tooShortTimers.length) process.exitCode = 1;

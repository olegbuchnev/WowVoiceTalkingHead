// Read current Forever Quest Pins as data; do not run its Lua or ATT tooling.
const fs = require('fs'), path = require('path');
const {dataTable} = require('./import-forever-audio');
const {generate,sha256} = require('./generate-speakers');
function collect(directory, commit) {
  if (!/^[a-f0-9]{40}$/.test(commit)) throw Error('Expected pinned Forever Quest Pins commit');
  const file = path.join(directory,'ForeverQuests.lua'), metadata = dataTable(path.join(directory,'Metadata.lua'),'Metadata');
  const quests = dataTable(file,'Quests'), givers = {};
  if (metadata.source !== 'ATTWoWAddon/AllTheThings' || Object.keys(quests).length !== metadata.questCount) throw Error('Unexpected Pins schema/count');
  for (const [id,quest] of Object.entries(quests)) {
    const ids = [...new Set(quest.qgs ? Object.values(quest.qgs) : quest.qg ? [quest.qg] : [])];
    if (!Number.isSafeInteger(Number(id)) || Number(id)<=0 || ids.some(n=>!Number.isSafeInteger(n)||n<=0)) throw Error('Invalid Pins ID');
    if (ids.length) givers[id] = ids.length === 1 ? ids[0] : false;
  }
  return {schemaVersion:1, source:'https://github.com/TylerAkins/forever-quest-markers', commit,
    attCommit:metadata.attCommit, sha256:sha256(fs.readFileSync(file)), questCount:metadata.questCount, givers};
}
module.exports = {collect};
if (require.main === module) {
  const result=collect(process.argv[2],process.argv[3]);
  fs.writeFileSync(path.join(__dirname,'../docs/internal/forever-pins-speakers-source.json'),JSON.stringify(result,null,2)+'\n');
  console.log(JSON.stringify(generate().counts));
}

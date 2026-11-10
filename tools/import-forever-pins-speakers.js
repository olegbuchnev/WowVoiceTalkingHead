// Read current Forever Quest Pins as data; do not run its Lua or ATT tooling.
const fs = require('fs'), path = require('path');
const {dataTable} = require('./import-forever-audio');
const {generate,sha256} = require('./generate-speakers');
function collect(directory, commit) {
  if (!/^[a-f0-9]{40}$/.test(commit)) throw Error('Expected pinned Forever Quest Pins commit');
  const file = path.join(directory,'ForeverQuests.lua'), metadata = dataTable(path.join(directory,'Metadata.lua'),'Metadata');
  const quests = dataTable(file,'Quests'), givers = {}, finishers = {};
  const questie = metadata.source === 'QuestieDB-Forever';
  if ((questie ? metadata.contractVersion !== 4 : metadata.source !== 'ATTWoWAddon/AllTheThings')
      || Object.keys(quests).length !== metadata.questCount) throw Error('Unexpected Pins schema/count');
  if (questie && (!/^[a-f0-9]{40}$/.test(metadata.artifactCommit || '')
      || !/^[a-f0-9]{64}$/.test(metadata.artifactSHA256 || '')
      || !/^[a-f0-9]{40}$/.test(metadata.policyCommit || ''))) throw Error('Invalid Pins provenance');
  const positive = n => Number.isSafeInteger(n) && n > 0;
  function ids(value) {
    if (value === undefined) return [];
    if (!value || typeof value !== 'object' || Object.keys(value).some((k,i)=>Number(k)!==i+1)
        || Object.values(value).some(n=>!positive(n))) throw Error('Invalid Pins ID list');
    return [...new Set(Object.values(value))];
  }
  let turnInCount = 0;
  for (const [id,quest] of Object.entries(quests)) {
    if (!positive(Number(id)) || !quest || typeof quest !== 'object'
        || (quest.qg !== undefined && !positive(quest.qg))) throw Error('Invalid Pins ID');
    const starters = [...new Set([...ids(quest.qgs), ...(quest.qg === undefined ? [] : [quest.qg])])];
    if (starters.length) givers[id] = starters.length === 1 ? starters[0] : false;
    if (questie) {
      const targets = ids(quest.turnIns), objects = ids(quest.turnInObjects);
      if (targets.length || objects.length) {
        turnInCount++;
        // Object IDs are a different namespace. Never treat them as NPC IDs.
        finishers[id] = targets.length === 1 && !objects.length ? targets[0] : false;
      }
    }
  }
  if (questie && turnInCount !== metadata.turnInCount) throw Error('Unexpected Pins turn-in count');
  return {schemaVersion:1, source:'https://github.com/TylerAkins/forever-quest-markers', commit,
    ...(questie ? {databaseSource:metadata.source, contractVersion:4, artifactCommit:metadata.artifactCommit,
      artifactSHA256:metadata.artifactSHA256, policyCommit:metadata.policyCommit, finishers}
      : {attCommit:metadata.attCommit}),
    metadataSHA256:sha256(fs.readFileSync(path.join(directory,'Metadata.lua'))),
    sha256:sha256(fs.readFileSync(file)), questCount:metadata.questCount, givers};
}
module.exports = {collect};
if (require.main === module) {
  const result=collect(process.argv[2],process.argv[3]);
  fs.writeFileSync(path.join(__dirname,'../docs/internal/forever-pins-speakers-source.json'),JSON.stringify(result,null,2)+'\n');
  console.log(JSON.stringify(generate().counts));
}

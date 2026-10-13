// Only explicit creature categories, never generic voice timbre or player sex.
const labels = new Map([
  ['ancient-male','ancient'], ['ancient-female','ancient'], ['creature/ancient','ancient'],
  ['furbolg-male','furbolg'], ['furbolg-female','furbolg'], ['creature/furbolg','furbolg'],
  ['creature/banshee','banshee'],
]);
function creatureVoiceMetadata(observations) {
  const byNPC = new Map();
  for (const {npcID,voice} of observations) {
    if (!Number.isSafeInteger(npcID) || npcID<=0 || typeof voice!=='string') continue;
    if (!byNPC.has(npcID)) byNPC.set(npcID,new Set());
    byNPC.get(npcID).add(labels.get(voice) || null);
  }
  const result = {};
  for (const [id,races] of byNPC) if (races.size===1 && !races.has(null))
    result[id] = {voiceRace:[...races][0]};
  return result;
}
module.exports = {creatureVoiceMetadata};

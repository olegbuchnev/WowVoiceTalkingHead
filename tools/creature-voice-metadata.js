// Only explicit creature categories, never generic voice timbre or player sex.
const labels = new Map([
  ['ancient-male','ancient'], ['ancient-female','ancient'], ['creature/ancient','ancient'],
  ['furbolg-male','furbolg'], ['furbolg-female','furbolg'], ['creature/furbolg','furbolg'],
  ['creature/banshee','banshee'],
  ['creature/dreadlord','dreadlord'],
  ['elemental-water','elemental_water'],
  ['imp-male','imp'],
  ['centaur-male','centaur'],
]);
function creatureVoiceMetadata(observations) {
  const byNPC = new Map();
  for (const {npcID,voice} of observations) {
    if (!Number.isSafeInteger(npcID) || npcID<=0 || typeof voice!=='string') continue;
    if (!byNPC.has(npcID)) byNPC.set(npcID,new Set());
    byNPC.get(npcID).add(labels.get(voice) || null);
  }
  const result = {};
  for (const [id,races] of byNPC) if (races.size===1 && !races.has(null)) {
    const race = [...races][0];
    result[id] = {voiceRace:race};
    if (race === 'imp' || race === 'centaur') result[id].voiceSex = 'male';
  }
  return result;
}
module.exports = {creatureVoiceMetadata};

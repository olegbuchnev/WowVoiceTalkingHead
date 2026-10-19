// Only explicit creature categories, never generic voice timbre or player sex.
const labels = new Map([
  ['ancient-male','ancient'], ['ancient-female','ancient'], ['creature/ancient','ancient'],
  ['furbolg-male','furbolg'], ['furbolg-female','furbolg'], ['creature/furbolg','furbolg'],
  ['creature/banshee','banshee'],
  ['creature/dreadlord','dreadlord'],
  ['elemental-water','elemental_water'],
  ['elemental-fire','elemental_fire'],
  ['imp-male','imp'],
  ['centaur-male','centaur'],
  ['dragon-male','dragon'], ['dragon-female','dragon'], ['creature/dragon','dragon'],
]);
function creatureVoiceMetadata(observations) {
  const byNPC = new Map(), dragonSex = new Map();
  for (const {npcID,voice} of observations) {
    if (!Number.isSafeInteger(npcID) || npcID<=0 || typeof voice!=='string') continue;
    if (!byNPC.has(npcID)) byNPC.set(npcID,new Set());
    byNPC.get(npcID).add(labels.get(voice) || null);
    if (voice === 'dragon-male' || voice === 'dragon-female') {
      if (!dragonSex.has(npcID)) dragonSex.set(npcID,new Set());
      dragonSex.get(npcID).add(voice.slice('dragon-'.length));
    }
  }
  const result = {};
  for (const [id,races] of byNPC) if (races.size===1 && !races.has(null)) {
    const race = [...races][0];
    if (race === 'dragon' && dragonSex.get(id)?.size > 1) continue;
    result[id] = {voiceRace:race};
    if (race === 'imp' || race === 'centaur') result[id].voiceSex = 'male';
    if (race === 'dragon' && dragonSex.get(id)?.size === 1) result[id].voiceSex = [...dragonSex.get(id)][0];
  }
  return result;
}
module.exports = {creatureVoiceMetadata};

// Voice labels describe the speaker, not the m/f player audio variants.
// They supply ageGroup and sex, never race or a human camera profile.
// Orcs and children of other races may use these voices too.
function childVoiceMetadata(observations) {
  const byNPC = new Map();
  for (const {npcID, voice} of observations) {
    if (!Number.isSafeInteger(npcID) || npcID <= 0 || typeof voice !== 'string') continue;
    if (!byNPC.has(npcID)) byNPC.set(npcID, new Set());
    byNPC.get(npcID).add(voice);
  }
  const result = {};
  for (const [id, voices] of byNPC) {
    // Conflicting stages/quests are not evidence of one child's identity.
    if (voices.size !== 1) continue;
    const match = /^child-(male|female)$/.exec([...voices][0]);
    if (match) result[id] = {ageGroup:'child', sex:match[1]};
  }
  return result;
}
module.exports = {childVoiceMetadata};

export const voteStorageKey='talkinghead-prototype-votes';
export const libraries=['WowVoice','CatQuest','Wayfarer'];

export function readVotes(storage=localStorage) {
  const records=JSON.parse(storage.getItem(voteStorageKey) || '[]');
  if(!Array.isArray(records)) throw Error('Invalid vote history');
  return records;
}

export function countVotes(records) {
  const counts=Object.fromEntries(libraries.map(name=>[name,0]));
  for(const record of records) {
    const pack=record?.candidates?.find?.(candidate=>candidate?.id===record.selected)?.pack;
    const library=pack==='WowVoiceSounds' ? 'WowVoice' : pack==='CatQuest_Voices' ? 'CatQuest'
      : typeof pack==='string' && pack.startsWith('Wayfarer_Voices_') ? 'Wayfarer' : null;
    if(library) counts[library]++;
  }
  return counts;
}

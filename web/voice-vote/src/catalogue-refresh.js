// A ballot always refers to the exact recordings the listener heard.
export const comparisonKey=(questID,variantIds)=>JSON.stringify([questID,[...variantIds].sort()]);
export const questKey=quest=>comparisonKey(quest.questID,quest.variants.map(v=>v.id));

export function createCatalogueClient({request=fetch}={}) {
  let snapshot,etag,pending;
  return {
    current:()=>snapshot,
    load() {
      if(pending) return pending;
      pending=(async()=>{
        const response=await request('/api/catalogue',{
          cache:'no-store',signal:AbortSignal.timeout(15000),
          headers:etag ? {'If-None-Match':etag} : {},
        });
        if(response.status===304 && snapshot) return snapshot;
        if(!response.ok) throw Error('Не удалось обновить список сравнений. Попробуйте ещё раз.');
        const data=await response.json();
        if(!Array.isArray(data.quests)) throw Error('Некорректный список сравнений.');
        // Also support older deployments and development fixtures without ETags.
        if(!snapshot || JSON.stringify(snapshot)!==JSON.stringify(data)) snapshot=data;
        etag=response.headers.get('ETag');
        return snapshot;
      })().finally(()=>{pending=null;});
      return pending;
    },
  };
}

// Keep the current/finished comparisons immutable. Refresh only unseen entries,
// retaining blind card order and mounted portraits wherever possible.
export function refreshComparisons(entries,quests,keep=0) {
  const current=new Map(quests.map(q=>[q.questID,q]));
  return entries.flatMap((entry,index)=>{
    if(index<keep) return [entry];
    const quest=current.get(entry.quest.questID);
    if(!quest || quest.variants.length<2) return [];
    if(JSON.stringify(quest)===JSON.stringify(entry.quest)) return [entry];
    const variants=entry.variants.map(old=>quest.variants.find(v=>v.source===old.source)).filter(Boolean);
    variants.push(...quest.variants.filter(v=>!variants.includes(v)));
    const samePortrait=JSON.stringify(quest.npc)===JSON.stringify(entry.quest.npc);
    return [{...entry,quest,variants,key:samePortrait ? entry.key : `${entry.key}:${JSON.stringify(quest.npc)}`}];
  });
}

export function withLocalRatings(priorities,quests,localRated) {
  const keys=new Map(quests.map(q=>[q.questID,questKey(q)]));
  return priorities.map(p=>({...p,rated:p.rated || localRated.has(keys.get(p.questID))}));
}

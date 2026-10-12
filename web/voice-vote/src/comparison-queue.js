function shuffle(items, random) {
  const copy=[...items];
  for(let i=copy.length-1;i>0;i--) {
    const j=Math.floor(random()*(i+1));
    [copy[i],copy[j]]=[copy[j],copy[i]];
  }
  return copy;
}

// A batch never pads unseen quests with repeats. Replays require an explicit action.
export function createComparisonBatch(quests, priorities=[], {repeat=false, previousQuestID, random=Math.random}={}) {
  const rated=new Set(priorities.filter(p=>p.rated).map(p=>p.questID));
  const candidates=quests.filter(q=>repeat || !rated.has(q.questID));
  const ranks=new Map(priorities.map((p,i)=>[p.questID,i]));
  const ordered=shuffle(candidates,random).sort((a,b)=>(ranks.get(a.questID)??Infinity)-(ranks.get(b.questID)??Infinity));
  if(repeat && ordered.length>1 && ordered[0].questID===previousQuestID)
    [ordered[0],ordered[1]]=[ordered[1],ordered[0]];
  const selected=ordered.slice(0,5);
  const queue=createComparisonQueue(selected,random,selected.map(q=>({questID:q.questID})));
  return selected.map(()=>queue.take());
}

// Reserve both the quest and its blind A/B/C ordering before loading resources.
// Each round visits every quest; a new round never repeats the previous quest.
export function createComparisonQueue(quests, random=Math.random, priorities=[]) {
  let ranks;
  const order=items=>items.sort((a,b)=>(ranks.get(a.questID)??Infinity)-(ranks.get(b.questID)??Infinity));
  function updatePriority(entries) { ranks=new Map(entries.map((entry,i)=>[entry.questID,i])); }
  updatePriority(priorities);
  let remaining=order(shuffle(quests,random));
  let previous, sequence=0;
  return {updatePriority(entries) { updatePriority(entries); order(remaining); }, take() {
    if(!quests.length) return null;
    if(!remaining.length) {
      remaining=order(shuffle(quests,random));
      if(remaining.length>1 && remaining[0].questID===previous)
        [remaining[0],remaining[1]]=[remaining[1],remaining[0]];
    }
    const quest=remaining.shift();
    previous=quest.questID;
    return {key:++sequence,quest,variants:shuffle(quest.variants,random)};
  }};
}

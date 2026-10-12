import {libraries} from './vote-history.js';

// Memory only: refreshing the page starts a fresh chart, not a new visitor.
export function sessionSummary(votes) {
  const counts=Object.fromEntries(libraries.map(name=>[name,0]));
  for (const source of Object.values(votes)) if (source in counts) counts[source]++;
  return {counts,total:Object.values(counts).reduce((sum,n)=>sum+n,0)};
}

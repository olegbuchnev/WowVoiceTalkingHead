const assets=new Map();
export function modelAssetURL(value) {
  const url=new URL(value,location.origin);
  const hash=url.origin===location.origin && assets.get(url.pathname);
  if(!hash) return value;
  url.searchParams.set('v',hash);
  return url.href;
}
export async function loadModelVersions(displayID) {
  const response=await fetch(`/api/model-versions/${displayID}`,{cache:'no-cache',signal:AbortSignal.timeout(15000)});
  if(!response.ok) throw Error('Portrait resource versions unavailable');
  const result=await response.json();
  for(const [url,hash] of Object.entries(result.assets)) {
    if(!url.startsWith('/modelviewer/') || !/^[a-f0-9]{64}$/.test(hash)) throw Error('Invalid portrait resource version');
    assets.set(url,hash);
  }
}

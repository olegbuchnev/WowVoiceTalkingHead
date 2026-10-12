// Keep only the current and next comparison in memory. Fetch explicitly:
// <audio preload="auto"> is a hint and can leave other variants unloaded.
export function createAudioPreloader({fetcher=fetch,createURL=URL.createObjectURL,revokeURL=URL.revokeObjectURL,timeout=30000}={}) {
  const entries=new Map();
  function release(url,entry) {
    entries.delete(url);
    entry.controller.abort();
    clearTimeout(entry.timer);
    if(entry.objectURL) revokeURL(entry.objectURL);
  }
  function retain(variants) {
    const urls=new Set(variants.map(v=>v.url).filter(Boolean));
    for(const [url,entry] of entries) if(!urls.has(url)) release(url,entry);
    for(const url of urls) {
      if(entries.has(url)) continue;
      const entry={controller:new AbortController(),objectURL:null};
      entries.set(url,entry);
      entry.timer=setTimeout(()=>entry.controller.abort(),timeout);
      entry.pending=Promise.resolve().then(()=>fetcher(url,{signal:entry.controller.signal}))
        .then(response=>{
          if(!response.ok) throw Error(`Audio preload failed: ${response.status}`);
          return response.blob();
        }).then(blob=>{
          if(entries.get(url)===entry && !entry.controller.signal.aborted) entry.objectURL=createURL(blob);
        }).catch(()=>{
          // Background failures stay silent; playback can still stream normally.
          if(entries.get(url)===entry) release(url,entry);
        }).finally(()=>clearTimeout(entry.timer));
    }
  }
  return {
    retain,
    // Never make an early click wait for a complete background download.
    source:variant=>entries.get(variant.url)?.objectURL || variant.url,
    dispose:()=>{for(const [url,entry] of entries) release(url,entry);},
  };
}

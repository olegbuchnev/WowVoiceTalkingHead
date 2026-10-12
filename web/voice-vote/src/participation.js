// Keep pre-vote activity in memory only. A visit exists on the server only
// after its first confirmed ballot; opening the page alone is not a visit.
export function createParticipationTracker() {
  const visitID=crypto.randomUUID(), pending=new Map(), sent=new Set();
  let confirmed=false, flushing=false, stopped=false, timer;
  async function flush() {
    if(!confirmed || flushing || stopped) return;
    flushing=true;
    try {
      for(const [id,event] of pending) {
        try {
          const response=await fetch('/api/votes/playback',{method:'POST',credentials:'same-origin',
            headers:{'Content-Type':'application/json'},body:JSON.stringify({visitID,...event}),signal:AbortSignal.timeout(5000)});
          if(!response.ok) continue;
          pending.delete(id);sent.add(id);
        } catch { /* Analytics failure must never block playback or voting. */ }
      }
    } finally {
      flushing=false;clearTimeout(timer);
      // Admission can precede the database commit; retry playback after it.
      if(pending.size && !stopped) {timer=setTimeout(flush,5000);timer.unref?.();}
    }
  }
  return {visitID,
    played(questID,recordingID) {if(!sent.has(recordingID)) pending.set(recordingID,{questID,recordingID});void flush();},
    confirmed() {confirmed=true;void flush();},
    stop() {stopped=true;clearTimeout(timer);}
  };
}

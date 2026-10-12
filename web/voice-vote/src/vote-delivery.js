import {enqueueVote,loadSummary} from './vote-api.js';

// Only in-flight requests live here. The durable queue belongs to the server.
// Keep order within this page so retries cannot overwrite a later choice.
export function createVoteDelivery({send=enqueueVote,identify=loadSummary,onAccepted=()=>{},onObsolete=()=>{}}={}) {
  const pending=[];
  let running=false,timer,stopped=false,attempt=0;
  async function flush() {
    if(running || stopped || !pending.length) return;
    running=true;
    try {
      await identify();
      while(pending.length && !stopped) {
        const ballot=pending[0];
        try {
          const accepted=await send(ballot);
          pending.shift();attempt=0;onAccepted(ballot,accepted);
        } catch(error) {
          // Old/invalid comparisons cannot be repaired by resending. Never
          // substitute a different recording for an unaccepted choice.
          if([400,403,404,409].includes(error.status)) {
            pending.shift();
            if([404,409].includes(error.status)) {
              // Refresh independently of delivery; never resend this choice as
              // a vote for the replacement recording, even if refresh fails.
              void Promise.resolve().then(()=>onObsolete(ballot)).catch(()=>{});
            }
            continue;
          }
          throw error;
        }
      }
    } catch {attempt++;}
    finally {
      running=false;
      if(pending.length && !stopped) {
        timer=setTimeout(flush,Math.min(30000,1000*2**Math.min(attempt,5)));
        timer.unref?.();
      }
    }
  }
  return {
    enqueue(ballot) {pending.push(ballot);void flush();},
    retry() {clearTimeout(timer);void flush();},
    stop() {stopped=true;clearTimeout(timer);},
  };
}

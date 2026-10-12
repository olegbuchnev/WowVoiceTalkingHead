// A slow download can outlive the placeholder's timeout. Keep observing it so
// the portrait appears when ready, without requiring another page load.
export function watchPortraitReadiness({isReady,onReady,onError,timeout=120000,interval=150}) {
  const deadline=Date.now()+timeout;
  let warned=false;
  const timer=setInterval(()=>{
    let ready;
    try {ready=isReady();}
    catch {clearInterval(timer);onError();return;}
    if(ready) {clearInterval(timer);onReady();}
    else if(!warned && Date.now()>deadline) {warned=true;onError();}
  },interval);
  return ()=>clearInterval(timer);
}

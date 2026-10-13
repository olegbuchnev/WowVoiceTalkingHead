// Replace only the external model engine. The React portrait, readiness timer,
// placeholder and camera handoff remain production code in the browser test.
export async function createPortrait(container,npc) {
  const viewer={container,ready:false,destroyed:false};
  const canvas=document.createElement('canvas');container.append(canvas);
  void fetch(`/test/model/${npc.displayID}`).then(r=>r.arrayBuffer()).then(()=>{viewer.ready=true;});
  viewer.destroy=()=>{viewer.destroyed=true;canvas.remove();};
  return viewer;
}
export const isPortraitLoaded=viewer=>viewer.ready;
export const portraitStatus=viewer=>({actorLoaded:viewer.ready,contextLost:false,
  animations:viewer.ready?1:0,pendingDownloads:viewer.ready?0:1,textures:0,pendingTextures:0});
export function setTalking() {}
export async function framePortrait(viewer,signal) {
  await fetch('/test/camera',{signal}).then(r=>r.json());
  viewer.container.dataset.cameraConfigured='true';
}

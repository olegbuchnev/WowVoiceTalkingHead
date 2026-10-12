// Replace only the external model engine. The React portrait, readiness timer,
// placeholder and camera handoff remain production code in the browser test.
export async function createPortrait(container,npc) {
  const viewer={container,ready:false,destroyed:false};
  void fetch(`/test/model/${npc.displayID}`).then(r=>r.arrayBuffer()).then(()=>{viewer.ready=true;});
  viewer.destroy=()=>{viewer.destroyed=true;};
  return viewer;
}
export const isPortraitLoaded=viewer=>viewer.ready;
export function setTalking() {}
export async function framePortrait(viewer,signal) {
  await fetch('/test/camera',{signal}).then(r=>r.json());
  viewer.container.dataset.cameraConfigured='true';
}

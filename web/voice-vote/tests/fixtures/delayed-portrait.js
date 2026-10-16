// Replace only the external model engine. The React portrait, readiness timer,
// placeholder and camera handoff remain production code in the browser test.
export async function createPortrait(container,npc) {
  const viewer={container,ready:false,destroyed:false};
  container.modelViewer=viewer;
  const canvas=document.createElement('canvas');container.append(canvas);
  void fetch(`/test/model/${npc.displayID}`).then(r=>r.arrayBuffer()).then(bytes=>{
    viewer.failedTexture=new Uint8Array(bytes)[0]===0;
    viewer.ready=!viewer.failedTexture;
  });
  viewer.destroy=()=>{viewer.destroyed=true;canvas.remove();};
  return viewer;
}
export const isPortraitLoaded=viewer=>viewer.ready;
export const portraitStatus=viewer=>({actorLoaded:viewer.ready || !!viewer.failedTexture,contextLost:false,
  animations:viewer.ready || viewer.failedTexture?1:0,pendingDownloads:viewer.ready || viewer.failedTexture?0:1,
  textures:viewer.failedTexture?12:0,pendingTextures:viewer.failedTexture?7:0});
export function setTalking() {}
export async function framePortrait(viewer,signal) {
  await fetch('/test/camera',{signal}).then(r=>r.json());
  viewer.container.dataset.cameraConfigured='true';
}

import $ from 'jquery';
import {installPortraitCamera} from './portrait-camera.js';
import {installPortraitLighting} from './portrait-light.js';
let loading;
export function loadViewer() {
  if (window.ZamModelViewer) return Promise.resolve();
  if (loading) return loading;
  window.$ = window.jQuery = $;
  window.WH ||= { debug:()=>{}, defaultAnimation:'Stand', WebP:{getImageExtension:()=>'.webp'} };
  loading = new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = '/modelviewer/live/viewer/viewer.min.js?portrait-light=2';
    script.onload = resolve; script.onerror = () => { loading = null; script.remove(); reject(Error('Просмотрщик недоступен')); };
    document.head.append(script);
  });
  return loading;
}
export async function createPortrait(container, npc, {originalAssets=false}={}) {
  await loadViewer();
  const viewer = new window.ZamModelViewer({type:2, container:$(container), aspect:1,
    // Forever is named classicplus on Wowhead's asset CDN. Display IDs are
    // shared with Retail, but their appearance/equipment data is different.
    // Keep the tested rendering engine separate from the model data branch.
    contentPath:`${location.origin}/modelviewer/${originalAssets?'':'portrait-v1/'}classicplus/`, models:{id:npc.displayID,type:8}, hd:true});
  fitPortraitResolution(viewer, container);
  container.modelViewer = viewer;
  return viewer;
}

export function isPortraitLoaded(viewer) {
  const renderer = viewer.renderer, actor = renderer?.actors?.[0];
  if (!actor?.isLoaded?.() || !actor.getNumAnimations?.()) return false;
  // Geometry/animation readiness alone can expose an untextured model. The
  // cached viewer's texture m() reports completion of the GPU upload as well.
  const textures = renderer.textureCache;
  if (!(textures instanceof Map)) throw Error('Portrait texture readiness unavailable');
  return Object.keys(renderer.downloads).length === 0
    && [...textures.values()].every(texture => texture.m());
}

// Bounded status fields only: no URLs, texture names or browser error messages.
export function portraitStatus(viewer) {
  try {
    const r=viewer?.renderer, actor=r?.actors?.[0], textures=r?.textureCache;
    const canvas=r?.canvas?.[0], gl=canvas?.getContext('webgl2');
    const values=textures instanceof Map ? [...textures.values()] : [];
    return {contextLost:!!gl?.isContextLost(),actorLoaded:!!actor?.isLoaded?.(),
      animations:actor?.getNumAnimations?.() || 0,
      pendingDownloads:Object.keys(r?.downloads || {}).length,
      textures:values.length,pendingTextures:values.filter(t=>!t.m()).length};
  } catch {return {};}
}

function fitPortraitResolution(viewer, container) {
  // The viewer assumes CSS pixels are framebuffer pixels. Account for both the
  // head's CSS zoom and display DPR, then supersample 2x to reduce moving edges.
  // Its resize API also resizes DOM elements; restore their logical dimensions.
  viewer.setAdaptiveMode(false);
  const logicalWidth = container.style.width, logicalHeight = container.style.height;
  let disposed = false, densityQuery;
  const resize = () => {
    if (disposed) return;
    const {width, height} = container.getBoundingClientRect();
    if (!(width > 0 && height > 0)) return;
    const density = window.devicePixelRatio || 1;
    const factor = Math.min(density * 2, 1024 / Math.max(width, height));
    const w = Math.ceil(width * factor), h = Math.ceil(height * factor);
    viewer.renderer.onResize(w, h, width / height);
    container.style.width = logicalWidth;
    container.style.height = logicalHeight;
    Object.assign(viewer.renderer.canvas[0].style, {width:'100%', height:'100%'});
  };
  const watchDensity = () => {
    densityQuery?.removeEventListener('change', watchDensity);
    densityQuery = matchMedia(`(resolution: ${window.devicePixelRatio || 1}dppx)`);
    densityQuery.addEventListener('change', watchDensity);
    resize();
  };
  const observer = new ResizeObserver(resize);
  observer.observe(container);
  window.addEventListener('resize', resize);
  watchDensity();
  const destroy = viewer.destroy;
  viewer.destroy = function(...args) {
    disposed = true;
    observer.disconnect();
    window.removeEventListener('resize', resize);
    densityQuery?.removeEventListener('change', watchDensity);
    return destroy.apply(this, args);
  };
}

export function setTalking(viewer, talking) {
  // Public actor methods; no phoneme/lip synchronization is used.
  const actor = viewer?.renderer?.actors?.[0];
  // Playback can start while the next portrait is still downloading. Its
  // ready callback applies the latest playback state after animations load.
  if (!actor?.isLoaded?.() || !actor.getNumAnimations?.()) return;
  const names = Array.from({length:actor.getNumAnimations()}, (_, i) => actor.getAnimation(i));
  const animation = talking ? (names.includes('EmoteTalk') ? 'EmoteTalk' : names.find(n=>/Talk/.test(n)) || 'Stand') : 'Stand';
  // Use the first frame of Stand between recordings. Stand alone keeps running
  // and eventually picks idle variations (stretching, shifting weight, etc.).
  // setAnimation already starts at time zero. resetAnimation would select
  // Stand again, replacing EmoteTalk rather than rewinding the selected clip.
  actor.setAnimation(animation, false);
  if (!talking) {
    // Adapter for the cached ZamModelViewer: pause freezes each bone's cached
    // transform, not just the clip clock. Reset time/blending, then evaluate
    // Stand with zero elapsed time before freezing those transforms. Public
    // resetAnimation() only selects Stand; it does not evaluate its pose.
    const model = actor.c;
    if (typeof model?.q !== 'function' || typeof model.ab !== 'function' || !model.as)
      throw Error('Просмотрщик не поддерживает сброс позы.');
    const delta = model.as.delta, updateBounds = model.as.doUpdateBounds;
    actor.setAnimPaused(false);
    try {
      model.q();
      model.as.delta = 0;
      model.ab();
    } finally {
      model.as.delta = delta;
      // Resetting a pose must not trigger the viewer's full-body camera refit.
      model.as.doUpdateBounds = updateBounds;
      actor.setAnimPaused(true);
    }
  }
  actor.setAnimPaused(!talking);
  viewer.container[0].dataset.animation = animation;
}

export async function framePortrait(viewer, signal) {
  const fileID=viewer.renderer?.actors?.[0]?.c?.aX;
  if(!Number.isInteger(fileID) || fileID<=0) throw Error('Portrait model ID unavailable');
  const response=await fetch(`/api/portrait-camera/${fileID}`,{signal});
  if(!response.ok) throw Error('Portrait camera unavailable');
  const settings=await response.json();
  if(signal?.aborted) return;
  installPortraitCamera(viewer,settings);
  installPortraitLighting(viewer);
}

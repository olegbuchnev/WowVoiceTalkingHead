// Convert the authored M2 camera through the viewer's model transform (including
// its quarter-turn and model scale). Addon offsets move the model, so subtract
// them from eye and target. No race-specific browser framing constants.
export function portraitView(camera, profile, matrix) {
  // Native PlayerModel offsets are not necessarily in raw M2 units. Use a
  // validated client measurement when available; the shared profile stays intact.
  const scale=camera.positionScale ?? 1;
  const offset=[0,profile.y*scale,profile.z*scale];
  const transform=v=>[0,1,2].map(j=>matrix[j]*v[0]+matrix[4+j]*v[1]+matrix[8+j]*v[2]+matrix[12+j]);
  const target=transform(camera.target.map((v,i)=>v-offset[i]));
  const eye=transform(camera.position.map((v,i)=>camera.target[i]+(v-camera.target[i])*profile.distance-offset[i]));
  const delta=eye.map((v,i)=>v-target[i]), distance=Math.hypot(...delta);
  return {target,distance,azimuth:Math.atan2(-delta[1],-delta[0]),zenith:Math.acos(-delta[2]/distance)};
}

export function installPortraitCamera(viewer, settings) {
  const r=viewer.renderer, model=r.actors[0]?.c;
  if(!model?.i || model.aX!==settings.fileID) throw Error('Portrait model changed');
  const {camera,profile}=settings;
  if(!camera) throw Error('Model has no portrait camera');
  // This adapter uses the cached viewer's transform and camera entry point.
  const view=portraitView(camera,profile,model.i);
  const update=r.updateCamera;
  r.updateCamera=function() {
    // Bounds recalculation after loading equipment/animations must not replace
    // the portrait with the viewer's full-body fit. Resize preserves this too.
    this.target.set(view.target);
    this.distance=view.distance; this.azimuth=view.azimuth; this.zenith=view.zenith;
    this.translation.fill(0); this.translationFromModel.fill(0);
    this.zoom.current=this.zoom.target=this.zoom.rateCurrent=0;
    this.up.set([0,0,1]);
    update.call(this);
    const aspect=this.width/this.height;
    // Convert authored diagonal FOV using the M2 camera aspect convention.
    // Native PlayerModel parity still needs in-game camera measurements.
    const fov=camera.fov/Math.sqrt(1+aspect*aspect), f=1/Math.tan(fov/2);
    this.fov=fov*180/Math.PI;
    const p=this.projMatrix, near=camera.near, far=camera.far;
    p.fill(0); p[0]=f/aspect; p[5]=f;
    p[10]=(far+near)/(near-far); p[11]=-1; p[14]=2*far*near/(near-far);
    // Roll is normally zero for portraits. Rotate the view's screen axes when
    // an authored camera supplies it, without disturbing the model transform.
    if(camera.roll) {
      const c=Math.cos(camera.roll), s=Math.sin(camera.roll), m=this.viewMatrix;
      for(let col=0;col<4;col++) {const i=col*4,x=m[i],y=m[i+1];m[i]=c*x-s*y;m[i+1]=s*x+c*y;}
    }
  };
  r.updateCamera();
  viewer.container[0].dataset.cameraProfile=profile.key;
  viewer.container[0].dataset.cameraModel=String(settings.fileID);
}

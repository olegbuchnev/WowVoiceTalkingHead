import light from './native-portrait-light.json';

function direction(matrix,vector) {
  // Direction vectors have w=0: camera/model translations must not affect light.
  return [0,1,2].map(j=>matrix[j]*vector[0]+matrix[4+j]*vector[1]+matrix[8+j]*vector[2]);
}

export function installPortraitLighting(viewer) {
  if(!light.enabled || light.omnidirectional) throw Error('Unsupported portrait light capture');
  const renderer=viewer.renderer;
  function sceneUniforms() {
    // Cached ZamModelViewer WebGL2 and WebGPU backends share this scene-uniform
    // object with material instances. Mutate its arrays, never replace them.
    const uniforms=renderer.renderer?.r;
    if(!uniforms?.uAmbientColor || !uniforms.uPrimaryColor || !uniforms.uSecondaryColor || !uniforms.uLightDir1)
      throw Error('Viewer lighting adapter unavailable');
    return uniforms;
  }
  sceneUniforms();
  const update=renderer.updateCamera;
  renderer.updateCamera=function() {
    update.call(this);
    const uniforms=sceneUniforms();
    for(let i=0;i<3;i++) {
      uniforms.uAmbientColor[i]=light.ambientColor[i]*light.ambientIntensity;
      uniforms.uPrimaryColor[i]=light.diffuseColor[i]*light.diffuseIntensity;
      uniforms.uSecondaryColor[i]=0;
    }
    // PlayerModel's directional point describes the rays; the shader uses a
    // vector towards the light. Transform it into the shader's view space using
    // the same model-axis conversion and camera as the rendered portrait.
    const model=this.actors[0].c;
    const towardLight=direction(this.viewMatrix,direction(model.i,light.point.map(v=>-v)));
    const length=Math.hypot(...towardLight);
    if(!(length>0)) throw Error('Invalid portrait light direction');
    for(let i=0;i<3;i++) uniforms.uLightDir1[i]=towardLight[i]/length;
  };
  renderer.updateCamera();
  viewer.container[0].dataset.lighting='forever-capture';
}

// The stock viewer clips ambient + diffuse to 1 BEFORE multiplying texture RGB.
// Keep the captured light's full radiance (up to ~1.498 here), leaving final
// framebuffer colour clamping intact. Apply only to the local portrait viewer;
// the downloaded/cache copy is never edited. Fail explicitly on vendor changes.
// The viewer samples display-encoded textures. Approximate linear-light shading
// with gamma 2.2: decode texture, multiply radiance, encode again simplifies to
// texture * pow(radiance, 1/2.2). This softens the exaggerated highlights without
// changing the captured light or stripping emissive/material effects. It is a
// visual approximation, not an exact reproduction of WoW's colour pipeline.
export function adaptViewerLighting(bytes) {
  let script=bytes.toString('utf8');
  const patches=[
    ['//wow.zamimg.com/modelviewer/viewer/viewer.css','/modelviewer/viewer/viewer.css'],
    ['litColor = clamp(litColor, vec4(0,0,0,0), vec4(1,1,1,1));','litColor = max(litColor, vec4(0,0,0,0));'],
    ['litColor = clamp(litColor, vec4f(0.0, 0.0, 0.0, 0.0), vec4f(1.0, 1.0, 1.0, 1.0));','litColor = max(litColor, vec4f(0.0, 0.0, 0.0, 0.0));'],
    ['_output.rgb *= (litColor * uDiffuseColor).rgb;',
      '_output.rgb *= pow(max((litColor * uDiffuseColor).rgb, vec3(0.0)), vec3(1.0 / 2.2));'],
    ['_output = vec4f(_output.rgb * (litColor * uDiffuseColor).rgb, _output.a);',
      '_output = vec4f(_output.rgb * pow(max((litColor * uDiffuseColor).rgb, vec3f(0.0)), vec3f(1.0 / 2.2)), _output.a);'],
  ];
  for(const [before,after] of patches) {
    if(script.split(before).length!==2) throw Error('Viewer shader changed: review portrait lighting adapter');
    script=script.replace(before,after);
  }
  return Buffer.from(script);
}

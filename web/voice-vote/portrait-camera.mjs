import fs from 'node:fs';
import {createRequire} from 'node:module';

const require = createRequire(import.meta.url);
const {lua, lauxlib, lualib, to_luastring, to_jsstring} = require('fengari');
const source = new URL('../../src/', import.meta.url);
const nativeSamples=JSON.parse(fs.readFileSync(new URL('./native-camera-samples.json',import.meta.url),'utf8'));

// GetCameraPosition/Target from this capture match:
//   nativePoint = authoredPoint * worldScale - position * (1 - worldScale).
// Dividing by worldScale gives the model-space translation factor below.
// This is a measured adapter calibration, NOT a universal PlayerModel formula.
// Keep unmeasured models (including the confirmed dwarf) unchanged. Revalidate
// against both camera points so a changed M2 or zoom cannot reuse stale data.
export function nativePositionScale(camera, profile, sample) {
  if(!camera || !sample || sample.modelScale!==1 || sample.distanceScale!==profile.distance
    || !(sample.worldScale>0 && sample.worldScale<1)) return null;
  const s=sample.worldScale;
  const predictedTarget=camera.target.map((v,i)=>v*s-sample.position[i]*(1-s));
  const predictedEye=camera.position.map((v,i)=>(camera.target[i]+(v-camera.target[i])*sample.distanceScale)*s-sample.position[i]*(1-s));
  const matches=(a,b)=>a.every((v,i)=>Number.isFinite(v) && Math.abs(v-b[i])<1e-6);
  return matches(predictedTarget,sample.target) && matches(predictedEye,sample.eye) ? 1/s-1 : null;
}

export function calibratedCamera(camera, profile, fileID) {
  const positionScale=nativePositionScale(camera,profile,nativeSamples[fileID]);
  return camera && {...camera,positionScale:positionScale ?? 1,
    calibration:positionScale===null ? 'm2' : 'native-capture'};
}

// Run only our own camera modules. Resolve profiles with the addon's function,
// including protected families and model overrides, instead of duplicating it.
export function loadCameraProfiles() {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  try {
    const code = 'WowVoice = {}\n' + ['CameraModels.lua','CameraProfiles.lua']
      .map(name=>fs.readFileSync(new URL(name,source),'utf8')).join('\n') + `
local ids, lines = {[0]=true}, {}
for id in pairs(WowVoice.CameraModelProfiles) do ids[id]=true end
for id in pairs(WowVoice.PortraitCameraOverrides) do ids[id]=true end
for id in pairs(ids) do
    local p, key = WowVoice:GetPortraitCameraProfile({GetModelFileID=function() return id end})
    lines[#lines+1] = table.concat({id, key, p.distance, p.y, p.z}, "|")
end
return table.concat(lines, "\\n")`;
    if (lauxlib.luaL_dostring(L,to_luastring(code)) !== lua.LUA_OK)
      throw Error(to_jsstring(lua.lua_tostring(L,-1)));
    return Object.fromEntries(to_jsstring(lua.lua_tostring(L,-1)).split('\n').map(line=>{
      const [id,key,distance,y,z] = line.split('|');
      return [id,{key,distance:Number(distance),y:Number(y),z:Number(z)}];
    }));
  } finally { lua.lua_close(L); }
}

let profileCache;
export function cameraProfile(fileID) {
  const signature = ['CameraModels.lua','CameraProfiles.lua'].map(name=>{
    const s=fs.statSync(new URL(name,source)); return `${s.mtimeMs}:${s.size}`;
  }).join('|');
  if (profileCache?.signature !== signature) profileCache={signature,profiles:loadCameraProfiles()};
  return profileCache.profiles[fileID] || profileCache.profiles[0];
}

// Modern MD20 data lives inside MD21. Camera type 0 is the portrait; its array
// index is NOT always zero (the dwarf has the full-body camera first).
// Read the first pose of camera tracks, keeping the portrait still during Talk.
export function readPortraitCamera(bytes) {
  let data;
  if (bytes.toString('ascii',0,4)==='MD20') data=bytes;
  else {
    for(let p=0;p+8<=bytes.length;) {
      const size=bytes.readUInt32LE(p+4), end=p+8+size;
      if(end>bytes.length) throw Error('Truncated M2 chunk');
      if(bytes.toString('ascii',p,p+4)==='MD21') { data=bytes.subarray(p+8,end); break; }
      p=end;
    }
  }
  if(!data || data.length<0x118 || data.toString('ascii',0,4)!=='MD20') throw Error('Invalid M2 header');
  const version=data.readUInt32LE(4);
  if(version!==272 && version!==274) throw Error(`Unsupported M2 version ${version}`);
  const check=(offset,size)=>{
    if(!Number.isSafeInteger(offset) || offset<0 || offset+size>data.length) throw Error('Truncated M2 camera');
  };
  const vector=offset=>{check(offset,12);return [0,4,8].map(n=>data.readFloatLE(offset+n));};
  function track(offset,components,fallback) {
    check(offset,20);
    const count=data.readUInt32LE(offset+12), arrays=data.readUInt32LE(offset+16);
    if(!count) return fallback;
    check(arrays,count*8);
    // Sequence zero is Stand for the supported models. Empty tracks are static.
    const keys=data.readUInt32LE(arrays), values=data.readUInt32LE(arrays+4);
    if(!keys) return fallback;
    check(values,components*4);
    return Array.from({length:components},(_,i)=>data.readFloatLE(values+i*4));
  }
  const count=data.readUInt32LE(0x110), offset=data.readUInt32LE(0x114);
  check(offset,count*116);
  for(let i=0;i<count;i++) {
    const p=offset+i*116;
    if(data.readInt32LE(p)!==0) continue;
    const add=(a,b)=>a.map((v,i)=>v+b[i]);
    const camera={position:add(vector(p+32),track(p+12,3,[0,0,0])),
      target:add(vector(p+64),track(p+44,3,[0,0,0])),
      roll:track(p+76,1,[0])[0], fov:track(p+96,1,[NaN])[0],
      near:data.readFloatLE(p+8),far:data.readFloatLE(p+4)};
    if(![...camera.position,...camera.target,camera.roll,camera.fov,camera.near,camera.far].every(Number.isFinite)
      || camera.fov<=0 || camera.fov>=Math.PI || camera.near<=0 || camera.far<=camera.near
      || Math.hypot(...camera.position.map((v,i)=>v-camera.target[i]))<1e-6)
      throw Error('Invalid M2 portrait camera');
    return camera;
  }
  return null;
}

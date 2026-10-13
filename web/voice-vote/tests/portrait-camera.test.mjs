import test from 'node:test';
import assert from 'node:assert/strict';
import {loadCameraProfiles, readPortraitCamera, nativePositionScale, calibratedCamera} from '../portrait-camera.mjs';
import fs from 'node:fs';
import {portraitView} from '../src/portrait-camera.js';

test('addon resolver supplies model overrides, family profiles and the default',()=>{
  const profiles=loadCameraProfiles();
  assert(Object.keys(profiles).length>1200);
  assert.deepEqual(profiles[124495],{key:'human_child_male',distance:1.5,y:.02,z:.04});
  assert.deepEqual(profiles[124456],{key:'human_child_female',distance:1.5,y:.02,z:.015});
  assert.deepEqual(profiles[878772],{key:'dwarf',distance:1.2,y:0,z:.005});
  assert.equal(profiles[1011653].key,'human_male');
  assert.equal(profiles[8125066].key,'model:8125066');
  assert.equal(profiles[0].key,'default');
  assert.equal(profiles[121287].distance,profiles[0].distance);
});

function fixture() {
  const data=Buffer.alloc(768);
  data.write('MD20'); data.writeUInt32LE(272,4);
  data.writeUInt32LE(2,0x110); data.writeUInt32LE(304,0x114);
  data.writeInt32LE(1,304); // Full-body camera comes first.
  const p=420;
  data.writeInt32LE(0,p); data.writeFloatLE(100,p+4); data.writeFloatLE(.1,p+8);
  [2,-1,3].forEach((v,i)=>data.writeFloatLE(v,p+32+i*4));
  [0,0,2].forEach((v,i)=>data.writeFloatLE(v,p+64+i*4));
  // FOV first key: one animation, one sample.
  data.writeUInt32LE(1,p+108);data.writeUInt32LE(600,p+112);
  data.writeUInt32LE(1,600);data.writeUInt32LE(608,604);data.writeFloatLE(Math.PI/4,608);
  const chunk=Buffer.alloc(8);chunk.write('MD21');chunk.writeUInt32LE(data.length,4);
  return {data,chunk:Buffer.concat([chunk,data])};
}

test('portrait camera is selected by type, independently of array order and chunk wrapper',()=>{
  const {data,chunk}=fixture(), camera=readPortraitCamera(chunk);
  assert.deepEqual(camera,readPortraitCamera(data));
  assert.deepEqual(camera.position,[2,-1,3]);
  assert.deepEqual(camera.target,[0,0,2]);
  assert(Math.abs(camera.fov-Math.PI/4)<1e-7);
  data.writeInt32LE(1,420);
  assert.equal(readPortraitCamera(data),null);
});

test('bad or truncated M2 camera data is rejected instead of producing a broken projection',()=>{
  const {data,chunk}=fixture();
  assert.throws(()=>readPortraitCamera(chunk.subarray(0,600)),/Truncated/);
  data.writeUInt32LE(999999,532);
  assert.throws(()=>readPortraitCamera(data),/Truncated/);
  assert.throws(()=>readPortraitCamera(Buffer.alloc(10)),/Invalid/);
});

test('model offsets translate both camera points; zoom changes distance without changing direction',()=>{
  const camera={position:[2,0,3],target:[0,0,3]};
  const matrix=[0,1,0,0,-1,0,0,0,0,0,1,0,0,0,0,1];
  const a=portraitView(camera,{distance:1,y:0,z:0},matrix);
  const b=portraitView(camera,{distance:1.5,y:.02,z:.04},matrix);
  assert.deepEqual(a.target,[0,0,3]);
  assert.deepEqual(b.target,[.02,0,2.96]);
  assert.equal(b.distance,a.distance*1.5);
  assert.equal(b.azimuth,a.azimuth);assert.equal(b.zenith,a.zenith);
});

test('child camera reproduces the measured native eye and target after world-scale conversion',()=>{
  const sample=JSON.parse(fs.readFileSync(new URL('../native-camera-samples.json',import.meta.url),'utf8'))[124495];
  const camera={position:[.3294188678264618,.21204538643360138,1.1642940044403076],
    target:[.02397611178457737,.0014601548900827765,1.1209173202514648]};
  const profile=loadCameraProfiles()[124495];
  const scaled=calibratedCamera(camera,profile,124495);
  assert.equal(scaled.calibration,'native-capture');
  assert(Math.abs(scaled.positionScale-1.5394683426507956)<1e-12);
  const identity=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1];
  const view=portraitView(scaled,profile,identity);
  const eye=[-view.distance*Math.sin(view.zenith)*Math.cos(view.azimuth),
    -view.distance*Math.sin(view.zenith)*Math.sin(view.azimuth),-view.distance*Math.cos(view.zenith)]
    .map((v,i)=>v+view.target[i]);
  for(let i=0;i<3;i++) {
    assert(Math.abs(view.target[i]*sample.worldScale-sample.target[i])<1e-6);
    assert(Math.abs(eye[i]*sample.worldScale-sample.eye[i])<1e-6);
  }
  assert.equal(calibratedCamera(camera,profile,878772).positionScale,1,'do not change the confirmed dwarf');
  assert.equal(nativePositionScale(camera,{...profile,distance:1.7},sample),null,'changed zoom needs another measurement');
  assert.equal(nativePositionScale({...camera,target:[0,0,0]},profile,sample),null,'changed camera data invalidates the capture');
});

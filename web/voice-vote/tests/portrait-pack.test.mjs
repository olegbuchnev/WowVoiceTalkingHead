import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {packPortraitModel,packPortraitSkeleton,chunksOf} from '../portrait-pack.mjs';
import {readPortraitPack} from '../portrait-pack-store.mjs';

function fixture(){
  const data=Buffer.alloc(4096);data.write('MD20');data.writeUInt32LE(274,4);
  let end=320;
  const array=(at,count,stride)=>{const offset=end;end+=count*stride;data.writeUInt32LE(count,at);data.writeUInt32LE(offset,at+4);return offset;};
  const seq=array(28,3,64);
  for(let i=0;i<3;i++){
    const at=seq+64*i;data.writeUInt16LE([0,4,60][i],at);data.writeUInt32LE(1000,at+4);
    data.writeUInt32LE(0x20,at+12);data.writeInt16LE(-1,at+60);
  }
  const bones=array(44,1,88);data.writeInt16LE(-1,bones+8);
  const times=array(bones+20,3,8),values=array(bones+28,3,8);
  for(let i=0;i<3;i++){
    const t=array(times+i*8,1,4);data.writeUInt32LE(0,t);
    const v=array(values+i*8,1,12);data.writeFloatLE([1,9999,3][i],v);
  }
  const vertices=array(60,8,48);for(let i=0;i<8;i++)data.writeFloatLE(i,vertices+i*48);
  const md=data.subarray(0,end),head=Buffer.alloc(8);head.write('MD21');head.writeUInt32LE(md.length,4);
  const sfid=Buffer.alloc(12);sfid.write('SFID');sfid.writeUInt32LE(4,4);sfid.writeUInt32LE(20,8);
  const skin=Buffer.alloc(54);skin.write('SKIN');skin.writeUInt32LE(3,4);skin.writeUInt32LE(48,8);
  skin.writeUInt16LE(0,48);skin.writeUInt16LE(1,50);skin.writeUInt16LE(2,52);
  return {input:Buffer.concat([head,md,sfid]),skin};
}

test('portrait subset preserves quality and talk keys, excludes walk and unused LOD vertices',()=>{
  const {input,skin}=fixture(),before=Buffer.from(input);
  const {bytes,stats}=packPortraitModel(input,skin),md=chunksOf(bytes)[0].bytes;
  assert.deepEqual(input,before,'input stays immutable');
  assert.equal(stats.vertices,3);assert.equal(stats.sourceVertices,8);
  assert.deepEqual(stats.retainedSequences.map(s=>s.id),[0,60]);
  const bone=md.readUInt32LE(48),values=md.readUInt32LE(bone+32);
  assert.equal(md.readFloatLE(md.readUInt32LE(values+4)),1);
  assert.equal(md.readUInt32LE(values+8),0,'walk keys are absent');
  assert.equal(md.readUInt32LE(values+12),0,'walk key pointer is empty');
  assert.equal(md.readFloatLE(md.readUInt32LE(values+20)),3);
  const vertices=md.readUInt32LE(64),source=chunksOf(input)[0].bytes;
  assert.deepEqual(md.subarray(vertices,vertices+3*48),source.subarray(source.readUInt32LE(64),source.readUInt32LE(64)+3*48));
});

test('unsupported and truncated layouts never produce an optimized asset',()=>{
  const {input,skin}=fixture();
  assert.throws(()=>packPortraitModel(input.subarray(0,100),skin),/Truncated/);
  const particles=Buffer.from(input);particles.writeUInt32LE(1,8+296);
  assert.throws(()=>packPortraitModel(particles,skin),/Invalid data range/);
  const badSkin=Buffer.from(skin);badSkin.writeUInt16LE(99,48);
  assert.throws(()=>packPortraitModel(input,badSkin),/missing vertices/);
});

function chunk(tag,bytes){const h=Buffer.alloc(8);h.write(tag);h.writeUInt32LE(bytes.length,4);return Buffer.concat([h,bytes]);}
function skeletonFixture(){
  const {input,skin}=fixture(),md=chunksOf(input)[0].bytes;
  const seq=Buffer.from(md),bones=Buffer.from(md);
  for(const [dst,src]of [[0,20],[8,28],[16,36]])md.copy(seq,dst,src,src+8);
  for(const [dst,src]of [[0,44],[8,52]])md.copy(bones,dst,src,src+8);
  const skeleton=Buffer.concat([chunk('SKS1',seq),chunk('SKB1',bones),chunk('SKA1',Buffer.alloc(16))]);
  const geometry=Buffer.from(md);for(const at of [20,28,36,44,52,240,248])geometry.fill(0,at,at+8);
  const id=Buffer.alloc(4);id.writeUInt32LE(3);
  return {skin,skeleton,input:Buffer.concat([chunk('MD21',geometry),chunk('SFID',chunksOf(input)[1].bytes),chunk('SKID',id)])};
}

test('external skeleton retains stand/talk bones and original sequence indices',()=>{
  const {input,skin,skeleton}=skeletonFixture();
  const before=Buffer.from(skeleton),pack=packPortraitModel(input,skin,skeleton);
  assert.deepEqual(skeleton,before);
  assert.equal(pack.stats.vertices,3);
  assert.equal(pack.skeleton.file,'3.skel');
  assert.deepEqual(pack.stats.retainedSequences.map(s=>s.id),[0,60]);
  const bones=chunksOf(pack.skeleton.bytes).find(c=>c.tag==='SKB1').bytes;
  const at=bones.readUInt32LE(4),values=bones.readUInt32LE(at+32);
  assert.equal(bones.readFloatLE(bones.readUInt32LE(values+4)),1);
  assert.equal(bones.readUInt32LE(values+8),0);
  assert.equal(bones.readFloatLE(bones.readUInt32LE(values+20)),3);
  assert.throws(()=>packPortraitModel(input,skin),/External skeleton/);
  assert.throws(()=>packPortraitSkeleton(Buffer.concat([skeleton,chunk('SKPD',Buffer.alloc(16))])),/Parent/);
});

test('geometry and external skeleton fail back together when either source or pack changes',async()=>{
  const root=await fs.mkdtemp(path.join(os.tmpdir(),'portrait-skeleton-'));
  const hash=b=>createHash('sha256').update(b).digest('hex');
  const {input,skin,skeleton}=skeletonFixture(),pack=packPortraitModel(input,skin,skeleton),viewer=Buffer.from('viewer');
  const files={
    'modelviewer/classicplus/m2/1.m2':input,'modelviewer/classicplus/skin/20.skin':skin,
    'modelviewer/classicplus/skel/3.skel':skeleton,'modelviewer/live/viewer/viewer.min.js':viewer,
    'portrait-packs-v1/1.m2':pack.bytes,'portrait-packs-v1/skel/3.skel':pack.skeleton.bytes,
    'portrait-packs-v1/verification.json':JSON.stringify({version:1,failed:[],viewerSha256:hash(viewer),verified:[{
      file:'1.m2',sourceSha256:hash(input),sha256:hash(pack.bytes),skinSha256:hash(skin),
      skeleton:{file:'3.skel',sourceSha256:hash(skeleton),sha256:hash(pack.skeleton.bytes)},
    }]}),
  };
  try {
    for(const [name,bytes]of Object.entries(files)){await fs.mkdir(path.dirname(path.join(root,name)),{recursive:true});await fs.writeFile(path.join(root,name),bytes);}
    assert.deepEqual(await readPortraitPack(root,'1.m2'),pack.bytes);
    assert.deepEqual(await readPortraitPack(root,'3.skel'),pack.skeleton.bytes);
    for(const name of ['modelviewer/classicplus/skel/3.skel','portrait-packs-v1/skel/3.skel','portrait-packs-v1/1.m2']) {
      await fs.appendFile(path.join(root,name),'changed');
      assert.equal(await readPortraitPack(root,'1.m2'),null,name);
      assert.equal(await readPortraitPack(root,'3.skel'),null,name);
      await fs.writeFile(path.join(root,name),files[name]);
    }
  } finally {await fs.rm(root,{recursive:true,force:true});}
});

test('pack serving verifies source, skin, viewer and derived bytes; mismatch falls back',async()=>{
  const root=await fs.mkdtemp(path.join(os.tmpdir(),'portrait-pack-'));
  const hash=b=>createHash('sha256').update(b).digest('hex');
  const {input,skin}=fixture(),packed=packPortraitModel(input,skin).bytes,viewer=Buffer.from('test viewer');
  const files={
    'modelviewer/classicplus/m2/1.m2':input,'modelviewer/classicplus/skin/20.skin':skin,
    'modelviewer/live/viewer/viewer.min.js':viewer,'portrait-packs-v1/1.m2':packed,
  };
  try{
    for(const [name,bytes]of Object.entries(files)){await fs.mkdir(path.dirname(path.join(root,name)),{recursive:true});await fs.writeFile(path.join(root,name),bytes);}
    assert.equal(await readPortraitPack(root,'1.m2'),null,'unverified pack is not served');
    const manifest={version:1,viewerSha256:hash(viewer),failed:[],verified:[{file:'1.m2',sha256:hash(packed),sourceSha256:hash(input),skinSha256:hash(skin)}]};
    await fs.writeFile(path.join(root,'portrait-packs-v1/verification.json'),JSON.stringify(manifest));
    assert.deepEqual(await readPortraitPack(root,'1.m2'),packed);
    assert.deepEqual(await readPortraitPack(root,'1.m2'),packed,'reuse validation');
    await fs.appendFile(path.join(root,'modelviewer/classicplus/skin/20.skin'),'changed');
    assert.equal(await readPortraitPack(root,'1.m2'),null,'updated base skin invalidates pack');
    await fs.writeFile(path.join(root,'modelviewer/classicplus/skin/20.skin'),skin);
    assert.deepEqual(await readPortraitPack(root,'1.m2'),packed);
    await fs.appendFile(path.join(root,'portrait-packs-v1/1.m2'),'corrupt');
    assert.equal(await readPortraitPack(root,'1.m2'),null,'tampered pack is not served');
    await fs.writeFile(path.join(root,'portrait-packs-v1/1.m2'),packed);
    await fs.appendFile(path.join(root,'modelviewer/classicplus/m2/1.m2'),'new source');
    assert.equal(await readPortraitPack(root,'1.m2'),null,'new source requires new verification');
    await assert.rejects(readPortraitPack(root,'../secret'),/Invalid/);
  }finally{await fs.rm(root,{recursive:true,force:true});}
});

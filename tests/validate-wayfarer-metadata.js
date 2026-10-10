const assert = require('assert/strict');
const fs = require('fs'), os = require('os'), path = require('path');
const {generate,readPack} = require('../tools/generate-wayfarer-metadata');
const {duration} = require('../tools/import-forever-audio');
const root=fs.mkdtempSync(path.join(os.tmpdir(),'wayfarer-metadata-'));
try {
  const name='Wayfarer_Voices_Alliance', dir=path.join(root,'input',name), output=path.join(root,'output');
  fs.mkdirSync(path.join(dir,'q'),{recursive:true});
  fs.writeFileSync(path.join(dir,name+'.toc'),'## Version: 3.1.0\n');
  const index='Wayfarer.RegisterPack({name="'+name+'",format=1,version="3.1.0",model="v4",q={[5]={a={m=1,f=2,v="Голос",s=7}},[6]={c={d=3}}}})';
  fs.writeFileSync(path.join(dir,'Index.lua'),index);
  const sample=fs.readFileSync(path.join(__dirname,'../soundpack/179a.ogg'));
  for(const file of ['5-a-m.ogg','5-a-f.ogg','6-c.ogg']) fs.writeFileSync(path.join(dir,'q',file),sample);
  assert.equal(readPack(Buffer.from(index)).q[5].a.v,'Голос');
  const result=generate(path.join(root,'input'),output);
  assert.equal(result.mainDescriptions,1);
  assert.equal(result.packs[name].files,3);
  const manifest=JSON.parse(fs.readFileSync(path.join(output,'docs/internal/wayfarer-audio-manifest.json')));
  assert.equal(manifest.packs[name].files['q/5-a-f.ogg'].duration,duration(sample));
  assert.equal(manifest.packs[name].files['q/5-a-f.ogg'].indexDuration,2);
  const target=path.join(output,'src/WayfarerAudio.lua'), before=fs.readFileSync(target);
  fs.writeFileSync(path.join(dir,'q/5-a-m.ogg'),'broken');
  assert.throws(()=>generate(path.join(root,'input'),output),/OGG/);
  assert.deepEqual(fs.readFileSync(target),before,'Failed audit must preserve previous runtime metadata');
  assert.throws(()=>readPack(Buffer.from(index.replace('m=1','m=os.execute("bad")'))),/Unsupported/);
  assert.throws(()=>readPack(Buffer.from(index.replace('m=1','m=1,m=2'))),/Duplicate/);
  console.log('PASS: Wayfarer data-only parser, unique descriptions, per-variant OGG timing, hashes, and failed-audit preservation');
} finally {fs.rmSync(root,{recursive:true,force:true});}

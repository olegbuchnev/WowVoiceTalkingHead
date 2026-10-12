import test from 'node:test';
import assert from 'node:assert/strict';
import {audioRange, buildCatalogue, readVerifiedAudio, demoIDs} from '../server.mjs';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {createHash} from 'node:crypto';
import {exportVoteCatalogue, revisionHashes} from '../export-vote-catalogue.mjs';
import historyTools from '../../../tools/audio-recording-history.js';

test('OGG range requests, suffixes and invalid ranges', () => {
  assert.deepEqual(audioRange(null,100),{start:0,end:99,partial:false});
  assert.deepEqual(audioRange('bytes=10-19',100),{start:10,end:19,partial:true});
  assert.deepEqual(audioRange('bytes=90-',100),{start:90,end:99,partial:true});
  assert.deepEqual(audioRange('bytes=-10',100),{start:90,end:99,partial:true});
  for(const range of ['bytes=100-','bytes=30-20','bytes=-0','bytes=0-1,3-4','not-a-range']) assert.equal(audioRange(range,100),null);
});

test('explicit description narrator exports no receiving NPC or race/sex', async()=>{
  const {catalogue}=buildCatalogue(undefined,{questIDs:[98247,98248]});
  assert.equal(catalogue.quests.length,2);
  for(const quest of catalogue.quests) {
    assert.deepEqual(quest.npc,{id:0,displayID:0,race:null,sex:null,name:'Рассказчик'});
    assert.equal(quest.variants.length,2,'Narration still participates in quest voting');
  }
});

test('audio delivery rejects changed bytes even when the file size is unchanged', async()=>{
  const directory=await fs.mkdtemp(path.join(os.tmpdir(),'voice-vote-audio-'));
  const file=path.join(directory,'fixture.bin');
  try {
    const bytes=Buffer.from('original fixture');
    const sha256=createHash('sha256').update(bytes).digest('hex');
    await fs.writeFile(file,bytes);
    assert.deepEqual(await readVerifiedAudio(file,sha256),bytes);
    await fs.writeFile(file,Buffer.alloc(bytes.length,1));
    await assert.rejects(readVerifiedAudio(file,sha256),error=>error.status===409);
  } finally {await fs.unlink(file);await fs.rmdir(directory);}
});

test('export produces deterministic portable metadata without audio paths or files',async()=>{
  const directory=await fs.mkdtemp(path.join(os.tmpdir(),'voice-vote-catalogue-'));
  const file=path.join(directory,'catalogue.json');
  try {
    const snapshot=await exportVoteCatalogue(file,{questIDs:demoIDs});
    const original=await fs.readFile(file,'utf8');
    assert.equal(snapshot.schemaVersion,2);
    assert.equal(snapshot.quests.length,3);
    for(const quest of snapshot.quests) {
      assert(quest.npc.modelFileID>0);
      for(const variant of quest.variants) {
        assert.deepEqual(Object.keys(variant).sort(),['id','pack','revisions','sha256','source','version']);
        assert.match(variant.sha256,/^[a-f0-9]{64}$/);
        assert(variant.revisions.includes(variant.sha256));
        assert(variant.revisions.length>=1 && variant.revisions.length<=3);
      }
    }
    assert(!original.includes('audioFile'));
    assert(!/[A-Za-z]:[\\/]/.test(original));
    await exportVoteCatalogue(file,{questIDs:demoIDs});
    assert.equal(await fs.readFile(file,'utf8'),original);
    assert.deepEqual(await fs.readdir(directory),['catalogue.coverage.json','catalogue.json']);
  } finally {await fs.unlink(file);await fs.unlink(path.join(directory,'catalogue.coverage.json'));await fs.rmdir(directory);}
});

test('prototype reads real, hash-verified descriptions with distinct sources and NPC identity', () => {
  const {catalogue,audio} = buildCatalogue(undefined,{questIDs:demoIDs});
  assert.equal(catalogue.quests.length,3);
  assert.equal(catalogue.warnings.length,0);
  for(const quest of catalogue.quests) {
    assert(quest.text.length > 20 && quest.npc.displayID && quest.npc.race && quest.npc.sex);
    assert(quest.variants.length >= 2);
    assert.equal(new Set(quest.variants.map(v=>v.source)).size,quest.variants.length);
    for(const v of quest.variants) {
      assert.match(v.sha256,/^[a-f0-9]{64}$/);
      assert(v.version && v.duration > 0 && audio.has(v.id));
      assert(!JSON.stringify(v).includes('C:\\'), 'Do not expose local filesystem paths');
    }
  }
  assert.equal(audio.get('../../config/build.env.local.ps1'),undefined);
});

test('catalogue exports three distinct per-file revisions, independent of release count',()=>{
  const pack='CatQuest_Voices', file='1479_m.ogg', hash=n=>String(n).repeat(64);
  let history=null;
  for(const [version,n] of [['1',1],['2',1],['3',2],['4',3],['5',4]]) {
    history=historyTools.update(history,[{pack,version,files:[{file,sha256:hash(n),bytes:100,duration:20}]}]);
  }
  assert.deepEqual(revisionHashes(history,{pack,file,sha256:hash(4)}),[hash(4),hash(3),hash(2)]);
  assert.equal(history.packs[pack].recordings[file].revisions.length,4,'older metadata remains archived');
  assert.throws(()=>revisionHashes(history,{pack,file,sha256:hash(1)}),/outside the audited history window/);
  history=historyTools.update(history,[{pack,version:'6',files:[{file,sha256:hash(1),bytes:100,duration:20}]}]);
  assert.deepEqual(revisionHashes(history,{pack,file,sha256:hash(1)}),[hash(1),hash(4),hash(3)]);
});

test('full catalogue includes only descriptions, two-source comparisons and quests without a known speaker',async()=>{
  const {catalogue,audio}=buildCatalogue();
  const history=JSON.parse(await fs.readFile(new URL('../../../docs/internal/audio-recording-history.json',import.meta.url),'utf8'));
  assert(catalogue.quests.length>3000);
  assert.equal(catalogue.warnings.length,0);
  assert.equal(new Set(catalogue.quests.map(q=>q.questID)).size,catalogue.quests.length);
  assert(catalogue.quests.some(q=>q.variants.length===2));
  assert(catalogue.quests.some(q=>q.variants.length===3));
  assert(catalogue.quests.some(q=>q.npc.id>0 && !q.npc.race));
  const unknown=catalogue.quests.find(q=>q.questID===2);
  assert.equal(unknown.npc.id,0);
  assert.equal(unknown.npc.race,null);
  assert.equal(unknown.npc.sex,null);
  for(const quest of catalogue.quests) {
    assert(quest.text.trim().length>0);
    assert(quest.variants.length>=2 && quest.variants.length<=3);
    assert.equal(new Set(quest.variants.map(v=>v.source)).size,quest.variants.length);
    for(const variant of quest.variants) {
      assert(audio.has(variant.id));
      const recording=history.packs[variant.pack].recordings[variant.file];
      assert.equal(recording.questID,quest.questID);
      assert.equal(recording.section,'a');
    }
  }
});

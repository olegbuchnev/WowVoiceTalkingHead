const assert = require('assert/strict');
const fs = require('fs'), path = require('path'), os = require('os');
const {collect} = require('../tools/import-forever-pins-speakers');
const directory = fs.mkdtempSync(path.join(os.tmpdir(),'talkinghead-pins-'));
const commit = 'a'.repeat(40);
function fixture(records, extra = '', source = 'QuestieDB-Forever') {
  fs.writeFileSync(path.join(directory,'Metadata.lua'), `ns.Metadata={source="${source}",contractVersion=4,
    questCount=4,turnInCount=3,artifactCommit="${commit}",artifactSHA256="${'b'.repeat(64)}",policyCommit="${commit}"${extra}}`);
  fs.writeFileSync(path.join(directory,'ForeverQuests.lua'), `ns.Quests={${records}}`);
}
const records = '[1]={qg=10,turnIns={20}},[2]={qgs={11,12},turnIns={21,22}},[3]={turnInObjects={30}},[4]={}';
try {
  fixture(records);
  const result = collect(directory,commit);
  assert.deepEqual(result.givers, {1:10,2:false});
  assert.deepEqual(result.finishers, {1:20,2:false,3:false});
  assert.equal(result.contractVersion,4);
  assert.equal(result.artifactCommit,commit);
  fixture(records, ',contractVersion=5');
  assert.throws(()=>collect(directory,commit),/schema/);
  fixture(records, ',turnInCount=4');
  assert.throws(()=>collect(directory,commit),/turn-in count/);
  fixture(records.replace('qg=10','qg=-10'));
  assert.throws(()=>collect(directory,commit),/Invalid Pins ID/);
  fixture(records.replace('turnIns={20}','turnIns={false}'));
  assert.throws(()=>collect(directory,commit),/Invalid Pins ID/);
  fixture(records.replace('qg=10','qg=10,qgs={12}'));
  assert.equal(collect(directory,commit).givers[1],false);
  fixture(records, '', 'unknown');
  assert.throws(()=>collect(directory,commit),/schema/);
  fixture(records, '', 'ATTWoWAddon/AllTheThings');
  assert.equal(collect(directory,commit).finishers,undefined);
  console.log('PASS: Pins v4 provenance, separate giver/finisher NPCs, object namespace, ambiguity, invalid contracts and legacy ATT');
} finally {
  assert.equal(path.dirname(directory),path.resolve(os.tmpdir()));
  assert(path.basename(directory).startsWith('talkinghead-pins-'));
  fs.rmSync(directory,{recursive:true,force:true});
}

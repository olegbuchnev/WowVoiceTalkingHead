// Install only offline-verified derivatives. Never overwrite original assets.
import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash,randomUUID} from 'node:crypto';
import {chunksOf} from './portrait-pack.mjs';

const root=path.resolve(import.meta.dirname,'../..');
const option=(name,fallback)=>process.argv.find(a=>a.startsWith(`--${name}=`))?.slice(name.length+3)||fallback;
const prepared=path.resolve(option('prepared',path.join(root,'artifacts/portrait-packs')));
const cache=path.resolve(option('cache',process.env.VOICE_VOTE_MODEL_CACHE||path.join(root,'artifacts/voice-vote-model-cache')));
const destination=path.join(cache,'portrait-packs-v1');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const manifest=await fs.readFile(path.join(prepared,'verification.json'));
const report=JSON.parse(manifest);
if(report.version!==1||report.failed?.length||!report.verified?.length)throw Error('A successful offline verification report is required');
if(digest(await fs.readFile(path.join(cache,'modelviewer/live/viewer/viewer.min.js')))!==report.viewerSha256)throw Error('Viewer changed after verification');
if(digest(await fs.readFile(new URL('./portrait-pack.mjs',import.meta.url)))!==report.packerSha256)throw Error('Packer changed after verification');
await fs.mkdir(destination,{recursive:true});
let total=0;
for(const row of report.verified){
  if(!/^\d+\.m2$/.test(row.file))throw Error('Invalid model filename');
  const [source,packed]=await Promise.all([
    fs.readFile(path.join(cache,'modelviewer/classicplus/m2',row.file)),fs.readFile(path.join(prepared,row.file))]);
  const skinID=chunksOf(source).find(c=>c.tag==='SFID').bytes.readUInt32LE();
  const skin=await fs.readFile(path.join(cache,'modelviewer/classicplus/skin',`${skinID}.skin`));
  if(digest(source)!==row.sourceSha256||digest(packed)!==row.sha256||digest(skin)!==row.skinSha256)throw Error(`Asset changed after verification: ${row.file}`);
  const temporary=path.join(destination,`${row.file}.${randomUUID()}.tmp`);
  await fs.writeFile(temporary,packed);await fs.rename(temporary,path.join(destination,row.file));total+=packed.length;
}
// Publish the manifest last. Concurrent mismatches use the original model.
const temporary=path.join(destination,`manifest.${randomUUID()}.tmp`);
await fs.writeFile(temporary,manifest);await fs.rename(temporary,path.join(destination,'verification.json'));
console.log(`Installed ${report.verified.length} verified models (${total} bytes) in ${destination}. ${report.unsupported.length} models retain their source assets.`);

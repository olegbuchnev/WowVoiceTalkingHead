import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';

const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const checks=new Map();
const signature=stat=>`${stat.size}:${stat.mtimeMs}:${stat.ctimeMs}`;

// Packs are generated and verified offline. No binary conversion on a request.
// A changed source, base skin or pack falls back to the immutable source cache.
export async function readPortraitPack(cacheRoot,file) {
  if(!/^\d+\.(m2|skel)$/.test(file))throw Error('Invalid portrait pack name');
  const directory=path.join(cacheRoot,'portrait-packs-v1');
  const manifestPath=path.join(directory,'verification.json');
  try {
    const report=JSON.parse(await fs.readFile(manifestPath,'utf8'));
    if(report.version!==1||report.failed?.length) return null;
    const isSkeleton=file.endsWith('.skel');
    const entry=report.verified?.find(row=>isSkeleton ? row.skeleton?.file===file : row.file===file);
    if(!entry)return null;
    const sourcePath=path.join(cacheRoot,'modelviewer/classicplus/m2',entry.file);
    const modelPath=path.join(directory,entry.file);
    const packedPath=isSkeleton ? path.join(directory,'skel',file) : modelPath;
    const skeletonPaths=entry.skeleton ? [path.join(cacheRoot,'modelviewer/classicplus/skel',entry.skeleton.file),path.join(directory,'skel',entry.skeleton.file)] : [];
    const viewerPath=path.join(cacheRoot,'modelviewer/live/viewer/viewer.min.js');
    const stats=await Promise.all([manifestPath,sourcePath,modelPath,viewerPath,...skeletonPaths].map(p=>fs.stat(p)));
    const key=`${directory}/${file}`,stamp=stats.map(signature).join('|');
    let check=checks.get(key);
    if(check?.stamp!==stamp){
      const promise=(async()=>{
        const [source,packed,viewer,...skeletons]=await Promise.all([sourcePath,modelPath,viewerPath,...skeletonPaths].map(p=>fs.readFile(p)));
        if(digest(source)!==entry.sourceSha256||digest(packed)!==entry.sha256||digest(viewer)!==report.viewerSha256)return null;
        if(entry.skeleton&&(digest(skeletons[0])!==entry.skeleton.sourceSha256||digest(skeletons[1])!==entry.skeleton.sha256))return null;
        // Locate SFID without importing the build-time binary optimizer.
        let skinID;
        for(let p=0;p+8<=source.length;){
          const size=source.readUInt32LE(p+4);
          if(p+8+size>source.length)return null;
          if(source.toString('ascii',p,p+4)==='SFID'&&size>=4)skinID=source.readUInt32LE(p+8);
          p+=8+size;
        }
        if(!skinID)return null;
        const skinPath=path.join(cacheRoot,'modelviewer/classicplus/skin',`${skinID}.skin`);
        const skin=await fs.readFile(skinPath);
        if(digest(skin)!==entry.skinSha256)return null;
        return {skinPath,skinStamp:signature(await fs.stat(skinPath))};
      })();
      check={stamp,promise};checks.set(key,check);
    }
    const valid=await check.promise;
    if(!valid)return null;
    if(signature(await fs.stat(valid.skinPath))!==valid.skinStamp){checks.delete(key);return null;}
    return await fs.readFile(packedPath);
  }catch(error){
    if(error.code!=='ENOENT')console.warn(`Portrait pack unavailable (${file}): ${error.message}`);
    return null;
  }
}

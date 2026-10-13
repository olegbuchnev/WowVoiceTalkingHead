import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';

export const modelHash=bytes=>createHash('sha256').update(bytes).digest('hex');
export const viewerPath='/modelviewer/live/viewer/viewer.min.js';
export const viewerStylePath='/modelviewer/viewer/viewer.css';
export function matchesETag(header,etag) {
  return (header || '').split(',').some(tag=>tag.trim()==='*' || tag.trim().replace(/^W\//,'')===etag);
}

export function sendModelAsset(req,res,url,bytes,mime,timings={}) {
  const hash=modelHash(bytes),version=url.searchParams.get('v');
  // Never return new bytes under an old immutable URL, even during deploy.
  if(version!==null && version!==hash) {
    res.writeHead(410,{'Cache-Control':'no-store'}).end();return;
  }
  const etag=`"${hash}"`,headers={'Content-Type':mime,'Cache-Control':version ? 'public, max-age=31536000, immutable' : 'no-cache',
    'ETag':etag,'Server-Timing':`read;dur=${timings.readMs || 0}`};
  if(matchesETag(req.headers['if-none-match'],etag)) res.writeHead(304,headers).end();
  else res.writeHead(200,headers).end(req.method==='HEAD' ? undefined : bytes);
}

// Only the small dependency list for this portrait is sent to the browser.
// Hash the bytes actually served, including verified packs and viewer adapters.
export function createModelVersions({cacheRoot,readAsset}) {
  let stamp,manifest;
  return async displayID=>{
    const file=path.join(cacheRoot(),'manifest.json'),stat=await fs.stat(file);
    const current=`${stat.size}:${stat.mtimeMs}:${stat.ctimeMs}`;
    if(current!==stamp) {
      manifest=JSON.parse(await fs.readFile(file,'utf8'));stamp=current;
    }
    const portrait=manifest.portraits?.[displayID];
    if(!portrait?.files?.length) throw Error('Portrait dependency manifest unavailable');
    const paths=new Set([viewerPath,viewerStylePath,...portrait.files.map(f=>f.url)]);
    const assets={};
    for(const source of paths) {
      const url=source.replace('/modelviewer/classicplus/','/modelviewer/portrait-v1/classicplus/');
      assets[url]=modelHash(await readAsset(url));
    }
    return {assets};
  };
}

// Keep the adapter scoped to the audited viewer. Do not replace browser fetch
// or XMLHttpRequest globally. Metadata/bone requests use a scoped jQuery filter.
export function adaptViewerAssetURLs(bytes) {
  let script=bytes.toString('utf8');
  for(const [before,after] of [
    ['n=yield fetch(e);if(!n.ok)', 'n=yield fetch(WH.modelAssetURL?.(e) || e);if(!n.ok)'],
    ['const e=yield fetch(t);if(!e.ok)', 'const e=yield fetch(WH.modelAssetURL?.(t) || t);if(!e.ok)'],
    ['n.open("GET",e,!0)', 'n.open("GET",WH.modelAssetURL?.(e) || e,!0)'],
    ['href="/modelviewer/viewer/viewer.css"', 'href="\'+(WH.modelAssetURL?.("/modelviewer/viewer/viewer.css") || "/modelviewer/viewer/viewer.css")+\'"'],
  ]) {
    if(script.split(before).length!==2) throw Error('Viewer transport changed: review model cache adapter');
    script=script.replace(before,after);
  }
  return Buffer.from(script);
}

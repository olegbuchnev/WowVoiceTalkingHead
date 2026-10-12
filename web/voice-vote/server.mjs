import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import {cameraProfile, readPortraitCamera, calibratedCamera} from './portrait-camera.mjs';
import {adaptViewerLighting} from './viewer-lighting.mjs';
import {createDiagnosticsHandler} from './diagnostics.mjs';
import {readPortraitPack} from './portrait-pack-store.mjs';

const require = createRequire(import.meta.url);
const { dataTable } = require('../../tools/import-forever-audio.js');
export const repo = fileURLToPath(new URL('../../', import.meta.url));
export const demoIDs = [179, 3741, 7];
const json = name => JSON.parse(fs.readFileSync(path.join(repo, 'docs/internal', name), 'utf8'));
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
export function addonsDirectory() {
  const config = path.join(repo, 'config/build.env.local.ps1');
  const local = fs.existsSync(config) && /\$env:WOWVOICE_FOREVER_BETA_ADDONS\s*=\s*'([^']+)'/.exec(fs.readFileSync(config, 'utf8'))?.[1];
  const directory = local || process.env.WOWVOICE_FOREVER_BETA_ADDONS;
  if (!directory || !fs.existsSync(directory)) throw Error('Укажите папку AddOns в config/build.env.local.ps1 или WOWVOICE_FOREVER_BETA_ADDONS.');
  return directory;
}

export function buildCatalogue(addons = addonsDirectory(), {questIDs} = {}) {
  const speakers = dataTable(path.join(repo, 'src/Speakers.lua'));
  const texts = dataTable(path.join(repo, 'src/QuestTexts.lua')).entries;
  const cat = dataTable(path.join(repo, 'src/CatQuestAudio.lua'));
  const way = dataTable(path.join(repo, 'src/WayfarerAudio.lua')).packs;
  const classic = json('classic-audio-manifest.json'), cm = json('forever-audio-manifest.json'), wm = json('wayfarer-audio-manifest.json');
  const audio = new Map(), quests = [], warnings = [];
  const classicFiles = new Map(classic.files.map(f=>[f.file,f]));
  const catFiles = new Map(cm.files.map(f=>[f.file,f]));
  const candidates = new Map();
  function addCandidate(id, source) {
    if (!candidates.has(id)) candidates.set(id,new Set());
    candidates.get(id).add(source);
  }
  for (const file of classicFiles.keys()) {
    const match=/^(\d+)a\.ogg$/.exec(file);
    if(match) addCandidate(Number(match[1]),'WowVoice');
  }
  for (const [source,entries] of [['CatQuest',cat.entries],...Object.values(way).map(p=>['Wayfarer',p.entries])]) {
    for(const key of Object.keys(entries)) {
      const match=/^(\d+)a$/.exec(key);
      if(match) addCandidate(Number(match[1]),source);
    }
  }
  function option(source, pack, version, file, entry, subdir = '') {
    if (!file || !entry) return;
    const absolute = path.join(addons, pack, subdir, file);
    if (!fs.existsSync(absolute)) return;
    // A sample must really be the version advertised by our metadata.
    const bytes = fs.readFileSync(absolute);
    if (digest(bytes) !== entry.sha256) { warnings.push(`${pack}/${file}: запись обновлена, нужен импорт метаданных.`); return; }
    const id = digest(`${pack}/${file}/${entry.sha256}`).slice(0, 24);
    audio.set(id, absolute);
    return { id, source, pack, version, file, sha256: entry.sha256, duration: entry.duration, url: `/api/audio/${id}` };
  }
  const ids=questIDs ?? [...candidates].filter(([,sources])=>sources.size>=2).map(([id])=>id).sort((a,b)=>a-b);
  for (const questID of ids) {
    const giver = speakers.givers[questID], npc = speakers.npcs[giver?.npcID];
    const file = `${questID}a.ogg`, cf = cat.entries[`${questID}a`]?.audio;
    const catFile = cf?.file || cf?.male?.file;
    const variants = [option('WowVoice', 'WowVoiceSounds', classic.version, file, classicFiles.get(file)),
      option('CatQuest', 'CatQuest_Voices', cm.version, catFile, catFiles.get(catFile), 'Sounds/q')];
    for (const [pack, data] of Object.entries(way)) {
      const recording = data.entries[`${questID}a`]?.audio;
      const chosen = recording?.d || recording?.m;
      if (chosen) {
        const variant=option('Wayfarer', pack, data.version, chosen.file, wm.packs[pack]?.files[chosen.file]);
        if(variant) {variants.push(variant);break;}
      }
    }
    const available = variants.filter(Boolean);
    if (available.length < 2) continue;
    // A blocked/ambiguous giver must never inherit an arbitrary NPC's identity.
    quests.push({ questID, npc: { id:giver?.npcID || 0, displayID:npc?.displayID || 0,
      race:npc?.race || null, sex:npc?.sex || null, name:giver?.narrator ? 'Рассказчик' : npc?.name || giver?.name || '' },
      text: texts[`${questID}a`]?.common || texts[`${questID}a`]?.male || '', variants:available });
  }
  return { catalogue: { app:'talkinghead-voice-vote', quests, warnings }, audio };
}

export function audioRange(header, size) {
  if (!header) return { start:0, end:size - 1, partial:false };
  const m = /^bytes=(\d*)-(\d*)$/.exec(header);
  if (!m || (!m[1] && !m[2])) return null;
  const start = m[1] ? Number(m[1]) : Math.max(0, size - Number(m[2]));
  const end = m[1] ? (m[2] ? Math.min(size - 1, Number(m[2])) : size - 1) : size - 1;
  return Number.isSafeInteger(start) && Number.isSafeInteger(end) && start <= end && start < size
    ? { start, end, partial:true } : null;
}

export async function readVerifiedAudio(file, sha256) {
  const bytes = await fs.promises.readFile(file);
  if (digest(bytes) !== sha256) {
    const error = Error('Audio has changed. Refresh the catalogue and reload the page.');
    error.status = 409;
    throw error;
  }
  return bytes;
}

const downloads = new Map();
export async function modelAsset(urlPath, timings) {
  const portraitAsset=urlPath.startsWith('/modelviewer/portrait-v1/classicplus/');
  if(portraitAsset)urlPath=urlPath.replace('/modelviewer/portrait-v1/','/modelviewer/');
  const viewerScript = urlPath === '/modelviewer/live/viewer/viewer.min.js';
  const viewerStyle = urlPath === '/modelviewer/viewer/viewer.css';
  const foreverAsset = /^\/modelviewer\/classicplus\/[a-zA-Z0-9_./-]+$/.test(urlPath);
  if ((!viewerScript && !viewerStyle && !foreverAsset) || urlPath.includes('..')) throw Error('Invalid model path');
  const cacheRoot=process.env.VOICE_VOTE_MODEL_CACHE || path.join(repo, 'artifacts/voice-vote-model-cache');
  const cache = path.join(cacheRoot, urlPath.slice(1));
  if(portraitAsset&&/^\/modelviewer\/classicplus\/m2\/\d+\.m2$/.test(urlPath)){
    const started=performance.now(),packed=await readPortraitPack(cacheRoot,path.basename(urlPath));
    if(timings)timings.portraitPack=!!packed;
    if(packed){if(timings)timings.readMs=Number((performance.now()-started).toFixed(2));return packed;}
  }
  if (fs.existsSync(cache)) {
    const started=performance.now();
    const bytes=await fs.promises.readFile(cache);
    if(timings) timings.readMs=Number((performance.now()-started).toFixed(2));
    return bytes;
  }
  if (process.env.VOICE_VOTE_MODEL_OFFLINE === 'true') throw Error(`Model asset missing from offline cache: ${urlPath}`);
  if (!downloads.has(urlPath)) downloads.set(urlPath, (async () => {
    const response = await fetch(`https://wow.zamimg.com${urlPath}`, { signal:AbortSignal.timeout(30000) });
    if (!response.ok) throw Error(`Model service: HTTP ${response.status}`);
    const bytes = Buffer.from(await response.arrayBuffer());
    if (bytes.length > 50 * 1024 * 1024) throw Error('Model asset too large');
    fs.mkdirSync(path.dirname(cache), {recursive:true});
    const temporary = `${cache}.${crypto.randomUUID()}.tmp`;
    fs.writeFileSync(temporary, bytes);
    fs.renameSync(temporary, cache);
    return bytes;
  })().finally(() => downloads.delete(urlPath)));
  return downloads.get(urlPath);
}

export function localApi(options = {}) {
  const diagnostics=createDiagnosticsHandler();
  let data,catalogueBody,catalogueETag;
  const catalogue=()=>data ||= options.loadData ? options.loadData() : buildCatalogue(undefined,options);
  return async (req, res, next) => {
    const url = new URL(req.url, 'http://localhost');
    if(url.pathname==='/api/diagnostics/portrait') return diagnostics(req,res);
    if (url.pathname === '/api/votes' || url.pathname.startsWith('/api/votes/')) return next();
    if (!url.pathname.startsWith('/api/') && !url.pathname.startsWith('/modelviewer/')) return next();
    if (!['GET','HEAD'].includes(req.method)) { res.writeHead(405).end(); return; }
    const started=performance.now(),timings={};
    const requestID=/^[a-f0-9]{32}$/.test(req.headers['x-request-id'] || '') ? req.headers['x-request-id'] : crypto.randomBytes(16).toString('hex');
    const measured=/^\/modelviewer\/.*\.(m2|skel)$/.test(url.pathname) || url.pathname.startsWith('/api/portrait-camera/');
    if(measured) res.once('finish',()=>console.log(JSON.stringify({event:'asset_server',time:new Date().toISOString(),requestID,path:url.pathname,status:res.statusCode,...timings,totalMs:Number((performance.now()-started).toFixed(2))})));
    try {
      if (url.pathname === '/api/catalogue') {
        data = catalogue();
        catalogueBody ||= JSON.stringify(data.catalogue);
        catalogueETag ||= `"${crypto.createHash('sha256').update(catalogueBody).digest('hex')}"`;
        const headers={'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-cache','ETag':catalogueETag};
        // Gzip proxies can weaken our ETag. GET/HEAD use weak comparison.
        const matches=(req.headers['if-none-match'] || '').split(',')
          .some(tag=>tag.trim()==='*' || tag.trim().replace(/^W\//,'')===catalogueETag);
        if(matches) {res.writeHead(304,headers).end();return;}
        res.writeHead(200,headers);
        res.end(req.method==='HEAD' ? undefined : catalogueBody);
      } else if (/^\/api\/portrait-camera\/[1-9]\d{0,9}$/.test(url.pathname)) {
        const fileID = Number(url.pathname.split('/').at(-1));
        const bytes = await modelAsset(`/modelviewer/classicplus/m2/${fileID}.m2`,timings);
        const profile=cameraProfile(fileID);
        const result = {fileID, profile, camera:calibratedCamera(readPortraitCamera(bytes),profile,fileID)};
        res.writeHead(200, {'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','Server-Timing':`read;dur=${timings.readMs || 0}`});
        res.end(JSON.stringify(result));
      } else if (url.pathname.startsWith('/api/audio/')) {
        data = catalogue();
        const file = data.audio.get(url.pathname.slice('/api/audio/'.length));
        if (!file) { res.writeHead(404).end(); return; }
        const variant = data.catalogue.quests.flatMap(q=>q.variants).find(v=>v.id===url.pathname.slice('/api/audio/'.length));
        // Serve exactly the bytes that were verified, even if a library update
        // replaces the installed file while this request is in progress.
        const bytes = await readVerifiedAudio(file, variant.sha256);
        const size = bytes.length, range = audioRange(req.headers.range, size);
        if (!range) { res.writeHead(416, {'Content-Range':`bytes */${size}`}).end(); return; }
        const headers = {'Content-Type':'audio/ogg', 'Accept-Ranges':'bytes', 'Content-Length':range.end-range.start+1, 'Cache-Control':'no-store'};
        if (range.partial) headers['Content-Range'] = `bytes ${range.start}-${range.end}/${size}`;
        res.writeHead(range.partial ? 206 : 200, headers);
        if (req.method === 'HEAD') res.end();
        else res.end(bytes.subarray(range.start, range.end + 1));
      } else if (url.pathname.startsWith('/modelviewer/')) {
        let bytes = await modelAsset(url.pathname,timings);
        if(url.pathname==='/modelviewer/live/viewer/viewer.min.js') bytes=adaptViewerLighting(bytes);
        const ext = path.extname(url.pathname);
        const mime = {'.js':'text/javascript', '.css':'text/css', '.json':'application/json', '.png':'image/png', '.webp':'image/webp'}[ext] || 'application/octet-stream';
        timings.bytes=bytes.length;
        res.writeHead(200, {'Content-Type':mime,'Cache-Control':'public, max-age=86400','Server-Timing':`read;dur=${timings.readMs || 0}`}).end(req.method==='HEAD' ? undefined : bytes);
      } else res.writeHead(404).end();
    } catch (error) {
      console.warn('Voice preview:', error.message);
      if (!res.headersSent) res.writeHead(error.status || 503, {'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'});
      res.end(JSON.stringify({error: url.pathname.startsWith('/modelviewer/') ? 'Не удалось загрузить модель. Проверьте соединение.' : error.message}));
    }
  };
}

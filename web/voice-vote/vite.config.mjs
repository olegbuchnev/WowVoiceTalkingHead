import { defineConfig, normalizePath } from 'vite';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs';
import { localApi } from './server.mjs';
const communityPreview=fileURLToPath(new URL('../../data/voice-vote/community-preview.json',import.meta.url));
const cameraFiles=['CameraModels.lua','CameraProfiles.lua']
  .map(name=>normalizePath(fileURLToPath(new URL(`../../src/${name}`,import.meta.url))));
const proxy = {'/api/votes': {target:process.env.VOICE_VOTE_API || 'http://127.0.0.1:8081', changeOrigin:false}};
export default defineConfig({
  plugins: [{ name:'local-voice-libraries', configureServer(server) {
      // Optional aggregate snapshot for local design reviews; never a production override.
      server.middlewares.use((req,res,next)=>{
        if(req.method!=='GET' || req.url.split('?')[0]!=='/api/votes/community' || !fs.existsSync(communityPreview)) return next();
        try {
          const snapshot=JSON.parse(fs.readFileSync(communityPreview,'utf8'));
          res.writeHead(200,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'});
          res.end(JSON.stringify(snapshot));
        } catch(error) {next(error);}
      });
      server.middlewares.use(localApi());
      server.watcher.add(cameraFiles);
    },
    handleHotUpdate({file,server}) {
      if(!cameraFiles.includes(normalizePath(file))) return;
      server.ws.send({type:'custom',event:'portrait-camera-changed'});
      // Refresh only the portrait: keep the current audio, text and vote state.
      return [];
    },
    configurePreviewServer(server) { server.middlewares.use(localApi()); } }],
  server: { host:'127.0.0.1', port:5174, strictPort:true, fs:{strict:true}, proxy },
  preview: { host:'127.0.0.1', port:5174, strictPort:true, proxy },
});

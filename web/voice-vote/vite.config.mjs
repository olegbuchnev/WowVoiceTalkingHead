import { defineConfig, normalizePath } from 'vite';
import { fileURLToPath } from 'node:url';
import { localApi } from './server.mjs';
const cameraFiles=['CameraModels.lua','CameraProfiles.lua']
  .map(name=>normalizePath(fileURLToPath(new URL(`../../src/${name}`,import.meta.url))));
const proxy = {'/api/votes': {target:process.env.VOICE_VOTE_API || 'http://127.0.0.1:8081', changeOrigin:false}};
export default defineConfig({
  plugins: [{ name:'local-voice-libraries', configureServer(server) {
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

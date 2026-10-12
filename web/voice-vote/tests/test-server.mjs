import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {createServer} from 'vite';
import {repo, demoIDs, localApi} from '../server.mjs';
import {exportVoteCatalogue} from '../export-vote-catalogue.mjs';

// A separate database and random ports keep automated votes out of real data.
export async function startTestServer({questIDs=demoIDs,adminPassword} = {}) {
  const directory=fs.mkdtempSync(path.join(os.tmpdir(),'talkinghead-vote-test-'));
  const catalogue=path.join(directory,'catalogue.json');
  let java,vite,logs='';
  async function close() {
    await vite?.close();
    if(java && java.exitCode===null) {const exited=once(java,'exit');java.kill();await exited;}
    if (path.dirname(directory)!==path.resolve(os.tmpdir()) || !path.basename(directory).startsWith('talkinghead-vote-test-')) throw Error('Unsafe test directory');
    fs.rmSync(directory,{recursive:true,force:true});
  }
  try {
    await exportVoteCatalogue(catalogue,{questIDs});
    fs.copyFileSync(path.join(repo,'server/voice-vote/target/voice-vote-server-0.1.0.jar'),path.join(directory,'server.jar'));
    const env={...process.env};
    if(adminPassword) {
      fs.writeFileSync(path.join(directory,'admin-password.txt'),adminPassword);
      env.VOICE_VOTE_ADMIN_PASSWORD_FILE=path.join(directory,'admin-password.txt');
    }
    delete env.WOWVOICE_FOREVER_BETA_ADDONS;
    // Simulate hosting: a standalone JAR, portable metadata and a writable DB.
    java=spawn('java',['--enable-native-access=ALL-UNNAMED','-jar','server.jar',
      '--server.port=0','--voice-vote.database=votes.sqlite','--voice-vote.catalogue=catalogue.json'],
      {windowsHide:true,cwd:directory,env});
    const port=await new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>reject(Error(`Java startup timeout: ${logs}`)),30000);
      java.on('error',e=>{clearTimeout(timer);reject(e);});
      java.on('exit',code=>{clearTimeout(timer);reject(Error(`Java exited ${code}: ${logs}`));});
      java.stderr.on('data',chunk=>{logs+=chunk;});
      java.stdout.on('data',chunk=>{logs+=chunk;const match=/VOICE_VOTE_PORT=(\d+)/.exec(logs);if(match){clearTimeout(timer);resolve(Number(match[1]));}});
    });
    vite=await createServer({root:path.join(repo,'web/voice-vote'),configFile:false,
      plugins:[{name:'fixture-catalogue',configureServer(server){server.middlewares.use(localApi({questIDs}));}}],
      server:{host:'127.0.0.1',port:0,strictPort:false,proxy:{'/api/votes':{target:`http://127.0.0.1:${port}`,changeOrigin:false}}}});
    await vite.listen();
    return {url:`http://127.0.0.1:${vite.httpServer.address().port}`,apiUrl:`http://127.0.0.1:${port}`,close};
  } catch(error) {await close();throw error;}
}

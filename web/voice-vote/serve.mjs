import http from 'node:http';
import {spawn} from 'node:child_process';
import {localApi} from './server.mjs';
import {loadPortableData} from './portable-data.mjs';

const data=loadPortableData(process.env.VOICE_VOTE_CATALOGUE_DIR || '/catalogue',process.env.VOICE_VOTE_LIBRARIES_DIR || '/libraries');
const api=localApi({loadData:()=>data});
const server=http.createServer((req,res)=> {
  if(req.url==='/health') {res.writeHead(200).end('ok');return;}
  void api(req,res,()=>res.writeHead(404).end());
});
server.requestTimeout=30000;server.headersTimeout=10000;
server.listen(8082,'127.0.0.1',()=>console.log('Site asset service ready'));
const nginx=spawn('nginx',['-e','/dev/stderr','-c','/app/web/voice-vote/docker/nginx.conf','-g','daemon off;'],{stdio:'inherit'});
let stopping=false;
function stop(code=0) {
  if(stopping) return;stopping=true;
  nginx.kill('SIGQUIT');server.close();
  const timer=setTimeout(()=>{nginx.kill('SIGKILL');process.exit(code);},10000);timer.unref();
  nginx.once('exit',()=>process.exit(code));
}
nginx.on('error',error=>{console.error('Nginx failed',error);stop(1);});
nginx.on('exit',code=>{if(!stopping){server.close();process.exit(code || 1);}});
server.on('error',error=>{console.error('Asset service failed',error);stop(1);});
process.on('SIGTERM',()=>stop());process.on('SIGINT',()=>stop());

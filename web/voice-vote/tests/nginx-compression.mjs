// Run inside the image build against its actual Nginx config. Synthetic binary
// data exercises transport only; no Blizzard models, audio or secrets are used.
import assert from 'node:assert/strict';
import http from 'node:http';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {gunzipSync} from 'node:zlib';
import {randomBytes} from 'node:crypto';

const block=randomBytes(1024),model=Buffer.concat(Array(1024).fill(block));
const upstream=http.createServer((req,res)=>{
  res.writeHead(200,{'Content-Type':'application/octet-stream','Content-Length':model.length});
  res.end(model);
});
function read(encoding) {
  return new Promise((resolve,reject)=>{
    const request=http.get('http://127.0.0.1:8080/modelviewer/classicplus/m2/950080.m2',{
      headers:{'Accept-Encoding':encoding},timeout:5000,
    },response=>{
      const chunks=[];response.on('data',chunk=>chunks.push(chunk));response.on('error',reject);
      response.on('end',()=>resolve({status:response.statusCode,headers:response.headers,bytes:Buffer.concat(chunks)}));
    });
    request.on('timeout',()=>request.destroy(Error('Compression test request timed out')));
    request.on('error',reject);
  });
}
let nginx;
try {
  upstream.listen(8082,'127.0.0.1');await once(upstream,'listening');
  nginx=spawn('nginx',['-e','/dev/stderr','-c','/app/web/voice-vote/docker/nginx.conf','-g','daemon off;'],{stdio:'inherit'});
  let spawnError;nginx.on('error',error=>{spawnError=error;});
  let plain;
  for(let attempt=0;attempt<50;attempt++) {
    if(spawnError) throw spawnError;
    if(nginx.exitCode!==null) throw Error(`Nginx exited: ${nginx.exitCode}`);
    try {plain=await read('identity');break;}
    catch(error) {if(error.code!=='ECONNREFUSED') throw error;await new Promise(resolve=>setTimeout(resolve,100));}
  }
  assert(plain,'Nginx did not start');
  assert.equal(plain.status,200);assert.equal(plain.headers['content-encoding'],undefined);
  assert.deepEqual(plain.bytes,model);
  const packed=await read('gzip');assert.equal(packed.status,200);
  assert.equal(packed.headers['content-encoding'],'gzip','Binary models must be compressed');
  assert.match(packed.headers.vary || '',/Accept-Encoding/i);
  assert.deepEqual(gunzipSync(packed.bytes),model,'Compression must preserve every model byte');
  assert(packed.bytes.length<model.length/2,'Fixture transfer should be substantially smaller');
  console.log(`PASS: production Nginx binary gzip ${model.length} -> ${packed.bytes.length} bytes, Vary and identity fallback.`);
} finally {
  if(nginx && nginx.exitCode===null && nginx.pid) {
    const exited=once(nginx,'exit');nginx.kill('SIGTERM');await exited;
  }
  await new Promise(resolve=>upstream.close(resolve));
}

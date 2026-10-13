import {test} from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {once} from 'node:events';
import {sanitizePortraitReport,createDiagnosticsHandler} from '../diagnostics.mjs';

const report={version:1,loadID:'p-a81f3c92d640',questID:977,displayID:9780,modelFileID:119369,stage:'ready',totalMs:48000,resources:[{path:'/modelviewer/classicplus/m2/119369.m2',durationMs:47000,requestID:'a'.repeat(32),cookie:'secret'}]};
test('context loss after portrait readiness is accepted as a diagnostic event',()=>{
  assert.equal(sanitizePortraitReport({...report,stage:'context-lost'}).stage,'context-lost');
});
test('portrait readiness details retain only bounded counts and boolean states',()=>{
  const value=sanitizePortraitReport({...report,stage:'timeout',status:{
    contextLost:false,actorLoaded:true,animations:60,pendingDownloads:0,textures:20,
    pendingTextures:1,url:'secret',cookie:'secret',message:'secret'}});
  assert.deepEqual(value.status,{contextLost:false,actorLoaded:true,animations:60,
    pendingDownloads:0,textures:20,pendingTextures:1});
  assert.deepEqual(sanitizePortraitReport({...report,status:{contextLost:'false',animations:Infinity,
    textures:100001,pendingTextures:-1,pendingDownloads:1.5}}).status,{});
});
test('portrait telemetry whitelists fields and bounds client-controlled values',()=>{
  const value=sanitizePortraitReport({...report,cookie:'secret',ip:'secret',message:'secret'});
  assert(!JSON.stringify(value).includes('secret'));
  assert.equal(value.resources[0].requestID,'a'.repeat(32));
  for(const bad of [{stage:'arbitrary'},{totalMs:Infinity},{displayID:0},{version:2}]) assert.throws(()=>sanitizePortraitReport({...report,...bad}));
  const filtered=sanitizePortraitReport({...report,resources:[{path:'/secret'},{path:'/modelviewer/classicplus/m2/../secret'},{path:'/modelviewer/classicplus/m2/1.m2?secret=1'}]});
  assert.deepEqual(filtered.resources,[]);
});
test('diagnostic endpoint records structured events, rejects bad/large requests and bounds volume',async()=>{
  const logs=[];let time=0;
  const handle=createDiagnosticsHandler({log:line=>logs.push(JSON.parse(line)),now:()=>time,limit:6});
  const server=http.createServer((req,res)=>void handle(req,res));
  server.listen(0,'127.0.0.1');await once(server,'listening');
  const url=`http://127.0.0.1:${server.address().port}/api/diagnostics/portrait`;
  const post=body=>fetch(url,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  try {
    assert.equal((await post(report)).status,204);assert.equal(logs[0].event,'portrait_client');
    assert.equal((await fetch(url)).status,405);
    assert.equal((await post({})).status,400);
    assert.equal((await post({...report,padding:'x'.repeat(9000)})).status,413);
    for(let i=0;i<4;i++) await post({});
    assert.equal((await post(report)).status,429);assert.equal(logs.length,1);
    time=60000;assert.equal((await post(report)).status,204);
  } finally {server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
});

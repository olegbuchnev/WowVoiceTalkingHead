import {firefox} from 'playwright';
import {createServer} from 'vite';
import assert from 'node:assert/strict';
import path from 'node:path';

// In-memory PCM fixture; no library recordings or production votes are used.
const wav=Buffer.alloc(44+16000*2);
wav.write('RIFF');wav.writeUInt32LE(wav.length-8,4);wav.write('WAVEfmt ',8);
wav.writeUInt32LE(16,16);wav.writeUInt16LE(1,20);wav.writeUInt16LE(1,22);
wav.writeUInt32LE(8000,24);wav.writeUInt32LE(16000,28);wav.writeUInt16LE(2,32);
wav.writeUInt16LE(16,34);wav.write('data',36);wav.writeUInt32LE(wav.length-44,40);
const quests=Array.from({length:7},(_,i)=>({questID:i+1,text:`Quest ${i+1}`,npc:{name:'Fixture'},
  variants:['WowVoice','CatQuest','Wayfarer'].slice(0,i%2 ? 2 : 3).map((source,j)=>({
    id:`${i+1}-${j}`,source,duration:2,url:`/api/audio/${i+1}-${j}`,
  })),
}));
const server=await createServer({root:path.resolve(import.meta.dirname,'..'),configFile:false,server:{host:'127.0.0.1',port:0}});
let browser;
try {
  await server.listen();
  // Optional deployed-build check still intercepts every vote and audio request.
  const base=process.env.VOICE_VOTE_TEST_URL || `http://127.0.0.1:${server.httpServer.address().port}`;
  browser=await firefox.launch({headless:true,...(process.env.PLAYWRIGHT_FIREFOX_EXECUTABLE ? {executablePath:process.env.PLAYWRIGHT_FIREFOX_EXECUTABLE} : {})});
  const page=await browser.newPage(),requests=[],rated=new Set(),errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.route('**/*',route=>new URL(route.request().url()).origin===base ? route.continue() : route.abort());
  await page.route('**/api/catalogue',route=>route.fulfill({json:{quests}}));
  await page.route('**/api/votes/**',route=>{
    if(route.request().url().endsWith('/submit')) rated.add(route.request().postDataJSON().questID);
    return route.fulfill({json:route.request().url().endsWith('/queue') ? quests.map(q=>({questID:q.questID,rated:rated.has(q.questID)})) : {total:rated.size}});
  });
  await page.route('**/api/audio/*',route=>{requests.push(new URL(route.request().url()).pathname);return route.fulfill({contentType:'audio/wav',body:wav});});
  await page.addInitScript(()=>{
    window.preloadedAudio=0;
    window.audioStarts=0;
    const play=HTMLMediaElement.prototype.play;
    HTMLMediaElement.prototype.play=async function(){await play.call(this);window.audioStarts++;};
    const create=URL.createObjectURL;
    URL.createObjectURL=function(blob){window.preloadedAudio++;return create.call(URL,blob);};
  });
  await page.goto(base);
  await page.waitForFunction(()=>window.preloadedAudio===5);
  assert.equal(requests.length,5,'all variants of the first TWO comparisons load on the welcome screen');
  await page.locator('.welcome-start').click();
  await page.locator('audio').evaluate(a=>{a.muted=true;});
  let starts=0;
  for(let i=0;i<5;i++) {
    const expected=quests.slice(0,Math.min(i+2,5)).reduce((sum,q)=>sum+q.variants.length,0);
    await page.waitForFunction(n=>window.preloadedAudio===n,expected);
    for(let j=0;j<quests[i].variants.length;j++) {
      await page.locator('.play-button').nth(j).click();
      await page.waitForFunction(n=>window.audioStarts===n,++starts);
      await page.waitForFunction(()=>document.querySelector('audio').currentSrc.startsWith('blob:') && !document.querySelector('audio').paused);
    }
    assert.equal(requests.length,expected,'warm playback does not download audio again');
    await page.locator('.vote-button').first().click();
    if(i<4) await page.locator('.next-sample').click();
  }
  const expected=quests.slice(0,6).reduce((sum,q)=>sum+q.variants.length,0);
  await page.waitForFunction(n=>window.preloadedAudio===n,expected);
  assert.equal(requests.length,expected,'next series audio loads before Continue');
  await page.locator('.continue-batch').click();
  await page.locator('.play-button').first().click();
  await page.waitForFunction(()=>document.querySelector('audio').currentSrc.startsWith('blob:') && !document.querySelector('audio').paused);
  assert.deepEqual(errors,[]);
  console.log('PASS: welcome, current/next comparisons and next series preload all variants; playback reuses blobs without new requests.');
} finally {await browser?.close();await server.close();}

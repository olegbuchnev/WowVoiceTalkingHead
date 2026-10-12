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
  const volume=page.getByRole('slider',{name:'Громкость'});
  assert.equal(await volume.inputValue(),'100');
  assert.equal(await page.locator('audio').evaluate(a=>a.volume),1);
  await volume.focus();await volume.press('End');await volume.press('ArrowDown');
  assert.equal(await volume.inputValue(),'99');
  assert.equal(await page.locator('audio').evaluate(a=>a.volume),.99);
  assert.equal((await page.context().cookies()).find(c=>c.name==='thru_vote_volume')?.value,'99');
  await page.getByRole('button',{name:'Выключить звук',exact:true}).click();
  assert.equal(await volume.inputValue(),'0');
  assert.equal(await page.locator('audio').evaluate(a=>a.volume),0);
  requests.length=0;
  await page.reload();
  await page.waitForFunction(()=>window.preloadedAudio===5);
  await page.locator('.welcome-start').click();
  assert.equal(await volume.inputValue(),'0','mute survives a page reload');
  assert.equal(await page.locator('audio').evaluate(a=>a.volume),0);
  await page.getByRole('button',{name:'Включить звук',exact:true}).click();
  assert.equal(await volume.inputValue(),'99','unmute restores the previous volume even after a reload');
  assert.equal(await page.locator('audio').evaluate(a=>a.volume),.99);
  await page.setViewportSize({width:1440,height:1000});
  const desktopControl=await page.locator('.volume-control').boundingBox(),head=await page.locator('.head-stage').boundingBox();
  assert(desktopControl.x>=0 && desktopControl.x+desktopControl.width<head.x,'desktop volume sits to the left of the head');
  assert(Math.abs(desktopControl.y-head.y)<1 && Math.abs(desktopControl.height-head.height)<1,'desktop volume matches the head panel height');
  await page.setViewportSize({width:390,height:844});
  const mobileControl=await page.locator('.volume-control').boundingBox(),mobileHead=await page.locator('.head-stage').boundingBox();
  assert(mobileControl.y>=mobileHead.y+mobileHead.height && mobileControl.x>=0 && mobileControl.x+mobileControl.width<=390,'mobile volume sits below the head and fits the viewport');
  await page.setViewportSize({width:1440,height:1000});
  await page.locator('audio').evaluate(a=>{a.muted=true;});
  let starts=0;
  for(let i=0;i<5;i++) {
    const expected=quests.slice(0,Math.min(i+2,5)).reduce((sum,q)=>sum+q.variants.length,0);
    await page.waitForFunction(n=>window.preloadedAudio===n,expected);
    for(let j=0;j<quests[i].variants.length;j++) {
      await page.locator('.play-button').nth(j).click();
      await page.waitForFunction(n=>window.audioStarts===n,++starts);
      await page.waitForFunction(()=>document.querySelector('audio').currentSrc.startsWith('blob:') && !document.querySelector('audio').paused);
      assert.equal(await page.locator('audio').evaluate(a=>a.volume),.99,'switching recordings preserves volume');
    }
    assert.equal(requests.length,expected,'warm playback does not download audio again');
    await page.locator('.vote-button').first().click();
    assert(await volume.isVisible(),'volume remains available on the result screen');
    if(i<4) await page.locator('.next-sample').click();
  }
  const expected=quests.slice(0,6).reduce((sum,q)=>sum+q.variants.length,0);
  await page.waitForFunction(n=>window.preloadedAudio===n,expected);
  assert.equal(requests.length,expected,'next series audio loads before Continue');
  await page.locator('.continue-batch').click();
  await page.locator('.play-button').first().click();
  await page.waitForFunction(()=>document.querySelector('audio').currentSrc.startsWith('blob:') && !document.querySelector('audio').paused);
  assert.deepEqual(errors,[]);
  await volume.focus();await volume.press('Home');
  assert.equal(await page.locator('audio').evaluate(a=>a.volume),0,'volume changes immediately during playback');
  assert.equal(await page.locator('audio').evaluate(a=>a.paused),false,'changing volume does not restart or stop the recording');
  await page.getByRole('button',{name:'Включить звук',exact:true}).press('Space');
  assert.equal(await volume.inputValue(),'99','keyboard unmute restores the last audible slider value');
  await page.getByRole('button',{name:'Выключить звук',exact:true}).click();
  assert.equal(await page.locator('audio').evaluate(a=>a.volume),0);
  await page.getByRole('button',{name:'Включить звук',exact:true}).click();
  assert.equal(await page.locator('audio').evaluate(a=>a.volume),.99);
  assert.equal(await page.locator('audio').evaluate(a=>a.paused),false,'mute/unmute keeps playback running');
  await page.locator('.volume-control').hover();
  const scrollBefore=await page.evaluate(()=>window.scrollY);
  await page.mouse.wheel(0,100);
  await page.waitForFunction(()=>document.querySelector('#voice-volume').value==='94');
  assert.equal(await page.locator('audio').evaluate(a=>a.volume),.94);
  assert.equal(await page.evaluate(()=>window.scrollY),scrollBefore,'wheel over volume does not scroll the page');
  await page.mouse.wheel(0,-100);
  await page.waitForFunction(()=>document.querySelector('#voice-volume').value==='99');
  await page.mouse.wheel(0,-100);
  await page.waitForFunction(()=>document.querySelector('#voice-volume').value==='100');
  await page.getByRole('button',{name:'Выключить звук',exact:true}).click();
  await page.mouse.wheel(0,100);
  await page.waitForTimeout(100);
  assert.equal(await volume.inputValue(),'0','wheel cannot reduce volume below zero');
  await page.mouse.wheel(0,-100);
  await page.waitForFunction(()=>document.querySelector('#voice-volume').value==='5');
  assert.equal((await page.context().cookies()).find(c=>c.name==='thru_vote_volume')?.value,'5');
  console.log('PASS: mouse wheel adjusts and saves volume in 5% steps within 0–100%, without scrolling the page.');
  console.log('PASS: volume defaults to 100%, persists in a cookie across reloads, applies to every recording and fits desktop/mobile layouts.');
  console.log('PASS: welcome, current/next comparisons and next series preload all variants; playback reuses blobs without new requests.');
} finally {await browser?.close();await server.close();}

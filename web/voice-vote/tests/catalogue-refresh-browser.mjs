import {firefox} from 'playwright';
import {createServer} from 'vite';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root=path.resolve(import.meta.dirname,'..');
const server=await createServer({root,configFile:false,server:{host:'127.0.0.1',port:0}});
await server.listen();
const cache=path.join(process.env.LOCALAPPDATA || '', 'ms-playwright');
const executablePath=fs.readdirSync(cache).filter(n=>n.startsWith('firefox-')).sort().reverse()
  .map(n=>path.join(cache,n,'firefox/firefox.exe')).find(file=>fs.existsSync(file));
const browser=await firefox.launch({headless:true,executablePath});
try {
  const page=await browser.newPage();
  const errors=[];page.on('pageerror',error=>errors.push(error.message));
  await page.addInitScript(()=>{
    const original=fetch;
    window.fixture={revision:1,requests:0,ballots:[],accepted:[],reject:false,hold:false};
    const json=(data,status=200)=>new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json'}});
    window.fetch=async function(input,options) {
      const f=window.fixture;
      if(input==='/api/catalogue') {
        f.requests++;
        return json({quests:Array.from({length:12},(_,i)=>({questID:i+1,text:'Quest description',npc:{displayID:0,name:`NPC ${i+1}`},
          variants:['WowVoice','CatQuest','Wayfarer'].map((source,j)=>({source,id:`${i+1}-${j}-${f.revision}`,duration:40,url:`/audio/${i+1}-${j}-${f.revision}`}))}))});
      }
      if(input==='/api/votes/summary') return json({counts:{WowVoice:0,CatQuest:0,Wayfarer:0},total:f.accepted.length});
      if(input==='/api/votes/queue') {
        if(f.hold) {f.hold=false;await new Promise(resolve=>{f.release=resolve;});}
        return json(Array.from({length:12},(_,i)=>({questID:i+1,rated:f.accepted.some(b=>b.questID===i+1 && b.selectedId.endsWith(`-${f.revision}`))})));
      }
      if(input==='/api/votes/submit') {
        const ballot=JSON.parse(options.body);f.ballots.push(ballot);
        if(f.reject || !ballot.selectedId.endsWith(`-${f.revision}`)) {f.reject=false;return json({},409);}
        f.accepted.push(ballot);return json({});
      }
      if(String(input).startsWith('/api/votes')) return json({});
      return original(input,options);
    };
    // No external audio, models, backend or real votes are used in this fixture.
    HTMLMediaElement.prototype.play=function(){this.dispatchEvent(new Event('playing'));return Promise.resolve();};
    HTMLMediaElement.prototype.pause=function(){this.dispatchEvent(new Event('pause'));};
    HTMLMediaElement.prototype.load=function(){};
    Object.defineProperty(HTMLMediaElement.prototype,'src',{set(value){this.fixtureSrc=value;},get(){return this.fixtureSrc;}});
  });
  await page.goto(`http://127.0.0.1:${server.httpServer.address().port}`);
  await page.locator('.welcome-start').click();
  await page.waitForSelector('.batch-progress');
  const current=()=>page.locator('.portrait-slot.current').getAttribute('data-quest-id');
  const first=await current();
  await page.locator('.play-button').nth(0).click();
  const originalAudio=await page.locator('audio').evaluate(a=>a.src);
  // A background update preserves the active speaker, playback and series index.
  await page.evaluate(()=>{window.fixture.revision=2;window.dispatchEvent(new Event('focus'));});
  await page.waitForFunction(()=>window.fixture.requests>=2);
  assert.equal(await current(),first);
  assert.equal(await page.locator('audio').evaluate(a=>a.src),originalAudio);
  assert.equal(await page.locator('.batch-progress').textContent(),'Сравнение 1 из 5');
  assert(await page.locator('.signal.playing').isVisible());
  async function choose() {
    await page.locator('.play-button').nth(0).click();
    await page.locator('.play-button').nth(1).click();
    await page.locator('.vote-button').nth(0).click();
    await page.waitForSelector('.choice-confirmation');
  }
  // Complete the old comparison normally. The server rejects it silently.
  await page.locator('.play-button').nth(1).click();
  await page.locator('.vote-button').nth(0).click();
  await page.waitForFunction(()=>window.fixture.ballots.length===1 && window.fixture.requests>=3);
  assert.equal((await page.evaluate(()=>window.fixture.accepted)).length,0);
  assert.equal(await page.locator('.stats-heading>span').textContent(),'Всего выборов: 1');
  assert.equal(await page.locator('[role=alert]').count(),0);
  assert.equal(await page.locator('.welcome').count(),0);
  await page.locator('.next-sample').click();
  await page.waitForFunction(()=>document.querySelector('.batch-progress').textContent==='Сравнение 2 из 5');
  await page.locator('.play-button').nth(0).click();
  assert.match(await page.locator('audio').evaluate(a=>a.src),/-2$/);
  // The update arrived after listening but before submission: 409 itself must
  // initiate refresh, without a focus event or resetting the session chart.
  await page.locator('.play-button').nth(1).click();
  await page.evaluate(()=>{window.fixture.revision=3;});
  await page.locator('.vote-button').nth(0).click();
  await page.waitForFunction(()=>window.fixture.ballots.length===2);
  await page.locator('.next-sample').click();
  await page.waitForFunction(()=>document.querySelector('.batch-progress').textContent==='Сравнение 3 из 5');
  await page.locator('.play-button').nth(0).click();
  assert.match(await page.locator('audio').evaluate(a=>a.src),/-3$/);
  await page.locator('.play-button').nth(1).click();
  await page.locator('.vote-button').nth(0).click();
  await page.locator('.next-sample').click();
  await page.waitForFunction(()=>document.querySelector('.batch-progress').textContent==='Сравнение 4 из 5');
  await choose();await page.locator('.next-sample').click();
  await page.waitForFunction(()=>document.querySelector('.batch-progress').textContent==='Сравнение 5 из 5');
  await page.evaluate(()=>{window.fixture.hold=true;});
  await choose();
  await page.waitForFunction(()=>!!window.fixture.release);
  // Change data while preparation is awaiting queue priorities. Old completion
  // must not overwrite the newer catalogue/preloaded series.
  const requests=await page.evaluate(()=>window.fixture.requests);
  await page.evaluate(()=>{window.fixture.revision=4;window.dispatchEvent(new Event('focus'));});
  await page.waitForFunction(n=>window.fixture.requests>n,requests);
  await page.evaluate(()=>window.fixture.release());
  await page.waitForFunction(()=>!document.querySelector('.continue-batch').disabled);
  await page.locator('.continue-batch').click();
  await page.waitForFunction(()=>document.querySelector('.batch-progress').textContent==='Сравнение 1 из 5');
  await page.locator('.play-button').nth(0).click();
  assert.match(await page.locator('audio').evaluate(a=>a.src),/-4$/);
  assert.equal(await page.locator('.stats-heading>span').textContent(),'Всего выборов: 5');
  assert.equal(await page.locator('.welcome').count(),0);
  assert.equal(await page.locator('[role=alert]').count(),0);
  assert.deepEqual(errors,[]);
  console.log('PASS: silent catalogue refresh during playback, rejected ballots, navigation and next-series preparation; session chart and screen preserved.');
} finally {await browser.close();await server.close();}

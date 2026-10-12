import {firefox} from 'playwright';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {repo} from '../server.mjs';
import {startTestServer} from './test-server.mjs';

const server=await startTestServer();
const cache=path.join(process.env.LOCALAPPDATA || '', 'ms-playwright');
const executablePath=fs.readdirSync(cache).filter(n=>n.startsWith('firefox-')).sort().reverse()
  .map(n=>path.join(cache,n,'firefox/firefox.exe')).find(file=>fs.existsSync(file));
const browser=await firefox.launch({headless:true,executablePath});
try {
  const page=await browser.newPage({viewport:{width:1365,height:900}});
  const errors=[];
  page.on('pageerror',error=>errors.push(error.message));
  await page.addInitScript(()=>{
    // Isolate seven frontend fixtures from the real three-quest voting database.
    const original=window.fetch, votes=new Map(JSON.parse(sessionStorage.getItem('batch-fixture-votes') || '[]'));
    let catalogue;
    window.failNextBatchVote=false;
    window.failNextBatchQueue=false;
    HTMLMediaElement.prototype.play=function(){this.muted=true;return Promise.resolve();};
    const json=(data,status=200)=>new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json'}});
    window.fetch=async function(input,options) {
      if(input==='/api/catalogue') {
        const source=await (await original.call(this,input,options)).json();
        catalogue={...source,quests:Array.from({length:7},(_,i)=>({...source.quests[i%3],questID:i+1}))};
        return json(catalogue);
      }
      if(input==='/api/votes/summary') return json({counts:{WowVoice:0,CatQuest:0,Wayfarer:0},total:votes.size});
      if(input==='/api/votes/queue') {
        if(window.holdNextBatchQueue) {
          window.holdNextBatchQueue=false;
          await new Promise(resolve=>{window.releaseBatchQueue=resolve;});
        }
        if(window.failNextBatchQueue) {window.failNextBatchQueue=false;return json({},503);}
        return json(Array.from({length:7},(_,i)=>({questID:i+1,rated:votes.has(i+1),votes:votes.has(i+1)?1:0})).sort((a,b)=>Number(a.rated)-Number(b.rated)));
      }
      if(input==='/api/votes/submit' && options?.method==='POST') {
        if(window.failNextBatchVote) {window.failNextBatchVote=false;return json({},503);}
        const ballot=JSON.parse(options.body);
        const selected=catalogue.quests.find(q=>q.questID===ballot.questID).variants.find(v=>v.id===ballot.selectedId).source;
        votes.set(ballot.questID,selected);
        sessionStorage.setItem('batch-fixture-votes',JSON.stringify([...votes]));
        return json({comparisonID:String(ballot.questID),selected,total:votes.size});
      }
      return original.call(this,input,options);
    };
  });
  await page.goto(server.url);
  await page.locator('.welcome .welcome-start').click();
  await page.waitForSelector('.batch-progress');
  async function choose(checkChartPosition=false) {
    await page.locator('.play-button').nth(0).click();
    assert.equal(await page.locator('.transport>span').last().textContent(),'Вариант А','card order must match the shuffled playback labels');
    await page.locator('.play-button').nth(1).click();
    assert.equal(await page.locator('.transport>span').last().textContent(),'Вариант Б','card order must match the shuffled playback labels');
    await page.locator('.vote-button').nth(0).scrollIntoViewIfNeeded();
    const before=checkChartPosition && await page.locator('.vote-stats').evaluate(e=>({top:e.getBoundingClientRect().top,scroll:scrollY}));
    await page.locator('.vote-button').nth(0).click();
    if(checkChartPosition) {
      await page.waitForSelector('.batch-complete');
      const after=await page.locator('.vote-stats').evaluate(e=>({top:e.getBoundingClientRect().top,scroll:scrollY}));
      assert(Math.abs(after.top-before.top)<1,`chart must not jump on completion: ${JSON.stringify({before,after})}`);
      assert(Math.abs(after.scroll-before.scroll)<1,'completion must preserve page scroll');
      assert.equal(await page.locator('.options-content').getAttribute('inert'),'');
      assert(await page.locator('.choice-confirmation').isVisible());
      assert.equal(await page.locator('.completion-title').textContent(),'Готово!');
      assert.equal(await page.locator('.next-sample').isVisible(),false);
      assert.equal(await page.locator('.variants').isVisible(),false);
      assert.equal(await page.locator('.options-stage .batch-complete').count(),1);
      assert.equal(await page.locator('.portrait-slot.current').count(),0,'completed portraits release WebGL resources');
      assert(await page.locator('.portrait-slot').count()<=1,'only the next series first portrait may preload');
    }
  }
  for(let i=1;i<=5;i++) {
    if(i===5) await page.evaluate(()=>{window.holdNextBatchQueue=true;});
    assert.equal(await page.locator('.batch-progress').textContent(),`Сравнение ${i} из 5`);
    assert.equal(await page.locator('.portrait-slot').count(),i===5?1:2);
    if(i===1) {
      await page.evaluate(()=>{window.failNextBatchVote=true;});
      await choose();await page.waitForSelector('.choice-confirmation');
      assert.equal(await page.locator('.batch-progress').textContent(),'Сравнение 1 из 5');
      assert.equal(await page.locator('.stats-heading>span').textContent(),'Всего выборов: 1');
      assert.equal(await page.locator('[role=alert]').count(),0);
    } else await choose(i===5);
    if(i<5) await page.locator('.next-sample').click();
  }
  await page.waitForSelector('.batch-complete');
  assert.equal(await page.locator('.head-stage').isVisible(),true);
  assert.equal(await page.locator('.continue-batch').textContent(),'Сравнить ещё 2');
  assert(await page.locator('.continue-batch').isDisabled());
  const preparingButton=await page.locator('.continue-batch').boundingBox();
  await page.evaluate(()=>window.releaseBatchQueue());
  await page.waitForFunction(()=>!document.querySelector('.continue-batch').disabled);
  const readyButton=await page.locator('.continue-batch').boundingBox();
  assert.deepEqual(readyButton,preparingButton,'preparing the next series must not resize or move its button');
  assert.equal(await page.locator('.stats-heading>span').textContent(),'Всего выборов: 5');
  const firstMessage=await page.locator('.completion-message').textContent();
  assert(await page.locator('audio').evaluate(a=>a.paused&&!a.getAttribute('src')));
  await page.waitForFunction(()=>document.querySelector('.portrait-slot.upcoming .model')?.dataset.modelState==='ready');
  assert.equal(await page.locator('.portrait-slot').count(),1);
  assert.equal(await page.locator('.portrait-slot.upcoming').isVisible(),false);
  const reservedQuest=await page.locator('.portrait-slot.upcoming').getAttribute('data-quest-id');
  await page.evaluate(()=>{window.batchViewer=document.querySelector('.portrait-slot.upcoming .model').modelViewer;});
  await page.screenshot({path:path.join(repo,'artifacts/voice-vote-preview/batch-complete-desktop.png'),fullPage:true});
  // A ready reserve must survive even if the queue endpoint goes offline.
  await page.evaluate(()=>{window.failNextBatchQueue=true;});
  await page.locator('.continue-batch').click();await page.waitForSelector('.batch-progress');
  assert.equal(await page.locator('.portrait-slot.current').getAttribute('data-quest-id'),reservedQuest);
  assert(await page.evaluate(()=>document.querySelector('.portrait-slot.current .model').modelViewer===window.batchViewer));
  assert.equal(await page.locator('.portrait-slot.current .model').getAttribute('data-model-state'),'ready');
  assert.equal(await page.locator('[role=alert]').count(),0);
  await page.setViewportSize({width:390,height:844});
  for(let i=1;i<=2;i++) {
    assert.equal(await page.locator('.batch-progress').textContent(),`Сравнение ${i} из 2`);
    await choose(i===2);if(i<2) await page.locator('.next-sample').click();
  }
  await page.waitForSelector('.batch-complete');
  assert.notEqual(await page.locator('.completion-message').textContent(),firstMessage);
  assert.equal(await page.locator('.stats-heading>span').textContent(),'Всего выборов: 7');
  assert.equal(await page.locator('.continue-batch').textContent(),'Сравнить повторно');
  await page.setViewportSize({width:390,height:844});
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  await page.screenshot({path:path.join(repo,'artifacts/voice-vote-preview/batch-complete-mobile.png'),fullPage:true});
  await page.locator('.continue-batch').click();await page.waitForSelector('[role=alert]');
  assert.equal(await page.locator('.stats-heading>span').textContent(),'Всего выборов: 7');
  assert(await page.locator('.batch-complete').isVisible());
  await page.locator('.continue-batch').click();await page.waitForSelector('.batch-progress');
  assert.equal(await page.locator('.batch-progress').textContent(),'Сравнение 1 из 5');
  assert.equal(await page.locator('.stats-heading>span').textContent(),'Всего выборов: 7');
  for(const viewport of [{width:1365,height:900},{width:390,height:844}]) {
    await page.setViewportSize(viewport);
    await page.reload();
    await page.locator('.welcome .welcome-start').click();
    await page.waitForSelector('.batch-complete');
    await page.evaluate(()=>document.fonts.ready);
    assert.equal(await page.locator('#batch-complete-title').textContent(),'Все доступные задания уже оценены');
    assert.equal(await page.locator('.portrait-slot').count(),0,'exhausted screen must not create WebGL portraits');
    assert.equal(await page.locator('.stats-heading>span').textContent(),'Всего выборов: 0');
    const before=await page.locator('.vote-stats').evaluate(e=>e.getBoundingClientRect().top+scrollY);
    await page.locator('.continue-batch').click();await page.waitForSelector('.batch-progress');
    const after=await page.locator('.vote-stats').evaluate(e=>e.getBoundingClientRect().top+scrollY);
    assert(Math.abs(after-before)<1,`exhausted screen and replay must place chart equally at width ${viewport.width}: ${before} -> ${after}`);
  }
  assert.deepEqual(errors,[]);
  console.log('PASS: 5+2 batches, immediate choices, explicit replay, cumulative chart, distinct messages and silent admission retry.');
} finally {await browser.close();await server.close();}

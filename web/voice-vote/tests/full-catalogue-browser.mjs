import {firefox} from 'playwright';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {startTestServer} from './test-server.mjs';

// Exercise the complete installed dataset against a disposable Java database.
const server=await startTestServer({questIDs:null});
const cache=path.join(process.env.LOCALAPPDATA || '', 'ms-playwright');
const executablePath=fs.readdirSync(cache).filter(n=>n.startsWith('firefox-')).sort().reverse()
  .map(n=>path.join(cache,n,'firefox/firefox.exe')).find(file=>fs.existsSync(file));
let browser;
try {
  browser=await firefox.launch({headless:true,executablePath});
  const page=await browser.newPage();
  const errors=[];
  page.on('pageerror',error=>errors.push(error.message));
  await page.addInitScript(()=>{
    HTMLMediaElement.prototype.play=function(){this.muted=true;return Promise.resolve();};
    const original=window.fetch;
    window.fetch=async function(input,options) {
      const response=await original.call(this,input,options);
      if(input==='/api/votes/queue' && response.ok) {
        const entries=await response.json();
        // Ensure an unknown giver is actually rendered and can receive a vote.
        const rank=q=>q.questID===2 ? 0 : q.questID===478 ? 1 : 2;
        entries.sort((a,b)=>rank(a)-rank(b));
        return new Response(JSON.stringify(entries),{status:200,headers:{'Content-Type':'application/json'}});
      }
      return response;
    };
  });
  await page.goto(server.url);
  await page.locator('.welcome .welcome-start').click();
  await page.waitForSelector('.portrait-slot.current[data-quest-id="2"]');
  assert.equal(await page.locator('.portrait-slot.current .model').getAttribute('data-model-state'),'unavailable');
  assert(await page.locator('.portrait-slot.current .portrait-placeholder').isVisible());
  const counts=await page.evaluate(async()=>({
    catalogue:(await (await fetch('/api/catalogue')).json()).quests.length,
    queue:(await (await fetch('/api/votes/queue')).json()).length
  }));
  assert(counts.catalogue>3000);
  assert.equal(counts.catalogue,counts.queue);
  for(let i=0;i<2;i++) await page.locator('.play-button').nth(i).click();
  const saved=page.waitForResponse(r=>r.url().endsWith('/api/votes/submit') && r.request().method()==='POST');
  await page.locator('.vote-button').first().click();
  const response=await saved;
  assert.equal(response.status(),202);
  assert.equal((await response.json()).state,'queued');
  await page.evaluate(async()=>{
    for(let attempt=0;attempt<100;attempt++) {
      if((await (await fetch('/api/votes/summary')).json()).total===1) return;
      await new Promise(resolve=>setTimeout(resolve,100));
    }
    throw Error('Accepted vote did not reach the database');
  });
  await page.waitForSelector('.choice-confirmation');
  const rated=await page.evaluate(async()=>(await (await fetch('/api/votes/queue')).json()).find(q=>q.questID===2));
  assert.equal(rated.rated,true);
  assert.equal(rated.votes,1);
  await page.locator('.next-sample').click();
  await page.waitForSelector('.portrait-slot.current[data-quest-id="478"]');
  assert.equal(await page.locator('.voice-card').count(),2);
  const grid=await page.locator('.variants').boundingBox();
  const first=await page.locator('.voice-card').nth(0).boundingBox();
  const second=await page.locator('.voice-card').nth(1).boundingBox();
  assert(Math.abs(first.x-grid.x)<1,'two options start at the left edge');
  assert(Math.abs(first.width-(grid.width-24)/3)<1,'cards retain one-third column width');
  assert(Math.abs(grid.x+grid.width-second.x-second.width-first.width-12)<1,'the third column stays empty');
  assert.deepEqual(errors,[]);
  console.log(`Full catalogue: ${counts.catalogue} comparisons, unknown-speaker playback UI and persisted vote passed.`);
} finally {await browser?.close();await server.close();}

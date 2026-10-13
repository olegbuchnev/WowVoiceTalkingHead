import {firefox} from 'playwright';
import {createServer} from 'vite';
import assert from 'node:assert/strict';
import path from 'node:path';

const root=path.resolve(import.meta.dirname,'..');
async function routed(promise) {
  let timer;
  try {return await Promise.race([promise,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('Expected fixture request did not arrive')),10000);})]);}
  finally {clearTimeout(timer);}
}
const server=await createServer({root,configFile:false,server:{host:'127.0.0.1',port:0},plugins:[{
  name:'delayed-model-engine',enforce:'pre',
  resolveId(source,importer) {
    if(source==='./model.js' && importer?.replaceAll('\\','/').endsWith('/src/main.jsx'))
      return path.join(import.meta.dirname,'fixtures/delayed-portrait.js');
  },
}]});
let browser;
try {
  await server.listen();
  const base=`http://127.0.0.1:${server.httpServer.address().port}`;
  browser=await firefox.launch({headless:true,...(process.env.PLAYWRIGHT_FIREFOX_EXECUTABLE ? {executablePath:process.env.PLAYWRIGHT_FIREFOX_EXECUTABLE} : {})});
  for(const delay of [41000,131000]) {
    const context=await browser.newContext();
    try {
      const page=await context.newPage(),errors=[],reports=[];
      page.on('pageerror',error=>errors.push(error.message));
      await page.clock.install();
      const model=Promise.withResolvers(),camera=Promise.withResolvers();
      // Test traffic cannot reach the public site, Wowhead or a real database.
      await context.route('**/*',route=>new URL(route.request().url()).origin===base ? route.continue() : route.abort());
      await page.route('**/test/model/*',route=>{model.resolve(route);});
      await page.route('**/test/camera',route=>{camera.resolve(route);});
      await page.route('**/api/catalogue',route=>route.fulfill({json:{quests:[{
        questID:1050,text:'Delayed portrait fixture',npc:{displayID:2049,name:'Librarian',
          ...(delay===41000 ? {race:'banshee',sex:'female'} : {})},
        variants:[{id:'a',source:'WowVoice'},{id:'b',source:'CatQuest'}],
      }]}}));
      await page.route('**/api/votes/**',route=>route.fulfill({json:route.request().url().endsWith('/queue') ? [] : {total:0}}));
      await page.route('**/api/diagnostics/portrait',route=>{reports.push(route.request().postDataJSON());return route.fulfill({status:204});});
      await page.goto(base);
      await page.locator('.welcome-start').click();
      await page.waitForSelector('.portrait-slot.current .model');
      await page.waitForFunction(()=>document.querySelector('.model')?.dataset.modelState==='loading');
      const modelRequest=await routed(model.promise);
      await page.clock.fastForward(delay);
      const portrait=page.locator('.portrait-slot.current');
      assert.equal(await portrait.locator('.model').getAttribute('data-model-state'),delay>120000 ? 'error' : 'loading');
      assert.equal(await portrait.locator('.portrait-placeholder').count(),1);
      assert.equal(await page.locator('.welcome').count(),0);
      const progress=await page.locator('.batch-progress').textContent();
      await modelRequest.fulfill({contentType:'application/octet-stream',body:Buffer.from([1,2,3,4])});
      const cameraRequest=await routed(camera.promise);
      assert.equal(await portrait.locator('.portrait-placeholder').count(),1,'keep the scroll until camera configuration finishes');
      await cameraRequest.fulfill({json:{}});
      await page.waitForFunction(()=>document.querySelector('.portrait-slot.current .model')?.dataset.modelState==='ready');
      assert.equal(await portrait.locator('.portrait-placeholder').count(),0,'late model must replace the scroll');
      assert.equal(await portrait.locator('.model').getAttribute('data-camera-configured'),'true');
      assert.equal(await page.locator('.batch-progress').textContent(),progress);
      assert.equal(await page.locator('.welcome').count(),0);
      assert.deepEqual(errors,[]);
      await page.waitForFunction(()=>document.querySelector('.model')?.dataset.modelState==='ready');
      for(let attempt=0;attempt<30 && !reports.some(r=>r.stage==='ready');attempt++) await page.waitForTimeout(50);
      assert(reports.some(r=>r.stage==='ready' && r.questID===1050 && r.totalMs>=delay && r.assetsReadyMs>=delay));
      const loadID=await portrait.locator('.model').getAttribute('data-load-id');
      assert.match(loadID,/^p-[a-f0-9]{12}$/);
      assert.equal(await page.locator('body > :first-child').getAttribute('id'),'portrait-debug');
      assert.deepEqual(await page.locator('#portrait-debug').evaluate(el=>Object.keys(el.dataset)),[]);
      assert.equal(await page.locator('#portrait-debug').isVisible(),false);
      const diagnosticText=await page.locator('#portrait-debug').textContent();
      assert(!diagnosticText.includes('\n'),'diagnostics can be copied as one text node');
      assert.deepEqual(JSON.parse(diagnosticText),{questID:1050,npcID:0,displayID:2049,
        modelFileID:0,race:delay===41000 ? 'banshee' : null,sex:delay===41000 ? 'female' : null,state:'ready',loadID});
      assert(reports.some(r=>r.loadID===loadID && r.stage==='started'));
      assert(reports.some(r=>r.loadID===loadID && r.stage==='ready'));
      assert.equal(reports.some(r=>r.stage==='timeout'),delay>120000);
      console.log(`PASS: portrait delayed ${delay/1000}s recovers through the real React UI after camera readiness, without reloading.`);
      await page.unroute('**/test/model/*');
      await page.unroute('**/test/camera');
      await page.route('**/test/model/*',r=>r.fulfill({body:Buffer.from([1,2,3,4])}));
      await page.route('**/test/camera',r=>r.fulfill({json:{}}));
      for(let loss=0;loss<3;loss++) {
        const previousID=await portrait.locator('.model').getAttribute('data-load-id');
        await portrait.locator('canvas').evaluate(canvas=>canvas.dispatchEvent(new Event('webglcontextlost',{cancelable:true})));
        await page.waitForFunction(()=>document.querySelector('.portrait-slot.current .model')?.dataset.modelState==='error');
        assert.equal(await portrait.locator('.portrait-placeholder').count(),1);
        assert.equal(JSON.parse(await page.locator('#portrait-debug').textContent()).state,'error');
        await page.clock.fastForward(1500);
        if(loss<2) {
          await page.waitForFunction(()=>document.querySelector('.portrait-slot.current .model')?.dataset.modelState==='ready');
          assert.notEqual(await portrait.locator('.model').getAttribute('data-load-id'),previousID);
        } else {
          assert.equal(await portrait.locator('.model').getAttribute('data-load-id'),previousID,'persistent context loss must not loop');
          assert.equal(await portrait.locator('.model').getAttribute('data-model-state'),'error');
        }
        assert.equal(await page.locator('.batch-progress').textContent(),progress);
        assert.equal(await page.locator('.welcome').count(),0);
        assert(reports.some(r=>r.loadID===previousID && r.stage==='context-lost'));
      }
      assert.deepEqual(errors,[]);
      console.log('PASS: context loss shows the placeholder, reports the failed mount and retries twice without resetting the comparison.');
      await page.unroute('**/api/catalogue');
      await page.route('**/api/catalogue',route=>route.fulfill({json:{quests:[{
        questID:5657,text:'Unavailable portrait fixture',npc:{id:4606,displayID:0,name:'Eltaliste',race:'banshee',sex:'female'},
        variants:[{id:'a',source:'WowVoice'},{id:'b',source:'CatQuest'}],
      }]}}));
      await page.goto(base);
      await page.locator('.welcome-start').click();
      await page.waitForFunction(()=>JSON.parse(document.getElementById('portrait-debug').textContent).state==='unavailable');
      assert.deepEqual(JSON.parse(await page.locator('#portrait-debug').textContent()),{
        questID:5657,npcID:4606,displayID:0,modelFileID:0,race:'banshee',sex:'female',state:'unavailable',loadID:''});
      console.log('PASS: unavailable portraits retain the exact catalogue race/sex in copyable debug JSON.');
    } finally {await context.close();}
  }
} finally {await browser?.close();await server.close();}

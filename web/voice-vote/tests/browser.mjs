import {firefox} from 'playwright';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {PNG} from '../node_modules/playwright-core/lib/utilsBundle.js';
import {repo} from '../server.mjs';
import {startTestServer} from './test-server.mjs';
const testServer=await startTestServer();

const cache = path.join(process.env.LOCALAPPDATA || '', 'ms-playwright');
const installed = fs.existsSync(cache) && fs.readdirSync(cache).filter(n=>n.startsWith('firefox-')).sort().reverse()
  .map(n=>path.join(cache,n,'firefox/firefox.exe')).find(n=>fs.existsSync(n));
const browser = await firefox.launch({headless:true, ...(installed ? {executablePath:installed} : {})});
const output = path.join(repo,'artifacts/voice-vote-preview');
fs.mkdirSync(output,{recursive:true});
function assertSameImage(actual, expected, message) {
  const a=PNG.sync.read(actual), b=PNG.sync.read(expected);
  assert.equal(a.width,b.width); assert.equal(a.height,b.height);
  // Supersampled WebGL rounds a few channels by 1–2/255 at the closer camera.
  // Bone matrices and camera values are also checked independently below.
  let maximum=0;
  for(let i=0;i<a.data.length;i++) maximum=Math.max(maximum,Math.abs(a.data[i]-b.data[i]));
  assert(maximum<=2,`${message} (maximum channel difference: ${maximum})`);
}
try {
  // Hold the real camera response: a fully textured model must remain covered
  // until its final camera is configured, including on a warm asset cache.
  const loadingPage=await browser.newPage({viewport:{width:1365,height:900}});
  await loadingPage.addInitScript(()=>{
    const fetchOriginal=window.fetch;
    const gate=new Promise(resolve=>{window.releasePortraitCamera=resolve;});
    window.fetch=async function(input,...args) {
      if(String(input).startsWith('/api/portrait-camera/')) {
        window.portraitCameraPending=true;
        await gate;
        if(window.failPortraitCamera) return new Response('',{status:503});
      }
      return fetchOriginal.call(this,input,...args);
    };
  });
  await loadingPage.goto(testServer.url);
  await loadingPage.locator('.welcome .welcome-start').click();
  await loadingPage.waitForFunction(()=>window.portraitCameraPending,{},{timeout:45000});
  assert.equal(await loadingPage.locator('.portrait-slot.current .model').evaluate(e=>getComputedStyle(e).opacity),'0');
  assert(await loadingPage.locator('.portrait-slot.current .portrait-placeholder').isVisible());
  await loadingPage.waitForFunction(()=>document.querySelector('.portrait-slot.current .portrait-placeholder img')?.naturalWidth===64);
  await loadingPage.locator('.portrait-slot.current .portrait').screenshot({path:path.join(output,'loading-scroll.png')});
  await loadingPage.evaluate(()=>window.releasePortraitCamera());
  await loadingPage.waitForSelector('.portrait-slot.current .model[data-model-state=ready]',{timeout:45000});
  assert.equal(await loadingPage.locator('.portrait-slot.current .portrait-placeholder').count(),0);
  assert.equal(await loadingPage.locator('.portrait-slot.current .model').evaluate(e=>getComputedStyle(e).opacity),'1');
  await loadingPage.reload();
  await loadingPage.locator('.welcome .welcome-start').click();
  await loadingPage.waitForFunction(()=>window.portraitCameraPending,{},{timeout:45000});
  await loadingPage.evaluate(()=>{window.failPortraitCamera=true;window.releasePortraitCamera();});
  await loadingPage.waitForSelector('.portrait-slot.current .model[data-model-state=error]',{timeout:45000});
  assert(await loadingPage.locator('.portrait-slot.current .portrait-placeholder').isVisible(),'failed camera keeps the scroll');
  assert.equal(await loadingPage.locator('.portrait-slot.current .model').evaluate(e=>getComputedStyle(e).opacity),'0');
  await loadingPage.close();
  const context=await browser.newContext({baseURL:testServer.url,viewport:{width:1365,height:900}});
  const page = await context.newPage();
  const errors=[]; page.on('pageerror',e=>errors.push(e.message));
  const cameraSnapshots=new Map();
  async function assertPortraitLighting() {
    const light=await page.locator('.portrait-slot.current .model').evaluate(e=>{
      const u=e.modelViewer.renderer.renderer.r;
      return {mode:e.dataset.lighting,ambient:Array.from(u.uAmbientColor).slice(0,3),
        diffuse:Array.from(u.uPrimaryColor).slice(0,3),fill:Array.from(u.uSecondaryColor).slice(0,3),
        direction:Array.from(u.uLightDir1)};
    });
    assert.equal(light.mode,'forever-capture');
    assert.deepEqual(light.ambient,[.69803923368454,.69803923368454,.69803923368454]);
    assert.deepEqual(light.diffuse,[.80000001192093,.80000001192093,.63921570777893]);
    assert.deepEqual(light.fill,[0,0,0],'extra Wowhead fill lights must remain disabled');
    assert(Math.abs(Math.hypot(...light.direction)-1)<1e-6);
  }
  async function assertPortraitCamera() {
    await assertPortraitLighting();
    const snapshot=await page.locator('.portrait-slot.current .model').evaluate(e=>{
      const r=e.modelViewer.renderer;
      return {id:r.actors[0].c.aX,profile:e.dataset.cameraProfile,
        distance:r.distance,eye:Array.from(r.eye),target:Array.from(r.target),projection:Array.from(r.projMatrix)};
    });
    const profiles={878772:'dwarf',124495:'human_child_male',1011653:'human_male'};
    assert.equal(snapshot.profile,profiles[snapshot.id],'camera profile follows the loaded Forever model ID');
    if(cameraSnapshots.has(snapshot.id)) assert.deepEqual(snapshot,cameraSnapshots.get(snapshot.id),'playback, stopping and resizing must preserve the portrait camera');
    else cameraSnapshots.set(snapshot.id,snapshot);
  }
  async function assertPortraitResolution(target) {
    const size=await target.locator('.portrait-slot.current .model').evaluate(e=>{
      const canvas=e.querySelector('canvas'), box=e.getBoundingClientRect();
      return {logicalWidth:e.clientWidth,logicalHeight:e.clientHeight,
        canvasWidth:canvas.width,canvasHeight:canvas.height,
        expected:Math.ceil(Math.min(1024,box.width*devicePixelRatio*2))};
    });
    assert.equal(size.logicalWidth,115,'render quality must not change portrait layout');
    assert.equal(size.logicalHeight,115);
    assert.equal(size.canvasWidth,size.expected,'framebuffer accounts for head zoom, DPR and supersampling');
    assert.equal(size.canvasHeight,size.expected);
  }
  // Exercise real playback without making hidden browser tests audible to the user.
  await page.addInitScript(()=>{
    // Keep ties deterministic for the long-text scrolling fixture.
    const originalFetch=window.fetch;
    window.fetch=async function(input,...args) {
      const response=await originalFetch.call(this,input,...args);
      if(input==='/api/votes/queue' && response.ok) {
        const entries=await response.json(), order=[179,3741,7];
        entries.sort((a,b)=>Number(a.rated)-Number(b.rated)||a.votes-b.votes||order.indexOf(a.questID)-order.indexOf(b.questID));
        return new Response(JSON.stringify(entries),{status:200,headers:{'Content-Type':'application/json'}});
      }
      return response;
    };
    const play=HTMLMediaElement.prototype.play;
    HTMLMediaElement.prototype.play=function(){this.muted=true;return play.call(this);};
    // Check the shader actually compiled by WebGL, not just the served JS text.
    const shaderSource=WebGL2RenderingContext.prototype.shaderSource;
    WebGL2RenderingContext.prototype.shaderSource=function(shader,source) {
      if(source.includes('vec4 litColor = uAmbientColor;')) window.portraitLightingShader=source;
      return shaderSource.call(this,shader,source);
    };
  });
  async function assertStillPortrait(expectedPose) {
    await assertActualAnimation('Stand',true);
    await assertPortraitCamera();
    // Give the renderer time to draw Stand, then compare actual rendered pixels
    // across a second of frames; a data-animation label alone cannot prove pause.
    await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
    const boneMatrices=()=>page.locator('.portrait-slot.current .model').evaluate(e=>e.modelViewer.renderer.actors[0].c.W.map(b=>Array.from(b.j)));
    const bones=await boneMatrices();
    const before = await page.locator('.portrait-slot.current .model').screenshot();
    await page.evaluate(()=>new Promise(resolve=>{
      const start=performance.now();
      const tick=()=>performance.now()-start>=1000 ? resolve() : requestAnimationFrame(tick);
      requestAnimationFrame(tick);
    }));
    assertSameImage(await page.locator('.portrait-slot.current .model').screenshot(),before,'Silent portrait must remain motionless');
    assert.deepEqual(await boneMatrices(),bones,'frozen bones must not animate between recordings');
    if (expectedPose) assertSameImage(before,expectedPose,'Stopping must restore the initial Stand pose, not freeze the last talking pose');
    return before;
  }
  async function assertActualAnimation(name, paused) {
    // Inspect the cached viewer's actual selected sequence. The requested name
    // in data-animation and changing pixels can both pass while Stand is playing.
    await page.waitForFunction(({name,paused})=>{
      const model=document.querySelector('.portrait-slot.current .model')?.modelViewer?.renderer?.actors?.[0]?.c;
      return model?.aa?.e?.a?.h===name && model.aB===paused;
    },{name,paused},{timeout:5000});
  }
  await page.goto(testServer.url);
  assert(await page.locator('.welcome').isVisible());
  assert.equal(await page.locator('.head-stage').isVisible(),false);
  assert.equal(await page.locator('header').count(),1);
  assert(await page.locator('audio').evaluate(a=>a.paused&&!a.getAttribute('src')));
  await page.waitForSelector('.portrait-slot.current .model[data-model-state=ready]',{state:'attached',timeout:45000});
  await page.evaluate(()=>{window.welcomeHeader=document.querySelector('header');window.welcomeViewer=document.querySelector('.portrait-slot.current .model').modelViewer;});
  await page.screenshot({path:path.join(output,'welcome-desktop.png'),fullPage:true});
  await page.setViewportSize({width:390,height:844});
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  assert(await page.evaluate(()=>document.documentElement.scrollHeight<=innerHeight),'preloaded comparison must not add blank scrolling to the welcome screen');
  await page.screenshot({path:path.join(output,'welcome-mobile.png'),fullPage:true});
  await page.setViewportSize({width:1365,height:900});
  await page.locator('.welcome .welcome-start').click();
  assert.equal(await page.locator('.welcome').count(),0);
  assert(await page.evaluate(()=>document.querySelector('header')===window.welcomeHeader));
  assert(await page.evaluate(()=>document.querySelector('.portrait-slot.current .model').modelViewer===window.welcomeViewer));
  assert(await page.locator('.intro h1').evaluate(e=>e===document.activeElement));
  await page.waitForSelector('.portrait-slot.current .model[data-model-state=ready]',{timeout:45000});
  await assertPortraitResolution(page);
  assert.equal(await page.locator('audio').evaluate(a=>a.paused),true);
  await assertStillPortrait();
  const lightingShader=await page.evaluate(()=>window.portraitLightingShader);
  assert(lightingShader?.includes('litColor = max(litColor'),'captured radiance reaches texture shading without the premature 1.0 cap');
  assert(!lightingShader.includes('clamp(litColor'));
  assert(lightingShader.includes('pow(max((litColor * uDiffuseColor).rgb, vec3(0.0)), vec3(1.0 / 2.2))'),
    'display-encoded texture lighting must soften highlights with gamma compensation');
  assert.equal(await page.locator('.vote-button').first().isDisabled(),true);
  // Firefox may restore a nested scroll position after reloading the page.
  await page.locator('.quest-text').evaluate(e=>{e.scrollTop=e.scrollHeight;});
  assert(await page.locator('.quest-text').evaluate(e=>e.scrollTop>0));
  await page.reload();
  await page.locator('.welcome .welcome-start').click();
  await page.waitForSelector('.portrait-slot.current .model[data-model-state=ready]',{timeout:45000});
  await page.evaluate(()=>document.fonts.ready);
  assert.equal(await page.locator('.quest-text').evaluate(e=>e.scrollTop),0,'Reload starts the quest text at the top');
  await page.locator('.play-button').first().click();
  await page.waitForFunction(()=>document.querySelector('audio').currentTime>.2);
  assert.equal(await page.locator('.portrait-slot.current .model').getAttribute('data-animation'),'EmoteTalk');
  await assertActualAnimation('EmoteTalk',false);
  await page.screenshot({path:path.join(output,'desktop.png'),fullPage:true});
  assert.equal(await page.locator('.quest-text').evaluate(e=>e.scrollTop),0,'first page holds still');
  const paging = await page.evaluate(async () => {
    const {measureScrollPlan} = await import('/src/quest-scroll.js');
    const audio = document.querySelector('audio'), viewport = document.querySelector('.quest-text');
    const progress = document.querySelector('.progress'), fill = progress.firstElementChild;
    const plan = measureScrollPlan(viewport,audio.duration), move = plan[0];
    if (!move) throw Error('Sample must overflow for the paging regression check');
    audio.currentTime = move.start - .15;
    const samples = [];
    await new Promise(resolve => {
      const sample = () => {
        if (!audio.seeking) samples.push({time:audio.currentTime, offset:viewport.scrollTop,
          progress:fill.getBoundingClientRect().width/progress.getBoundingClientRect().width});
        if (audio.currentTime >= move.finish + .2) resolve();
        else requestAnimationFrame(sample);
      };
      requestAnimationFrame(sample);
    });
    return {move,samples,duration:audio.duration};
  });
  assert(new Set(paging.samples.filter(s=>s.time>paging.move.start && s.time<paging.move.finish).map(s=>s.offset)).size>5,'scroll transition animates across frames');
  assert(Math.abs(paging.samples.at(-1).offset-paging.move.to)<1,'page holds at the target after the transition');
  assert(new Set(paging.samples.map(s=>s.progress)).size>10,'progress moves across animation frames between sparse timeupdate events');
  const lastProgress=paging.samples.at(-1);
  assert(Math.abs(lastProgress.progress*paging.duration-lastProgress.time)<.1,'progress follows the audio clock without a CSS transition lag');
  const first = await page.locator('audio').getAttribute('src');
  await page.locator('.play-button').nth(1).click();
  await page.waitForFunction(()=>document.querySelector('audio').currentTime>.2);
  assert.notEqual(await page.locator('audio').getAttribute('src'),first);
  assert.equal(await page.locator('audio').count(),1);
  assert.equal(await page.locator('.quest-text').evaluate(e=>e.scrollTop),0,'another recording restarts at the first page');
  assert.equal(await page.locator('.vote-button').first().isEnabled(),true);
  assert.equal(await page.locator('.skip').count(),0);
  await page.waitForSelector('.portrait-slot.upcoming .model[data-model-state=ready]',{state:'attached',timeout:45000});
  const reservedQuest=await page.locator('.portrait-slot.upcoming').getAttribute('data-quest-id');
  await page.evaluate(()=>{
    window.reservedViewer=document.querySelector('.portrait-slot.upcoming .model').modelViewer;
    window.outgoingViewer=document.querySelector('.portrait-slot.current .model').modelViewer;
  });
  await page.evaluate(()=>{
    const original=window.fetch;
    window.fetch=async function(input,options) {
      if(input==='/api/votes/submit' && options?.method==='POST') {
        window.fetch=original;
        return new Response('{"error":"Temporarily unavailable"}',{status:503});
      }
      return original.call(this,input,options);
    };
  });
  await page.locator('.vote-button').first().click();
  await page.waitForSelector('.choice-confirmation');
  assert.equal(await page.locator('[role=alert]').count(),0,'admission retries stay invisible to voters');
  assert.equal(await page.locator('.stats-heading>span').textContent(),'Всего выборов: 1');
  await page.evaluate(async()=>{
    for(let attempt=0;attempt<100;attempt++) {
      if((await (await fetch('/api/votes/summary')).json()).total===1) return;
      await new Promise(resolve=>setTimeout(resolve,100));
    }
    throw Error('Accepted vote did not reach the database');
  });
  const summary=await page.evaluate(()=>fetch('/api/votes/summary').then(r=>r.json()));
  assert.equal(summary.total,1);
  const ratedQuest=Number(await page.locator('.portrait-slot.current').getAttribute('data-quest-id'));
  const returningPage=await page.context().newPage();
  await returningPage.goto(testServer.url);
  assert(await returningPage.locator('.welcome').isVisible());
  await returningPage.locator('.welcome .welcome-start').click();
  await returningPage.waitForSelector('.portrait-slot.current');
  for(const id of await returningPage.locator('.portrait-slot').evaluateAll(items=>items.map(e=>Number(e.dataset.questId))))
    assert.notEqual(id,ratedQuest,'same cookie prioritizes unrated quests for current and preloaded portraits');
  assert.equal(await returningPage.locator('.stats-heading>span').textContent(),'Всего выборов: 0');
  await returningPage.close();
  assert.equal(await page.evaluate(()=>localStorage.getItem('talkinghead-prototype-votes')),null);
  assert.equal(await page.evaluate(()=>document.cookie.includes('talkinghead_voter')),false,'visitor cookie is HttpOnly');
  assert.equal(await page.locator('audio').evaluate(a=>a.paused),true);
  assert(await page.locator('.choice-confirmation').isVisible(),'choice is revealed in place of the talking head');
  assert.equal(await page.locator('.head-content').isVisible(),false);
  assert.equal(await page.locator('.stats-heading>span').textContent(),'Всего выборов: 1');
  assert.equal(await page.locator('.vote-button:enabled').count(),0,'a confirmed choice cannot be submitted twice');
  await page.locator('.head-stage').screenshot({path:path.join(output,'vote-confirmation.png')});
  await page.locator('.next-sample').click();
  assert.equal(await page.locator('.portrait-slot.current').getAttribute('data-quest-id'),reservedQuest,'next comparison was reserved before voting');
  assert(await page.evaluate(()=>document.querySelector('.portrait-slot.current .model').modelViewer===window.reservedViewer),'transition reuses the prepared WebGL viewer, not just cached downloads');
  assert.equal(await page.locator('.portrait-slot.current .model').getAttribute('data-model-state'),'ready');
  assert(await page.evaluate(()=>window.outgoingViewer.renderer.stop),'previous renderer is destroyed');
  assert.equal(await page.locator('.portrait-slot').count(),2,'only current and next portraits stay mounted');
  assert.equal(await page.locator('.progress>div').evaluate(e=>e.getBoundingClientRect().width),0,'changing NPC resets progress');
  assert.equal(await page.locator('.quest-text').evaluate(e=>e.scrollTop),0,'another NPC starts at the first page');
  let initialPose;
  for(const [name,slug] of [['Шоун','child'],['Маршал Макбрайд','human'],['Стен Крепкорук','dwarf']]) {
    // Advance through the actual voting flow; there is no skip or NPC picker.
    for(let attempt=0;await page.locator('.speech h2').textContent()!==name && attempt<6;attempt++) {
      await page.locator('.play-button').first().click();
      await page.waitForFunction(()=>document.querySelector('audio').currentTime>.1);
      await page.locator('.play-button').nth(1).click();
      await page.waitForFunction(()=>document.querySelector('audio').currentTime>.1);
      await page.locator('.vote-button').first().click();
      await page.waitForSelector('.choice-confirmation, .batch-complete');
      if(await page.locator('.batch-complete').count()) {
        assert.equal(await page.locator('audio').evaluate(a=>a.paused),true);
        assert(await page.locator('.completion-message').textContent());
        await page.locator('.continue-batch').click();
        await page.waitForSelector('.speech h2');
      } else await page.locator('.next-sample').click();
    }
    assert.equal(await page.locator('.speech h2').textContent(),name);
    await page.waitForSelector('.portrait-slot.current .model[data-model-state=ready]',{timeout:45000});
    await assertPortraitResolution(page);
    initialPose = await assertStillPortrait();
    await page.locator('.play-button').first().click();
    await page.waitForFunction(()=>document.querySelector('audio').currentTime>.3);
    assert.equal(await page.locator('.portrait-slot.current .model').getAttribute('data-animation'),'EmoteTalk');
    await assertActualAnimation('EmoteTalk',false);
    await assertPortraitCamera();
    await page.locator('.head-stage').screenshot({path:path.join(output,`${slug}.png`)});
    await page.locator('.play-button').first().click();
    assert.equal(await page.locator('.portrait-slot.current .model').getAttribute('data-animation'),'Stand');
    await assertStillPortrait(initialPose);
  }
  // Natural track completion must freeze Stand too, and a new track must resume.
  await page.locator('.play-button').first().click();
  await page.waitForFunction(()=>document.querySelector('audio').currentTime>.2);
  await page.locator('audio').evaluate(a=>{a.currentTime=a.duration-.05;});
  await page.waitForFunction(()=>document.querySelector('audio').ended);
  await page.waitForFunction(()=>{
    const p=document.querySelector('.progress');
    return Math.abs(p.firstElementChild.getBoundingClientRect().width-p.getBoundingClientRect().width)<.1;
  });
  assert.equal(await page.locator('.portrait-slot.current .model').getAttribute('data-animation'),'Stand');
  await assertStillPortrait(initialPose);
  await page.locator('.play-button').first().click();
  await page.waitForFunction(()=>document.querySelector('audio').currentTime>.2);
  const talkingFrame=await page.locator('.portrait-slot.current .model').screenshot();
  await assertActualAnimation('EmoteTalk',false);
  await page.waitForFunction(()=>document.querySelector('audio').currentTime>.8);
  assert(!(await page.locator('.portrait-slot.current .model').screenshot()).equals(talkingFrame),'Talking resumes animation');
  await page.locator('.play-button').first().click();
  await page.setViewportSize({width:390,height:844});
  await page.screenshot({path:path.join(output,'mobile.png'),fullPage:true});
  await assertPortraitResolution(page);
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  await assertPortraitCamera();
  assert.deepEqual(errors,[]);
  const totalBeforeReload=await page.evaluate(()=>fetch('/api/votes/summary').then(r=>r.json()).then(s=>s.total));
  await page.reload();
  await page.locator('.welcome .welcome-start').click();
  await page.waitForSelector('.stats-heading');
  assert.equal(await page.locator('.stats-heading>span').textContent(),'Всего выборов: 0','reload resets the session chart');
  assert.equal(await page.evaluate(()=>fetch('/api/votes/summary').then(r=>r.json()).then(s=>s.total)),totalBeforeReload,'server votes survive a reload');
  const range=await page.request.get(first,{headers:{Range:'bytes=0-63'}});
  assert.equal(range.status(),206);assert.equal((await range.body()).length,64);
  assert.equal((await page.request.get('/api/audio/not-an-asset')).status(),404);
  const highDpi=await browser.newPage({viewport:{width:1365,height:900},deviceScaleFactor:1.5});
  await highDpi.goto(testServer.url);
  await highDpi.locator('.welcome .welcome-start').click();
  await highDpi.waitForSelector('.portrait-slot.current .model[data-model-state=ready]',{timeout:45000});
  await assertPortraitResolution(highDpi);
  await highDpi.locator('.head-stage').screenshot({path:path.join(output,'high-dpi-portrait.png')});
  await highDpi.close();
  console.log('PASS: Firefox 3D models, Talk/Stand, audio switching, Java/SQLite votes, next NPC, mobile layout and OGG range streaming.');
} finally { await browser.close(); await testServer.close(); }

import {firefox,request} from 'playwright';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {repo} from '../server.mjs';
import {startTestServer} from './test-server.mjs';

const password='browser-test-admin-secret-123456';
const server=await startTestServer({adminPassword:password});
const cache=path.join(process.env.LOCALAPPDATA,'ms-playwright');
const executablePath=fs.readdirSync(cache).filter(n=>n.startsWith('firefox-')).sort().reverse()
  .map(n=>path.join(cache,n,'firefox/firefox.exe')).find(file=>fs.existsSync(file));
let browser;
try {
  browser=await firefox.launch({headless:true,executablePath});
  const page=await browser.newPage({viewport:{width:1365,height:1000}});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  assert.equal((await page.request.get(server.apiUrl+'/api/admin/dashboard')).status(),401);
  await page.goto(server.apiUrl+'/admin/');
  await page.locator('#password').fill('wrong');await page.getByRole('button',{name:'Войти',exact:true}).click();
  await page.waitForSelector('[role=alert]');
  await page.locator('#password').fill(password);await page.getByRole('button',{name:'Войти',exact:true}).click();
  await page.waitForSelector('.metrics');
  assert.equal(await page.locator('tbody tr').count(),0);
  const catalogue=await (await page.request.get(server.url+'/api/catalogue')).json();
  for(let n=0;n<4;n++) {
    const visitor=await request.newContext();
    await visitor.get(server.apiUrl+'/api/votes/summary');
    if(n<3) {
      const quest=catalogue.quests[n];
      const response=await visitor.post(server.apiUrl+'/api/votes',{headers:{Origin:server.apiUrl},data:{questID:quest.questID,
        selectedId:quest.variants[n%quest.variants.length].id,variantIds:quest.variants.map(v=>v.id),visitID:crypto.randomUUID()}});
      assert.equal(response.status(),200);
    }
    await visitor.dispose();
  }
  await page.getByRole('button',{name:'Обновить',exact:true}).click();
  await page.waitForFunction(()=>document.querySelectorAll('tbody tr').length===3);
  assert.equal(await page.locator('.metrics article').nth(0).locator('strong').textContent(),'3');
  assert.equal(await page.locator('.metrics article').nth(1).locator('strong').textContent(),'3');
  for(const [label,filename] of [['JSON','results.json'],['Всё в ZIP','results.zip']]) {
    const pending=page.waitForEvent('download');
    await page.getByRole('button',{name:label,exact:true}).click();
    const download=await pending;
    assert.equal(download.suggestedFilename(),filename);
    const bytes=fs.readFileSync(await download.path());
    if(filename.endsWith('.json')) assert.equal(JSON.parse(bytes).summary.votes,3);
    else assert.equal(bytes.subarray(0,2).toString(),'PK');
  }
  await page.evaluate(()=>document.fonts.ready);
  await page.screenshot({path:path.join(repo,'artifacts/voice-vote-preview/admin-desktop.png'),fullPage:true});
  await page.locator('.link').first().click();await page.waitForSelector('.detail tbody tr');
  assert(await page.getByRole('heading',{name:'Выборы по заданиям'}).isVisible());
  await page.screenshot({path:path.join(repo,'artifacts/voice-vote-preview/admin-visitor.png'),fullPage:true});
  await page.getByRole('button',{name:'Закрыть',exact:true}).click();
  await page.setViewportSize({width:390,height:844});
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  await page.screenshot({path:path.join(repo,'artifacts/voice-vote-preview/admin-mobile.png'),fullPage:true});
  await page.getByRole('button',{name:'Выйти',exact:true}).click();await page.waitForSelector('#password');
  assert.equal((await page.request.get(server.apiUrl+'/api/admin/visitors')).status(),401);
  assert.deepEqual(errors,[]);
  console.log('PASS: admin login/logout, protected data, voters-only statistics, visitor detail and responsive layout.');
} finally {await browser?.close();await server.close();}

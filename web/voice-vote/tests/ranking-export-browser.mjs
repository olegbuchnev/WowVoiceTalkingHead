import {firefox} from 'playwright';
import {createServer} from 'vite';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import path from 'node:path';

const root=path.resolve(import.meta.dirname,'..');
const server=await createServer({root,configFile:false,server:{host:'127.0.0.1',port:0}});
let browser;
try {
  await server.listen();const base=`http://127.0.0.1:${server.httpServer.address().port}`;
  browser=await firefox.launch({headless:true,...(process.env.PLAYWRIGHT_FIREFOX_EXECUTABLE?{executablePath:process.env.PLAYWRIGHT_FIREFOX_EXECUTABLE}:{})});
  const page=await browser.newPage();let failing=true;
  const json=JSON.stringify({schemaVersion:1,generatedAt:'2026-10-17T12:00:00Z',groups:[{speakerType:'npc',race:'dwarf',sex:'male',status:'ranked',ranking:['CatQuest','WowVoice','Wayfarer'].map((source,i)=>({rank:i+1,source,basis:'votes',tieGroup:i===0?null:2}))}]});
  const importString=`THR1:${Buffer.from(json).toString('base64url')}.${crypto.createHash('sha256').update(json).digest('hex')}`;
  await page.route('**/api/votes/ranking/export',route=>route.fulfill({status:failing?503:200,contentType:'application/json',body:JSON.stringify(failing?{error:'Unavailable'}:{json,importString})}));
  for(const width of [1365,390]) {
    await page.setViewportSize({width,height:900});
    await page.goto(`${base}/tests/ranking-export-fixture.html`);
    await page.getByRole('button',{name:'Импорт в аддон',exact:true}).click();
    if(failing) {
      await page.getByRole('alert').waitFor();failing=false;
      await page.getByRole('button',{name:'Обновить данные'}).click();
    }
    await page.getByRole('button',{name:'Скопировать строку',exact:true}).waitFor();
    assert.equal(await page.getByLabel('Строка рейтинга').inputValue(),importString);
    const rect=await page.locator('dialog').boundingBox();assert.ok(rect.x>=0 && rect.x+rect.width<=width);
    const copyRect=await page.locator('.ranking-copy').boundingBox();
    const fieldRect=await page.getByLabel('Строка рейтинга').boundingBox();
    await page.evaluate(()=>Object.defineProperty(navigator,'clipboard',{configurable:true,value:{writeText:async text=>{window.copiedRanking=text;}}}));
    await page.getByRole('button',{name:'Скопировать строку',exact:true}).click();
    assert.equal(await page.evaluate(()=>window.copiedRanking),importString);
    await page.getByRole('button',{name:'Скопировано',exact:true}).waitFor();
    assert.deepEqual(await page.locator('dialog').boundingBox(),rect,'Copy confirmation must not move or resize the dialog');
    assert.deepEqual(await page.locator('.ranking-copy').boundingBox(),copyRect,'Copy button must keep its dimensions');
    assert.deepEqual(await page.getByLabel('Строка рейтинга').boundingBox(),fieldRect,'Copy confirmation must not move the string field');
    assert.equal(await page.getByRole('button',{name:'Скачать JSON'}).count(),0);
    const parts=(await page.getByLabel('Строка рейтинга').inputValue()).slice(5).split('.');
    assert.equal(Buffer.from(parts[0],'base64url').toString('utf8'),json);
    assert.equal(crypto.createHash('sha256').update(json).digest('hex'),parts[1]);
    await page.keyboard.press('Escape');assert.equal(await page.locator('dialog').isVisible(),false);
  }
  console.log('Ranking export: error/retry, mobile/desktop, clipboard, THR1 encoding/checksum and Escape passed.');
} finally {await browser?.close();await server.close();}

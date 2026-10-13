import {firefox} from 'playwright';
import {createServer} from 'vite';
import assert from 'node:assert/strict';
import path from 'node:path';

const root=path.resolve(import.meta.dirname,'..');
const server=await createServer({root,configFile:false,server:{host:'127.0.0.1',port:0}});
let browser;
try {
  await server.listen();
  const base=`http://127.0.0.1:${server.httpServer.address().port}`;
  browser=await firefox.launch({headless:true,...(process.env.PLAYWRIGHT_FIREFOX_EXECUTABLE ? {executablePath:process.env.PLAYWRIGHT_FIREFOX_EXECUTABLE} : {})});
  const page=await browser.newPage({viewport:{width:1365,height:900}});
  await page.route('**/*',route=>new URL(route.request().url()).origin===base ? route.continue() : route.abort());
  await page.route('**/layout-fixture',route=>route.fulfill({contentType:'text/html',body:`<!doctype html>
    <html><head><link rel="stylesheet" href="/src/style.css"></head><body>
    <div class="head-stage"><div class="head-viewport"><div class="talking-head">
    <div class="head-background"></div><div class="speech"><h2></h2><div class="quest-text"><p></p></div></div>
    </div></div></div></body></html>`}));
  await page.goto(`${base}/layout-fixture`);
  await page.evaluate(async()=>{
    await document.fonts.load('18px "WoW Morpheus"');
    await document.fonts.load('12px "WoW Friz"');
    await document.fonts.ready;
  });
  const names=['Стен Крепкорук','Интендант Хасна из ордена Серебряного Рассвета',
    'Очень длинное имя персонажа '.repeat(12)];
  for(const width of [1365,390]) {
    await page.setViewportSize({width,height:900});
    for(const [index,name] of names.entries()) {
      const geometry=await page.evaluate(name=>{
        document.querySelector('h2').textContent=name;
        const text=document.querySelector('.quest-text');
        text.querySelector('p').textContent='Тебе причитается награда за верную службу Серебряному Рассвету, путник. '.repeat(50);
        const head=document.querySelector('.talking-head').getBoundingClientRect();
        const rect=text.getBoundingClientRect();
        const heading=document.querySelector('h2').getBoundingClientRect();
        const scale=head.height/155;
        text.scrollTop=text.scrollHeight;
        return {bottom:(rect.bottom-head.top)/scale,top:(rect.top-head.top)/scale,
          height:rect.height/scale,titleHeight:heading.height/scale,scrollTop:text.scrollTop,
          overflow:getComputedStyle(text).overflowY};
      },name);
      assert(geometry.bottom<=140.5,`text must stay above the frame's bottom inset: ${JSON.stringify({width,index,geometry})}`);
      assert(geometry.height>=54,'long names must leave readable description space');
      assert(geometry.scrollTop>0,'the remaining description must stay scrollable');
      assert.equal(geometry.overflow,'auto');
      if(index===0) assert(Math.abs(geometry.height-91)<1,'single-line name keeps the existing text geometry');
      if(index===1) assert(geometry.titleHeight>18,'regression fixture must wrap the NPC name');
    }
  }
  console.log('PASS: single/multiline NPC names keep descriptions inside the talking head on desktop and narrow viewports');
} finally {
  await browser?.close();
  await server.close();
}

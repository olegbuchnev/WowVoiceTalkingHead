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
  browser=await firefox.launch({headless:true,...(process.env.PLAYWRIGHT_FIREFOX_EXECUTABLE?{executablePath:process.env.PLAYWRIGHT_FIREFOX_EXECUTABLE}:{})});
  const page=await browser.newPage();
  await page.route('**/community-fixture',route=>route.fulfill({contentType:'text/html',body:
    '<div id="root"></div><script type="module" src="/tests/community-results-fixture.jsx"></script>'}));
  await page.addInitScript(()=>{
    const original=window.fetch;
    window.communityRequests=[];
    window.fetch=(url,options)=>{
      if(url==='/api/votes/community') window.communityRequests.push({cache:options.cache,credentials:options.credentials});
      return original(url,options);
    };
  });
  let wow=21,fail=false,requests=0;
  await page.route('**/api/votes/community',route=>{
    requests++;
    return route.fulfill({status:fail?503:200,contentType:'application/json',body:JSON.stringify(
      fail?{}:{counts:{WowVoice:wow,CatQuest:30,Wayfarer:40},total:wow+70})});
  });
  const waitForCount=count=>page.waitForFunction(value=>
    document.querySelector('.community-sector')?.getAttribute('aria-label')?.includes(String(value)),count);
  await page.goto(`${base}/community-fixture`);
  await waitForCount(21);
  assert.equal(requests,1);
  wow=25;
  await page.reload();
  await waitForCount(25);
  assert.equal(requests,2);
  wow=28;
  await page.evaluate(()=>window.dispatchEvent(new PageTransitionEvent('pageshow',{persisted:true})));
  await waitForCount(28);
  assert.equal(requests,3);
  fail=true;
  await page.reload();
  await page.locator('.community-message button').waitFor();
  fail=false;wow=29;
  await page.locator('.community-message button').click();
  await waitForCount(29);
  assert.equal(requests,5);
  assert.deepEqual(await page.evaluate(()=>window.communityRequests),[
    {cache:'no-store',credentials:'omit'},{cache:'no-store',credentials:'omit'}
  ]);
  console.log('Community results: fresh mount, reload, back/forward restoration and retry passed.');
} finally {await browser?.close();await server.close();}

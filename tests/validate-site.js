const assert = require('assert/strict');
const fs = require('fs'), path = require('path'), os = require('os');
const { spawnSync } = require('child_process');
const { createHash } = require('crypto');

(async () => {
  const { artifactKind, formatArtifactSize } = await import('../tools/release-assets.mjs');
  assert.equal(artifactKind('WowVoiceTalkingHead-1.2-lite.zip'), 'lite');
  assert.equal(artifactKind('WowVoiceTalkingHead-1.2-addon-only.zip'), 'addon');
  assert.equal(artifactKind('WowVoiceTalkingHead-1.2.zip'), 'full');
  assert.equal(artifactKind('TalkingHeadRu-1.2.5-forever.zip'), 'addon');
  assert.equal(artifactKind('TalkingHeadRu-1.2.5-forever-addon-only.zip'), 'addon');
  assert.equal(artifactKind('TalkingHeadRu-1.2.5-forever-full.zip'), 'full');
  assert.equal(artifactKind('source.zip'), undefined);
  assert.equal(formatArtifactSize(444444), '444,4 КБ');
  assert.equal(formatArtifactSize(555555555), '555,6 МБ');
  assert.throws(() => formatArtifactSize(0));
  // Use a temporary site root with fake published releases, not live GitHub.
  const root = path.resolve(__dirname, '..');
  // Exercise the real bootstrap without making analytics requests.
  const siteScript = fs.readFileSync(path.join(root, 'site/site.js'), 'utf8');
  const endpoint = 'https://tove2889.goatcounter.com/count';
  for (const [origin, pathname, configured, enabled] of [
    ['https://olegbuchnev.github.io', '/WowVoiceTalkingHead/', true, true],
    ['https://olegbuchnev.github.io', '/WowVoiceTalkingHead/guide.html', true, true],
    ['https://olegbuchnev.github.io', '/WowVoiceTalkingHead/', false, false],
    ['http://localhost:8000', '/WowVoiceTalkingHead/', true, false],
    ['null', '/C:/site/index.html', true, false],
    ['https://olegbuchnev.github.io', '/another-project/', true, false],
  ]) {
    const appended = [];
    let onLoad, bound = 0;
    const context = {
      window: { location: { origin, pathname }, goatcounter: { bind_events() { bound++; } } },
      document: {
        body: { dataset: configured ? { clickAnalytics: endpoint } : {} },
        head: { appendChild(script) { appended.push(script); } },
        createElement() { return { dataset: {}, addEventListener(name, fn) { assert.equal(name, 'load'); onLoad = fn; } }; },
        querySelector() { return null; }, querySelectorAll() { return []; },
      },
    };
    require('node:vm').runInNewContext(siteScript, context);
    assert.equal(appended.length, enabled ? 1 : 0);
    assert.equal(bound, 0);
    if (enabled) {
      assert.equal(appended[0].dataset.goatcounter, endpoint);
      assert.deepEqual(JSON.parse(appended[0].dataset.goatcounterSettings), { no_onload: true });
      onLoad();
      assert.equal(bound, 1);
      delete context.window.goatcounter;
      assert.doesNotThrow(onLoad, 'A blocked counter must not break the site');
    }
  }
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'wowvoice-site-'));
  try {
    for (const dir of ['tools', 'site', 'docs/images']) fs.mkdirSync(path.join(fixture, dir), {recursive:true});
    for (const file of ['tools/build-site.mjs', 'tools/release-assets.mjs', 'site/style.css', 'site/site.js', 'USER_README.md']) {
      let text = fs.readFileSync(path.join(root, file), 'utf8');
      if (file.endsWith('build-site.mjs')) {
        // Resolve the real dependency without copying node_modules or using a junction.
        const marked = require('url').pathToFileURL(require.resolve('marked')).href;
        text = text.replace("from 'marked'", `from '${marked}'`);
      }
      fs.writeFileSync(path.join(fixture,file),text);
    }
    const repo='https://github.com/olegbuchnev/WowVoiceTalkingHead';
    const urls = {full:`${repo}/releases/download/v1/WowVoiceTalkingHead-1.zip`,
      addon:`${repo}/releases/download/v2/WowVoiceTalkingHead-2-addon-only.zip`,
      lite:`${repo}/releases/download/v3/WowVoiceTalkingHead-3-lite.zip`};
    const assets = Object.entries(urls).map(([kind,url]) => ({browser_download_url:url,
      state:'uploaded', updated_at:'2026-09-28T00:00:00Z', size:{full:700000000,addon:444444,lite:555555555}[kind]}));
    const mock = `globalThis.fetch = async url => {
      const u = String(url);
      if (u.endsWith('/releases/tags/v2')) return new Response(JSON.stringify({
        published_at:'2026-09-27T00:00:00Z', assets:${JSON.stringify(assets)}
      }));
      if (u.endsWith('/src/CatQuestAudio.lua')) {
        if (!u.includes('/v2/')) throw Error('wrong compatibility tag');
        return new Response('WowVoiceCatQuestAudio = {sourceVersion = "0.2.2"}');
      }
      if (u.endsWith('/src/WayfarerSource.lua')) {
        if (!u.includes('/v2/')) throw Error('wrong Wayfarer compatibility tag');
        return new Response('local AUDITED_CORE_VERSION = "0.7.0"');
      }
      if (u.endsWith('/src/WayfarerAudio.lua')) {
        if (!u.includes('/v2/')) throw Error('wrong Wayfarer pack tag');
        return new Response('WowVoiceWayfarerAudio = {packs={["Wayfarer_Voices_Alliance"] = {version="3.1.0"}}}');
      }
      throw Error('Unexpected network request '+u);
    };`;
    fs.writeFileSync(path.join(fixture,'mock.mjs'),mock);
    const intro='# Test WowVoice\n\nDescription.\n\n';
    const body=`\n[Addon](${urls.addon})\n\n`
      + ['Три библиотеки озвучки','Установка','Возможности','Очередь озвучки','Настройки','Подключение библиотек','Авторы и озвучка','Что нового']
        .map(name=>`## ${name}\n\nContent. [Addon](${urls.addon})\n`
          + (name === 'Установка' ? '\n> **⚠ Если раньше скачивали наш полный архив**\n>\n> Удалите старую папку.\n' : '')
          + (name === 'Три библиотеки озвучки' ? '\n![Head](docs/images/head.png)\n' : '')
          + (name === 'Очередь озвучки' ? '\n<p class="feature-image"><img src="docs/images/queue.png" width="320" alt="Queue"></p>\n' : '')).join('\n');
    fs.writeFileSync(path.join(fixture,'docs/images/head.png'),Buffer.from([1]));
    fs.writeFileSync(path.join(fixture,'docs/images/queue.png'),Buffer.from([2]));
    const imageURL = (name, bytes) => `images/${name}.${createHash('sha256').update(Buffer.from(bytes)).digest('hex')}.png`;
    const headURL = imageURL('head', [1]), queueURL = imageURL('queue', [2]);
    fs.appendFileSync(path.join(fixture,'USER_README.md'), '\n\n![Head](docs/images/head.png)\n\n<img src=\'docs/images/queue.png\' alt="Queue">\n');
    for (const withLite of [true,false]) {
      fs.writeFileSync(path.join(fixture,'README.md'),intro+(withLite?`[Lite](${urls.lite}) [Full](${urls.full})\n`:'')+body);
      const result=spawnSync(process.execPath,['--import',require('url').pathToFileURL(path.join(fixture,'mock.mjs')).href,path.join(fixture,'tools/build-site.mjs')],{encoding:'utf8'});
      assert.equal(result.status,0,result.stderr);
      for (const name of ['index.html','guide.html']) {
        const html=fs.readFileSync(path.join(fixture,'artifacts/site',name),'utf8');
        assert(html.includes(`data-click-analytics="${endpoint}"`));
        assert.equal((html.match(/data-goatcounter-click="curseforge-open"/g) || []).length, 1);
        assert(html.includes('data-goatcounter-no-session="1"'));
        assert(html.includes('444,4 КБ') && !html.includes('700 МБ') && !html.includes('555,6 МБ'));
        assert.equal((html.match(/class="download-card"/g)||[]).length,1);
        assert.equal((html.match(/class="optional-voices"/g)||[]).length,3);
        assert(html.includes('Проверено с Voices 0.2.2'));
        assert(html.includes('Проверены Wayfarer 0.7.0 и модули 3.1.0'));
        for (const slug of ['wowvoice-classic', 'catquest', 'catquest-voices', 'wayfarer-russian-voiceover',
          'wayfarer-voices-alliance', 'wayfarer-voices-horde', 'wayfarer-voices-shared-quests']) {
          assert(html.includes(`https://www.curseforge.com/wow/addons/${slug}/files/all?page=1&amp;pageSize=20&amp;gameVersionTypeId=88568&amp;showAlphaFiles=hide`));
        }
        assert(!html.includes(`href="${urls.full}"`));
        assert(html.includes(`href="${urls.addon}"`));
        assert(html.includes('class="installation-notice"'), 'Migration notice stays visible on both pages');
        const script = fs.readFileSync(path.join(fixture, 'site/site.js'));
        const scriptURL = `site.${createHash('sha256').update(script).digest('hex')}.js`;
        assert(html.includes(`<script src="${scriptURL}" defer></script>`));
        assert.deepEqual(fs.readFileSync(path.join(fixture, 'artifacts/site', scriptURL)), script);
        assert(!html.includes('Зеркало на pCloud'));
        assert(html.includes('<time datetime="2026-09-28T00:00:00.000Z">28.09.2026</time>'));
        assert.equal((html.match(/Обновлён <time/g) || []).length, 1, 'Only the addon card shows the addon update date');
      }
      const html=fs.readFileSync(path.join(fixture,'artifacts/site/index.html'),'utf8');
      assert(html.indexOf('class="voice-feature"') < html.indexOf('class="screenshots"'));
      assert.equal((html.match(/<img /g)||[]).length,2,'Gallery and queue images must appear once each');
      assert(html.includes(`src="${headURL}"`), 'Markdown screenshots must use content-addressed filenames');
      assert(html.includes(`src="${queueURL}" width="320"`), 'Inline HTML screenshots must use the same hashed assets');
      assert(!html.includes('src="docs/images/'), 'Inline README image paths must work on Pages');
      assert.deepEqual(fs.readFileSync(path.join(fixture,'artifacts/site',queueURL)), Buffer.from([2]));
      const guideHtml = fs.readFileSync(path.join(fixture,'artifacts/site/guide.html'), 'utf8');
      assert(guideHtml.includes(`src="${headURL}"`) && guideHtml.includes(`src='${queueURL}'`), 'The guide must share hashed Markdown and HTML images');
    }
    const run = (...args) => spawnSync(process.execPath,['--import',require('url').pathToFileURL(path.join(fixture,'mock.mjs')).href,path.join(fixture,'tools/build-site.mjs'),...args],{encoding:'utf8'});
    // Replace bytes at the same source path: only this image gets a new URL.
    fs.writeFileSync(path.join(fixture,'docs/images/queue.png'), Buffer.from([3]));
    const changed = run();
    assert.equal(changed.status, 0, changed.stderr);
    const changedURL = imageURL('queue', [3]);
    const changedHtml = fs.readFileSync(path.join(fixture,'artifacts/site/index.html'), 'utf8');
    assert(changedHtml.includes(`src="${changedURL}"`) && !changedHtml.includes(queueURL));
    assert(changedHtml.includes(`src="${headURL}"`), 'An unchanged image keeps its URL between builds');
    assert.deepEqual(fs.readFileSync(path.join(fixture,'artifacts/site',changedURL)), Buffer.from([3]));
    fs.writeFileSync(path.join(fixture,'mock.mjs'),mock.replace("published_at:", "draft:true, published_at:"));
    assert.match(run().stderr,/Download is not a published release asset/);
    fs.writeFileSync(path.join(fixture,'mock.mjs'),mock.replace("return new Response('WowVoiceCatQuestAudio", "return new Response('', {status:404}); return new Response('WowVoiceCatQuestAudio"));
    assert.match(run().stderr,/Cannot verify CatQuest integration in v2/);
    fs.writeFileSync(path.join(fixture,'mock.mjs'),mock.replace("return new Response('local AUDITED_CORE_VERSION", "return new Response('', {status:404}); return new Response('local AUDITED_CORE_VERSION"));
    assert.equal(run().status, 0, 'Older releases without Wayfarer remain buildable');
    assert.equal((fs.readFileSync(path.join(fixture,'artifacts/site/index.html'),'utf8').match(/class="optional-voices"/g)||[]).length, 2);
    const previewRoot=path.join(fixture,'artifacts/site-preview');
    fs.mkdirSync(path.join(previewRoot,'downloads'),{recursive:true});
    const preview={version:'1.3.0-forever-preview',releaseVersion:'1.3.0-forever',addon:'TalkingHeadRu-1.3.0-forever-preview.zip',catQuestVersion:'0.2.2',wayfarer:{core:'0.7.0',packs:['3.1.0']}};
    fs.writeFileSync(path.join(previewRoot,'preview.json'),JSON.stringify(preview));
    fs.writeFileSync(path.join(previewRoot,'downloads',preview.addon),Buffer.alloc(23456));
    fs.writeFileSync(path.join(fixture,'mock.mjs'),"globalThis.fetch = () => {throw Error('Preview must work offline')};");
    const result=run('--preview');
    assert.equal(result.status,0,result.stderr);
    const previewHtml=fs.readFileSync(path.join(previewRoot,'index.html'),'utf8');
    for (const name of ['index.html', 'guide.html']) {
      assert(!fs.readFileSync(path.join(previewRoot, name), 'utf8').includes('data-click-analytics='));
    }
    assert(previewHtml.includes('Релиз ещё не опубликован') && previewHtml.includes('23,5 КБ'));
    assert(previewHtml.includes('Аддон: 1.3.0-forever'));
    assert(previewHtml.includes('Проверены Wayfarer 0.7.0 и модули 3.1.0'));
    assert(!previewHtml.includes(urls.full) && !previewHtml.includes(urls.addon));
    assert.equal((previewHtml.match(new RegExp(`href="downloads/${preview.addon}"`,'g'))||[]).length,9);
    assert(previewHtml.includes(`href="downloads/${preview.addon}"`));
    assert(previewHtml.includes(`src="${changedURL}"`) && previewHtml.includes(`src="${headURL}"`));
    assert.deepEqual(fs.readFileSync(path.join(previewRoot,changedURL)), Buffer.from([3]));
    console.log('PASS: one addon download, exact size and release date, three matching voice sections with Forever links and visible migration notice');
    console.log('PASS: unpublished or unverifiable downloads rejected; offline preview needs only the addon ZIP, no bundled audio');
    console.log('PASS: click-only analytics enabled on the published site, excluded from preview and local copies');
    console.log('PASS: Markdown/HTML/guide screenshots use hashed filenames; replacing image bytes changes its URL in published and preview builds');
  } finally {
    assert.equal(path.dirname(fixture),path.resolve(os.tmpdir()));
    assert(path.basename(fixture).startsWith('wowvoice-site-'));
    fs.rmSync(fixture,{recursive:true,force:true});
  }
})().catch(error => { console.error(error); process.exitCode=1; });

const assert = require('assert/strict');
const fs = require('fs'), path = require('path'), os = require('os');
const { spawnSync } = require('child_process');
const { createHash } = require('crypto');

(async () => {
  const { artifactKind, formatArtifactSize } = await import('../tools/release-assets.mjs');
  assert.equal(artifactKind('WowVoiceTalkingHead-1.2-lite.zip'), 'lite');
  assert.equal(artifactKind('WowVoiceTalkingHead-1.2-addon-only.zip'), 'addon');
  assert.equal(artifactKind('WowVoiceTalkingHead-1.2.zip'), 'full');
  assert.equal(artifactKind('source.zip'), undefined);
  assert.equal(formatArtifactSize(444444), '444,4 КБ');
  assert.equal(formatArtifactSize(555555555), '555,6 МБ');
  assert.throws(() => formatArtifactSize(0));
  // Use a temporary site root with fake published releases, not live GitHub.
  const root = path.resolve(__dirname, '..');
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'wowvoice-site-'));
  try {
    for (const dir of ['tools', 'site', 'docs/images']) fs.mkdirSync(path.join(fixture, dir), {recursive:true});
    for (const file of ['tools/build-site.mjs', 'tools/release-assets.mjs', 'site/style.css', 'site/site.js', 'site/audio-releases.json', 'USER_README.md']) {
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
      if (u.includes('/releases/tags/')) return new Response(JSON.stringify({
        published_at:'2026-09-27T00:00:00Z', assets:${JSON.stringify(assets)}
      }));
      if (u.endsWith('/src/CatQuestAudio.lua')) {
        if (!u.includes('/v1/') && !u.includes('/v2/')) throw Error('wrong compatibility tag');
        return new Response('WowVoiceCatQuestAudio = {sourceVersion = "0.2.2"}');
      }
      if (u.includes('/v1/') && u.endsWith('.toc')) return new Response('## X-Source-Version: 1.0.1');
      throw Error('Unexpected network request '+u);
    };`;
    fs.writeFileSync(path.join(fixture,'mock.mjs'),mock);
    const intro='# Test WowVoice\n\nDescription.\n\n';
    const body=`\n[Full](${urls.full})\n[Addon](${urls.addon})\n[Mirror](https://e.pcloud.link/example)\n\n`
      + ['Две озвучки на выбор','Установка','Возможности','Очередь озвучки','Настройки','Совместимость с CatQuest','Авторы и озвучка','Что нового']
        .map(name=>`## ${name}\n\nContent. [Full](${urls.full}) [Addon](${urls.addon})\n`
          + (name === 'Две озвучки на выбор' ? '\n![Head](docs/images/head.png)\n' : '')
          + (name === 'Очередь озвучки' ? '\n<p class="feature-image"><img src="docs/images/queue.png" width="320" alt="Queue"></p>\n' : '')).join('\n');
    fs.writeFileSync(path.join(fixture,'docs/images/head.png'),Buffer.from([1]));
    fs.writeFileSync(path.join(fixture,'docs/images/queue.png'),Buffer.from([2]));
    const imageURL = (name, bytes) => `images/${name}.${createHash('sha256').update(Buffer.from(bytes)).digest('hex')}.png`;
    const headURL = imageURL('head', [1]), queueURL = imageURL('queue', [2]);
    fs.appendFileSync(path.join(fixture,'USER_README.md'), '\n\n![Head](docs/images/head.png)\n\n<img src=\'docs/images/queue.png\' alt="Queue">\n');
    for (const withLite of [true,false]) {
      fs.writeFileSync(path.join(fixture,'README.md'),intro+(withLite?`[Lite](${urls.lite})\n`:'')+body);
      const result=spawnSync(process.execPath,['--import',require('url').pathToFileURL(path.join(fixture,'mock.mjs')).href,path.join(fixture,'tools/build-site.mjs')],{encoding:'utf8'});
      assert.equal(result.status,0,result.stderr);
      for (const name of ['index.html','guide.html']) {
        const html=fs.readFileSync(path.join(fixture,'artifacts/site',name),'utf8');
        assert(html.includes('700 МБ') && html.includes('444,4 КБ'));
        assert.equal((html.match(/class="download-card"/g)||[]).length,2);
        assert(!html.includes('555,6 МБ'));
        assert(html.includes('CatQuest Voices 0.2.2') && html.includes('curseforge.com/wow/addons/catquest'));
        assert(html.includes(`href="${urls.full}"`));
        assert(html.includes('<script src="site.js" defer></script>'));
        assert.equal(fs.readFileSync(path.join(fixture,'artifacts/site/site.js'),'utf8'),
          fs.readFileSync(path.join(root,'site/site.js'),'utf8'));
        assert(html.includes('Зеркало на pCloud'));
        assert(html.includes('<time datetime="2026-08-13">13.08.2026</time>'), 'Audio release date must not follow artifact uploads');
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
    fs.writeFileSync(path.join(fixture,'mock.mjs'),mock.replace('X-Source-Version: 1.0.1','X-Source-Version: 9.0.0'));
    const unknownAudio = run();
    assert.equal(unknownAudio.status,0,unknownAudio.stderr);
    const unknownHtml = fs.readFileSync(path.join(fixture,'artifacts/site/index.html'),'utf8');
    assert(unknownHtml.includes('Дата не указана') && !unknownHtml.includes('13.08.2026'), 'Unknown audio must not inherit another version date');
    fs.writeFileSync(path.join(fixture,'mock.mjs'),mock.replace("return new Response('WowVoiceCatQuestAudio", "if (u.includes('/v1/')) return new Response('', {status:404}); return new Response('WowVoiceCatQuestAudio"));
    assert.match(run().stderr,/Cannot verify CatQuest integration in v1/);
    fs.writeFileSync(path.join(fixture,'mock.mjs'),mock.replace("return new Response('WowVoiceCatQuestAudio", "if (u.includes('/v1/')) return new Response('sourceVersion = \"0.2.0\"'); return new Response('WowVoiceCatQuestAudio"));
    assert.match(run().stderr,/different CatQuest versions/);
    const previewRoot=path.join(fixture,'artifacts/site-preview');
    fs.mkdirSync(path.join(previewRoot,'downloads'),{recursive:true});
    const preview={version:'preview',full:'WowVoiceTalkingHead-preview.zip',addon:'WowVoiceTalkingHead-preview-addon-only.zip',catQuestVersion:'0.2.2',wowVoiceVersion:'1.0.1'};
    fs.writeFileSync(path.join(previewRoot,'preview.json'),JSON.stringify(preview));
    fs.writeFileSync(path.join(previewRoot,'downloads',preview.full),Buffer.alloc(1234567));
    fs.writeFileSync(path.join(previewRoot,'downloads',preview.addon),Buffer.alloc(23456));
    fs.writeFileSync(path.join(fixture,'mock.mjs'),"globalThis.fetch = () => {throw Error('Preview must work offline')};");
    const result=run('--preview');
    assert.equal(result.status,0,result.stderr);
    const previewHtml=fs.readFileSync(path.join(previewRoot,'index.html'),'utf8');
    assert(previewHtml.includes('Релиз ещё не опубликован') && previewHtml.includes('1,2 МБ') && previewHtml.includes('23,5 КБ'));
    assert(!previewHtml.includes(urls.full) && !previewHtml.includes(urls.addon));
    assert.equal((previewHtml.match(new RegExp(`href="downloads/${preview.full}"`,'g'))||[]).length,9);
    assert(previewHtml.includes(`href="downloads/${preview.addon}"`));
    assert(previewHtml.includes(`src="${changedURL}"`) && previewHtml.includes(`src="${headURL}"`));
    assert.deepEqual(fs.readFileSync(path.join(previewRoot,changedURL)), Buffer.from([3]));
    console.log('PASS: two published downloads, exact artifact sizes, independent release metadata, legacy lite links ignored and optional external audio');
    console.log('PASS: incompatible published downloads rejected; offline preview uses local archive sizes and links');
    console.log('PASS: Markdown/HTML/guide screenshots use hashed filenames; replacing image bytes changes its URL in published and preview builds');
  } finally {
    assert.equal(path.dirname(fixture),path.resolve(os.tmpdir()));
    assert(path.basename(fixture).startsWith('wowvoice-site-'));
    fs.rmSync(fixture,{recursive:true,force:true});
  }
})().catch(error => { console.error(error); process.exitCode=1; });

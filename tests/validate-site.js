const assert = require('assert/strict');
const fs = require('fs'), path = require('path'), os = require('os');
const { spawnSync } = require('child_process');

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
    for (const file of ['tools/build-site.mjs', 'tools/release-assets.mjs', 'site/style.css', 'USER_README.md']) {
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
      if (u.includes('/v1/') && u.endsWith('.toc')) return new Response('## X-Source-Version: 0.2.0');
      throw Error('Unexpected network request '+u);
    };`;
    fs.writeFileSync(path.join(fixture,'mock.mjs'),mock);
    const intro='# Test WowVoice\n\nDescription.\n\n';
    const body=`\n[Full](${urls.full})\n[Addon](${urls.addon})\n[Mirror](https://e.pcloud.link/example)\n\n`
      + ['Две озвучки на выбор','Установка','Возможности','Настройки','Совместимость с CatQuest','Авторы и озвучка']
        .map(name=>`## ${name}\n\nContent. [Full](${urls.full}) [Addon](${urls.addon})\n`
          + (name === 'Две озвучки на выбор' ? '\n![Head](docs/images/head.png)\n' : '')).join('\n');
    fs.writeFileSync(path.join(fixture,'docs/images/head.png'),Buffer.from([1]));
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
        assert(html.includes('Зеркало полного комплекта'));
      }
      const html=fs.readFileSync(path.join(fixture,'artifacts/site/index.html'),'utf8');
      assert(html.indexOf('class="voice-feature"') < html.indexOf('class="screenshots"'));
      assert.equal((html.match(/<img /g)||[]).length,1,'Gallery image must not be duplicated inside feature section');
    }
    const run = (...args) => spawnSync(process.execPath,['--import',require('url').pathToFileURL(path.join(fixture,'mock.mjs')).href,path.join(fixture,'tools/build-site.mjs'),...args],{encoding:'utf8'});
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
    assert.equal((previewHtml.match(new RegExp(`href="downloads/${preview.full}"`,'g'))||[]).length,7);
    assert(previewHtml.includes(`href="downloads/${preview.addon}"`));
    console.log('PASS: two published downloads, exact artifact sizes, independent release metadata, legacy lite links ignored and optional external audio');
    console.log('PASS: incompatible published downloads rejected; offline preview uses local archive sizes and links');
  } finally {
    assert.equal(path.dirname(fixture),path.resolve(os.tmpdir()));
    assert(path.basename(fixture).startsWith('wowvoice-site-'));
    fs.rmSync(fixture,{recursive:true,force:true});
  }
})().catch(error => { console.error(error); process.exitCode=1; });

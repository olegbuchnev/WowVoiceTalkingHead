import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Marked } from 'marked';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const output = path.join(root, 'artifacts/site');
const repository = 'https://github.com/olegbuchnev/WowVoiceTalkingHead';
const readme = await fs.readFile(path.join(root, 'README.md'), 'utf8');
const guide = await fs.readFile(path.join(root, 'USER_README.md'), 'utf8');
const escape = text => text.replace(/[&<>"']/g, char => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
}[char]));
const markdown = new Marked({
  walkTokens(token) {
    if (token.type !== 'link' && token.type !== 'image') return;
    if (/^(?:https?:|mailto:|#)/.test(token.href)) return;
    if (token.href.startsWith('docs/images/')) token.href = token.href.replace('docs/', '');
    else if (token.href === 'USER_README.md') token.href = 'guide.html';
    else token.href = `${repository}/blob/main/${token.href}`;
  },
  renderer: {
    heading({ tokens, depth, text }) {
      const id = text.toLowerCase().replace(/[^\p{L}\p{N}\s_-]/gu, '').replace(/\s+/g, '-');
      return `<h${depth} id="${escape(id)}">${this.parser.parseInline(tokens)}</h${depth}>\n`;
    },
  },
});
const tokens = markdown.lexer(readme);
const title = tokens.find(token => token.type === 'heading' && token.depth === 1)?.text;
const intro = tokens.find(token => token.type === 'paragraph')?.raw;
const links = [...readme.matchAll(/\]\((https:\/\/[^\s)]+)\)/g)].map(match => match[1]);
const full = links.find(link => /\/releases\/download\/[^/]+\/[^/]+\.zip$/.test(link) && !link.endsWith('-addon-only.zip'));
const addon = links.find(link => link.endsWith('-addon-only.zip'));
const mirror = links.find(link => link.startsWith('https://e.pcloud.link/'));
if (!title || !intro || !full || !addon || !mirror) throw Error('README is missing the title, introduction or download links');
// Resolve metadata for the exact downloads in README, which may use different releases.
// Keep API calls in the build; visitors do not need JavaScript or a GitHub API request.
const releases = new Map();
async function artifactInfo(url) {
  const prefix = `${repository}/releases/download/`;
  if (!url.startsWith(prefix)) throw Error(`Unexpected download URL: ${url}`);
  const tag = decodeURIComponent(url.slice(prefix.length).split('/')[0]);
  if (!releases.has(tag)) {
    const headers = { Accept: 'application/vnd.github+json', 'User-Agent': 'WowVoice-Pages' };
    if (process.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
    const response = await fetch(`https://api.github.com/repos/olegbuchnev/WowVoiceTalkingHead/releases/tags/${encodeURIComponent(tag)}`, {
      headers, signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) throw Error(`Cannot load release ${tag}: HTTP ${response.status}`);
    releases.set(tag, await response.json());
  }
  const release = releases.get(tag);
  const asset = release.assets?.find(item => item.browser_download_url === url);
  if (release.draft || release.prerelease || !release.published_at || asset?.state !== 'uploaded') {
    throw Error(`Download is not a published release asset: ${url}`);
  }
  // Draft assets may be uploaded before publication, or replaced afterwards.
  const timestamps = [release.published_at, asset.updated_at].map(value => Date.parse(value));
  if (timestamps.some(value => !Number.isFinite(value))) throw Error(`Invalid publication date: ${url}`);
  const date = new Date(Math.max(...timestamps));
  const dateText = new Intl.DateTimeFormat('ru-RU', {
    day: '2-digit', month: '2-digit', year: 'numeric', timeZone: 'UTC',
  }).format(date);
  return `<p class="artifact-meta"><a href="${escape(`${repository}/releases/tag/${encodeURIComponent(tag)}`)}" aria-label="Изменения в версии ${escape(tag.replace(/^v/, ''))}">Версия ${escape(tag.replace(/^v/, ''))}</a><br>Обновлён <time datetime="${date.toISOString()}">${dateText}</time></p>`;
}
const fullInfo = await artifactInfo(full);
const addonInfo = await artifactInfo(addon);
const screenshots = tokens.filter(token => token.type === 'paragraph' && token.tokens?.[0]?.type === 'image');
if (!screenshots.length) throw Error('README is missing screenshots');
const sections = new Map();
let current;
for (const token of tokens) {
  if (token.type === 'heading' && token.depth === 2) {
    current = token.text;
    sections.set(current, []);
  } else if (token.type === 'hr') current = undefined;
  else if (current) sections.get(current).push(token.raw);
}
function section(name, id) {
  if (!sections.has(name)) throw Error(`README section missing: ${name}`);
  return `<section aria-labelledby="${id}"><h2 id="${id}">${escape(name)}</h2>${markdown.parse(sections.get(name).join(''))}</section>`;
}
function page(content, isGuide = false) {
  return `<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="Русская озвучка квестов для WoW Forever Beta. Скачать WowVoice TalkingHead, установить аддон и настроить воспроизведение.">
  <meta name="theme-color" content="#ffffff">
  <title>${isGuide ? 'Инструкция — ' : ''}${escape(title)}</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <a class="skip-link" href="#content">Перейти к содержанию</a>
  <div class="layout">
    <header class="sidebar">
      <a class="brand" href="./">WowVoice<span>TalkingHead</span></a>
      <p class="tagline">Русская озвучка квестов<br>для WoW Forever Beta</p>
      <div class="downloads" aria-label="Скачать аддон">
        <div class="download-card" role="group" aria-label="Полный архив со звуками">
          <a class="button primary" href="${escape(full)}">Скачать полный архив <span aria-hidden="true">↓</span></a>
          <div class="download-info">
            <p class="download-note">Для первой установки · со звуками</p>
            ${fullInfo}
          </div>
        </div>
        <div class="download-card" role="group" aria-label="Обновление аддона без звуков">
          <a class="button" href="${escape(addon)}">Обновить аддон <span aria-hidden="true">↓</span></a>
          <div class="download-info">
            <p class="download-note">Без звуков · addon-only</p>
            ${addonInfo}
          </div>
        </div>
        <a class="mirror" href="${escape(mirror)}">Зеркало на pCloud ↗</a>
      </div>
      <nav aria-label="Разделы сайта">
        <a href="${isGuide ? './' : ''}#installation">Установка</a>
        <a href="${isGuide ? './' : ''}#features">Возможности</a>
        <a href="guide.html"${isGuide ? ' aria-current="page"' : ''}>Подробная инструкция</a>
      </nav>
      <a class="source-link" href="${repository}">Проект на GitHub ↗</a>
    </header>
    <main id="content">${content}
      <footer><a href="${repository}/issues">Сообщить об ошибке</a><span aria-hidden="true">·</span><a href="${repository}">Исходный код</a></footer>
    </main>
  </div>
</body>
</html>
`;
}
const gallery = markdown.parse(screenshots.map(token => token.raw).join('\n\n'));
const content = `<div class="intro"><p class="eyebrow">WoW Forever Beta</p><h1>Квесты с русской озвучкой</h1>${markdown.parse(intro)}</div>
  <div class="screenshots">${gallery}</div>
  ${section('Установка', 'installation')}
  ${section('Возможности', 'features')}
  ${section('Настройки', 'settings')}
  ${section('Совместимость с CatQuest', 'catquest')}
  ${section('Авторы и озвучка', 'credits')}`;
await fs.mkdir(path.join(output, 'images'), { recursive: true });
await fs.writeFile(path.join(output, 'index.html'), page(content));
await fs.writeFile(path.join(output, 'guide.html'), page(markdown.parse(guide), true));
await fs.copyFile(path.join(root, 'site/style.css'), path.join(output, 'style.css'));
for (const screenshot of screenshots) {
  const image = screenshot.tokens[0].href;
  if (!/^docs\/images\/[^/]+\.png$/.test(image)) throw Error(`Unexpected screenshot path: ${image}`);
  await fs.copyFile(path.join(root, image), path.join(output, 'images', path.basename(image)));
}
console.log(`Built GitHub Pages site: ${output}`);

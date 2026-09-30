import fs from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { Marked } from 'marked';
import { artifactKind, formatArtifactSize } from './release-assets.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const previewMode = process.argv.includes('--preview');
const output = path.join(root, previewMode ? 'artifacts/site-preview' : 'artifacts/site');
const preview = previewMode ? JSON.parse(await fs.readFile(path.join(output, 'preview.json'), 'utf8')) : null;
const repository = 'https://github.com/olegbuchnev/WowVoiceTalkingHead';
const readme = await fs.readFile(path.join(root, 'README.md'), 'utf8');
const guide = await fs.readFile(path.join(root, 'USER_README.md'), 'utf8');
const escape = text => text.replace(/[&<>"']/g, char => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
}[char]));
const imageAssets = new Map();
const imageURL = source => {
  const asset = imageAssets.get(source);
  if (!asset) throw Error(`Unindexed screenshot: ${source}`);
  return asset.url;
};
const markdown = new Marked({
  walkTokens(token) {
    if (token.type !== 'link' && token.type !== 'image') return;
    if (previewMode && token.type === 'link') {
      if (token.href === full) token.href = fullInfo.url;
      else if (token.href === addon) token.href = addonInfo.url;
      if (token.href.startsWith('downloads/')) return;
    }
    if (/^(?:https?:|mailto:|#)/.test(token.href)) return;
    if (token.href.startsWith('docs/images/')) token.href = imageURL(token.href);
    else if (token.href === 'USER_README.md') token.href = 'guide.html';
    else token.href = `${repository}/blob/main/${token.href}`;
  },
  renderer: {
    html({ text }) {
      return text.replace(/\bsrc=(["'])(docs\/images\/[^"']+)\1/g,
        (_, quote, source) => `src=${quote}${escape(imageURL(source))}${quote}`);
    },
    heading({ tokens, depth, text }) {
      const id = text.toLowerCase().replace(/[^\p{L}\p{N}\s_-]/gu, '').replace(/\s+/g, '-');
      return `<h${depth} id="${escape(id)}">${this.parser.parseInline(tokens)}</h${depth}>\n`;
    },
  },
});
const tokens = markdown.lexer(readme);
const imagePaths = new Set();
markdown.walkTokens([...tokens, ...markdown.lexer(guide)], token => {
  if ((token.type === 'image' || token.type === 'link') && token.href.startsWith('docs/images/')) {
    imagePaths.add(token.href);
  }
  if (token.type === 'html') {
    for (const match of token.text.matchAll(/\bsrc=(["'])(docs\/images\/[^"']+)\1/g)) imagePaths.add(match[2]);
  }
});
for (const image of imagePaths) {
  if (!/^docs\/images\/[^/]+\.png$/.test(image)) throw Error(`Unexpected screenshot path: ${image}`);
  const bytes = await fs.readFile(path.join(root, image));
  const hash = createHash('sha256').update(bytes).digest('hex');
  const name = `${path.basename(image, '.png')}.${hash}.png`;
  imageAssets.set(image, { url: `images/${name}`, bytes });
}
const title = tokens.find(token => token.type === 'heading' && token.depth === 1)?.text;
const intro = tokens.find(token => token.type === 'paragraph')?.raw;
const links = [...readme.matchAll(/\]\((https:\/\/[^\s)]+)\)/g)].map(match => match[1]);
const download = kind => links.find(link => link.startsWith(`${repository}/releases/download/`)
  && artifactKind(link.split('/').at(-1)) === kind);
const full = download('full');
const addon = download('addon');
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
  return { tag, size: formatArtifactSize(asset.size), html: `<p class="artifact-meta"><a href="${escape(`${repository}/releases/tag/${encodeURIComponent(tag)}`)}" aria-label="Изменения в версии ${escape(tag.replace(/^v/, ''))}">Аддон: ${escape(tag.replace(/^v/, ''))}</a><br>Обновлён <time datetime="${date.toISOString()}">${dateText}</time></p>` };
}
async function previewArtifact(kind) {
  const name = preview[kind];
  if (typeof name !== 'string' || path.basename(name) !== name || artifactKind(name) !== kind) {
    throw Error(`Invalid preview archive: ${kind}`);
  }
  const stat = await fs.stat(path.join(output, 'downloads', name));
  return { tag: preview.version, url: 'downloads/' + name, size: formatArtifactSize(stat.size),
    html: '<p class="artifact-meta">Локальная тестовая сборка<br>Размер готового ZIP</p>' };
}
const fullInfo = previewMode ? await previewArtifact('full') : await artifactInfo(full);
const addonInfo = previewMode ? await previewArtifact('addon') : await artifactInfo(addon);
// Compatibility is tied to the downloadable addon, not unpublished main metadata.
async function compatibilityVersion() {
  if (previewMode) return preview.catQuestVersion;
  const versions = new Set();
  for (const tag of new Set([fullInfo.tag, addonInfo.tag])) {
    const response = await fetch(`https://raw.githubusercontent.com/olegbuchnev/WowVoiceTalkingHead/${encodeURIComponent(tag)}/src/CatQuestAudio.lua`, {signal: AbortSignal.timeout(15000)});
    if (!response.ok) throw Error(`Cannot verify CatQuest integration in ${tag}: HTTP ${response.status}. Update README release links after publishing, or use --preview locally.`);
    const version = /sourceVersion\s*=\s*"([^"]+)"/.exec(await response.text())?.[1];
    if (!version) throw Error(`Published CatQuest compatibility version is missing in ${tag}`);
    versions.add(version);
  }
  if (versions.size !== 1) throw Error('Full and addon-only downloads support different CatQuest versions');
  return [...versions][0];
}
const catQuestVersion = await compatibilityVersion();
async function publishedAudioVersion(file, legacyVersions) {
  // Read the source tagged for the downloadable FULL release, not main: an
  // unreleased import or a newer addon-only build must not change these labels.
  const response = await fetch(`https://raw.githubusercontent.com/olegbuchnev/WowVoiceTalkingHead/${encodeURIComponent(fullInfo.tag)}/${file}`, {
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) throw Error(`Cannot read published audio metadata: ${file} (HTTP ${response.status})`);
  const toc = await response.text();
  const field = key => new RegExp(`^##[ \\t]+${key}:[ \\t]*(\\S+)`, 'm').exec(toc)?.[1];
  const version = field('X-Source-Version') || legacyVersions[field('Version')];
  if (!version) throw Error(`Unknown upstream audio version in ${fullInfo.tag}/${file}`);
  return version;
}
const wowVoiceVersion = previewMode ? preview.wowVoiceVersion
  : await publishedAudioVersion('soundpack/WowVoiceSounds.toc', { '1.0.3-forever.1': '1.0.1' });
// This is the verified upstream pack's publication date, not a rebuilt ZIP's
// upload date. Only look up the audio version included in the downloadable pack.
const audioReleases = JSON.parse(await fs.readFile(path.join(root, 'site/audio-releases.json'), 'utf8'));
const audioRelease = audioReleases.wowvoice?.[wowVoiceVersion];
let audioDateHtml = 'Дата не указана';
if (audioRelease) {
  const date = new Date(`${audioRelease.releasedOn}T00:00:00Z`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(audioRelease.releasedOn)
      || !Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== audioRelease.releasedOn) {
    throw Error(`Invalid upstream audio date for WowVoice ${wowVoiceVersion}`);
  }
  const dateText = new Intl.DateTimeFormat('ru-RU', {
    day: '2-digit', month: '2-digit', year: 'numeric', timeZone: 'UTC',
  }).format(date);
  audioDateHtml = `<time datetime="${escape(audioRelease.releasedOn)}">${dateText}</time>`;
}
const screenshots = tokens.filter(token => token.type === 'paragraph' && token.tokens?.[0]?.type === 'image');
if (!screenshots.length) throw Error('README is missing screenshots');
const sections = new Map();
let current;
for (const token of tokens) {
  if (token.type === 'heading' && token.depth === 2) {
    current = token.text;
    sections.set(current, []);
  } else if (token.type === 'hr') current = undefined;
  else if (current) {
    if (screenshots.includes(token)) continue;
    if (previewMode && token.type === 'paragraph' && token.raw.includes(mirror)) continue;
    sections.get(current).push(token.raw);
  }
}
function section(name, id, className = '') {
  if (!sections.has(name)) throw Error(`README section missing: ${name}`);
  const entries = sections.get(name);
  const image = className === 'queue-feature'
    ? entries.find(entry => entry.trim().startsWith('<p class="feature-image">')) : null;
  const content = `<h2 id="${id}">${escape(name)}</h2>${markdown.parse(entries.filter(entry => entry !== image).join(''))}`;
  return `<section${className ? ` class="${className}"` : ''} aria-labelledby="${id}">${image
    ? `<div class="queue-copy">${content}</div>${markdown.parse(image)}` : content}</section>`;
}
function page(content, isGuide = false) {
  return `<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="Русская озвучка квестов для WoW Forever Beta. Скачать WowVoice TalkingHead, установить аддон и настроить воспроизведение.">
  <meta name="color-scheme" content="dark">
  <meta name="theme-color" content="#181a1b">
  <title>${isGuide ? 'Инструкция — ' : ''}${escape(title)}</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  ${previewMode ? '<aside class="preview-banner">Предпросмотр следующего выпуска. Кнопки скачивают локальные тестовые ZIP. Релиз ещё не опубликован.</aside>' : ''}
  <a class="skip-link" href="#content">Перейти к содержанию</a>
  <div class="layout">
    <header class="sidebar">
      <a class="brand" href="index.html">WowVoice<span>TalkingHead</span></a>
      <p class="tagline">Русская озвучка квестов<br>для WoW Forever Beta</p>
      <div class="downloads" aria-label="Скачать аддон">
        <div class="download-card" role="group" aria-label="Аддон с озвучкой WowVoice">
          <a class="button primary" href="${escape(fullInfo.url || full)}"><span>Скачать с озвучкой WowVoice <span class="artifact-size">${escape(fullInfo.size)}</span></span><span aria-hidden="true">↓</span></a>
          <div class="download-info">
            <p class="download-note">Для первой установки или обновления озвучки: аддон и база WowVoice.</p>
            <dl class="audio-versions" aria-label="Версии исходных паков озвучки в полном архиве">
              <dt>Озвучка WowVoice:</dt><dd>${escape(wowVoiceVersion)}</dd>
              <dt>Выпуск базы:</dt><dd>${audioDateHtml}</dd>
            </dl>
            ${previewMode ? '<p class="download-note">Зеркало на pCloud появится после публикации.</p>' : `<a class="mirror" href="${escape(mirror)}">Зеркало на pCloud ↗</a>`}
          </div>
        </div>
        <div class="download-card" role="group" aria-label="Обновление аддона без звуков">
          <a class="button" href="${escape(addonInfo.url || addon)}"><span>Скачать только аддон <span class="artifact-size">${escape(addonInfo.size)}</span></span><span aria-hidden="true">↓</span></a>
          <div class="download-info">
            <p class="download-note">Для обновления аддона, если установлена озвучка WowVoice <strong>${escape(wowVoiceVersion)}</strong>.</p>
            ${addonInfo.html}
            <p class="download-note version-help">Проверьте строку «Озвучка WowVoice» в настройках <code>/thead</code>. Если озвучки нет или версия старее, скачайте архив с озвучкой.</p>
          </div>
        </div>
        <div class="optional-voices">
          <p class="optional-title">Озвучка CatQuest</p>
          <p class="download-note">Для дополнительной озвучки нужны CatQuest и CatQuest Voices ${escape(catQuestVersion)}. Основная озвучка WowVoice работает без них.</p>
          <div class="curseforge-links">
            <a class="mirror" href="https://www.curseforge.com/wow/addons/catquest">CatQuest на CurseForge ↗</a>
            <a class="mirror" href="https://www.curseforge.com/projects/1715207">CatQuest Voices на CurseForge ↗</a>
          </div>
        </div>
      </div>
      <nav aria-label="Разделы сайта">
        <a href="${isGuide ? 'index.html' : ''}#voice-choice">Выбор озвучки</a>
        <a href="${isGuide ? 'index.html' : ''}#installation">Установка</a>
        <a href="${isGuide ? 'index.html' : ''}#features">Возможности</a>
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
  ${section('Две озвучки на выбор', 'voice-choice', 'voice-feature')}
  <div class="screenshots">${gallery}</div>
  ${section('Установка', 'installation')}
  ${section('Возможности', 'features')}
  ${section('Очередь озвучки', 'quest-queue', 'queue-feature')}
  ${section('Настройки', 'settings')}
  ${section('Совместимость с CatQuest', 'catquest')}
  ${section('Авторы и озвучка', 'credits')}`;
await fs.mkdir(path.join(output, 'images'), { recursive: true });
await fs.writeFile(path.join(output, 'index.html'), page(content));
await fs.writeFile(path.join(output, 'guide.html'), page(markdown.parse(guide), true));
await fs.copyFile(path.join(root, 'site/style.css'), path.join(output, 'style.css'));
for (const asset of imageAssets.values()) {
  await fs.writeFile(path.join(output, asset.url), asset.bytes);
}
console.log(`Built GitHub Pages site: ${output}`);

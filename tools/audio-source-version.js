const fs = require('fs');
const path = require('path');

function readSourceVersion(directory, candidates) {
  // Prefer the Classic client-specific TOC over a potentially stale generic TOC.
  const toc = candidates.find(name => fs.existsSync(path.join(directory, name)));
  if (!toc) throw Error(`Missing source audio TOC in ${directory}`);
  const text = fs.readFileSync(path.join(directory, toc), 'utf8');
  const sourceVersion = /^##\s*X-Source-Version:\s*(\S+)/m.exec(text)?.[1];
  const version = sourceVersion || /^##\s*Version:\s*(\S+)/m.exec(text)?.[1];
  if (!version) throw Error(`Missing source version in ${toc}`);
  const sourceToc = sourceVersion && /^##\s*X-Source-TOC:\s*(\S+)/m.exec(text)?.[1];
  return { toc: sourceToc || toc, version };
}

function writeSourceVersion(file, { toc, version }) {
  if (!version || !toc || /[\r\n]/.test(version + toc)) throw Error('Invalid audio source metadata');
  let text = fs.readFileSync(file, 'utf8');
  const eol = text.includes('\r\n') ? '\r\n' : '\n';
  text = text.replace(/^##[ \t]+X-Source-(?:Version|TOC):[^\r\n]*(?:\r?\n|$)/gm, '');
  if (!/^##[ \t]+Version:/m.test(text)) throw Error(`Missing adapted pack version in ${file}`);
  text = text.replace(/^(##[ \t]+Version:[^\r\n]*)(?:\r?\n|$)/m, (_, line) =>
    `${line}${eol}## X-Source-Version: ${version}${eol}## X-Source-TOC: ${toc}${eol}`);
  fs.writeFileSync(file, text);
}

module.exports = { readSourceVersion, writeSourceVersion };

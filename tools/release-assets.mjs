export function artifactKind(name) {
  if (/^WowVoice(?:TalkingHead)?-.+-addon-only\.zip$/.test(name)) return 'addon';
  if (/^WowVoice(?:TalkingHead)?-.+-lite\.zip$/.test(name)) return 'lite';
  if (/^WowVoice(?:TalkingHead)?-.+\.zip$/.test(name)) return 'full';
  return undefined;
}

export function formatArtifactSize(bytes) {
  if (!Number.isSafeInteger(bytes) || bytes <= 0) throw Error('Invalid artifact size');
  const mb = bytes >= 1_000_000;
  const value = bytes / (mb ? 1_000_000 : 1_000);
  return new Intl.NumberFormat('ru-RU', { maximumFractionDigits: 1, minimumFractionDigits: 0 })
    .format(Math.max(0.1, value)) + (mb ? ' МБ' : ' КБ');
}

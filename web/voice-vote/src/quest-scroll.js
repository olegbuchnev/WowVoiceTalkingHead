// Port of speechWeight/buildScrollPlan/updatePlaybackText in src/Portrait.lua.
// Timing is estimated from text and recording duration, not forced alignment.
export function speechWeight(word) {
  word = word.replace(/\|c[\da-f]{8}|\|r/gi, '');
  const pause = /[.!?…]/u.test(word) ? 6 : /[,;:]/u.test(word) ? 3 : 0;
  return Math.max(1, [...word].length) + 1 + pause;
}

export function buildScrollPlan({text, duration, lineHeight, visibleLines, textRange, prefixHeight}) {
  if (!(textRange > 0 && duration > 0 && Number.isFinite(duration))) return [];
  const words = [];
  let total = 0, previousEnd = 0;
  for (const match of text.matchAll(/\S+/gu)) {
    const breaks = (text.slice(previousEnd, match.index).match(/\n/g) || []).length;
    total += Math.min(2, breaks) * 4;
    const weight = speechWeight(match[0]), finish = match.index + match[0].length;
    words.push({finish, before:total, weight});
    total += weight;
    previousEnd = finish;
  }
  if (!total) return [];
  const height = index => words[index].height ??= prefixHeight(words[index].finish);
  function weightAt(offset) {
    let low = 0, high = words.length - 1;
    while (low < high) {
      const mid = Math.floor((low + high) / 2);
      if (height(mid) <= offset + .01) low = mid + 1;
      else high = mid;
    }
    const previousHeight = low > 0 ? height(low - 1) : 0;
    const span = height(low) - previousHeight;
    const within = span > lineHeight * 1.5 ? Math.max(0, Math.min(1, (offset - previousHeight) / span)) : 0;
    return words[low].before + words[low].weight * within;
  }
  const overlap = Math.min(2, Math.max(0, visibleLines - 1));
  const step = Math.max(1, visibleLines - overlap) * lineHeight;
  const plan = [];
  let offset = 0, previousFinish = 0;
  while (offset < textRange - .01) {
    const to = Math.min(textRange, offset + step);
    const finish = Math.max(previousFinish, duration * weightAt(offset + step) / total);
    const movement = Math.min(.65, (finish - previousFinish) * .25);
    plan.push({from:offset, to, start:finish - movement, finish});
    offset = to;
    previousFinish = finish;
  }
  return plan;
}

export function scrollOffset(plan, elapsed) {
  let offset = 0;
  for (const move of plan) {
    if (elapsed < move.start) break;
    if (elapsed >= move.finish) offset = move.to;
    else {
      const t = (elapsed - move.start) / (move.finish - move.start);
      return move.from + (move.to - move.from) * t * t * (3 - 2 * t);
    }
  }
  return offset;
}

export function measureScrollPlan(viewport, duration) {
  const paragraph = viewport.querySelector('p');
  const style = getComputedStyle(paragraph);
  const lineHeight = parseFloat(style.lineHeight);
  const textRange = Math.max(0, viewport.scrollHeight - viewport.clientHeight);
  // A hidden copy uses the same font, wrapping and logical width, including
  // inside the zoomed head. offsetHeight is unscaled, unlike DOM rectangles.
  const measure = paragraph.cloneNode(false);
  Object.assign(measure.style, {position:'fixed', visibility:'hidden', pointerEvents:'none',
    width:style.width, top:'0', left:'0'});
  measure.setAttribute('aria-hidden', 'true');
  viewport.append(measure);
  try {
    return buildScrollPlan({text:paragraph.textContent, duration, lineHeight,
      visibleLines:Math.max(1, Math.floor(viewport.clientHeight / lineHeight)), textRange,
      prefixHeight:end => {
        measure.textContent = paragraph.textContent.slice(0, end);
        return measure.offsetHeight;
      }});
  } finally { measure.remove(); }
}

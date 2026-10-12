import {useLayoutEffect, useRef} from 'react';
import {measureScrollPlan, scrollOffset} from './quest-scroll.js';

export function useQuestScroll(scroll, audio, questID, duration, position, playing) {
  const plan = useRef([]);
  useLayoutEffect(() => {
    const viewport = scroll.current;
    if (!viewport) return;
    let disposed = false;
    const rebuild = () => {
      if (disposed) return;
      plan.current = measureScrollPlan(viewport, duration);
      viewport.scrollTop = scrollOffset(plan.current, audio.current?.currentTime || 0);
    };
    rebuild();
    const observer = new ResizeObserver(rebuild);
    observer.observe(viewport);
    observer.observe(viewport.querySelector('p'));
    document.fonts.ready.then(rebuild);
    return () => { disposed = true; observer.disconnect(); };
  }, [questID, duration]);

  useLayoutEffect(() => {
    if (scroll.current && !playing) scroll.current.scrollTop = scrollOffset(plan.current, position);
  }, [questID, duration, position, playing]);

  useLayoutEffect(() => {
    if (!playing) return;
    let frame;
    const tick = () => {
      if (scroll.current) scroll.current.scrollTop = scrollOffset(plan.current, audio.current?.currentTime || 0);
      frame = requestAnimationFrame(tick);
    };
    tick();
    return () => cancelAnimationFrame(frame);
  }, [questID, playing]);
}

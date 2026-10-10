// Only the published project site loads analytics. Preview builds omit the
// endpoint; the origin check also excludes local copies of production HTML.
const clickAnalytics = document.body.dataset.clickAnalytics;
if (clickAnalytics && window.location.origin === 'https://olegbuchnev.github.io'
    && window.location.pathname.startsWith('/WowVoiceTalkingHead/')) {
  const counter = document.createElement('script');
  counter.src = 'https://gc.zgo.at/count.js';
  counter.async = true;
  counter.dataset.goatcounter = clickAnalytics;
  // Count button clicks only, without sending a pageview on load.
  counter.dataset.goatcounterSettings = JSON.stringify({ no_onload: true });
  counter.addEventListener('load', () => window.goatcounter?.bind_events?.());
  document.head.appendChild(counter);
}

// A sticky column taller than the viewport hits the page's bottom boundary
// and jumps when release notes change the page height. Pin it only if it fits.
const sidebar = document.querySelector('.sidebar');
if (sidebar) {
  const layout = sidebar.closest('.layout');
  const updateSidebar = () => {
    const top = parseFloat(getComputedStyle(sidebar).top) || 0;
    const bottom = parseFloat(getComputedStyle(layout).paddingBottom) || 0;
    sidebar.classList.toggle('fits-viewport',
      sidebar.getBoundingClientRect().height + top + bottom <= window.innerHeight);
  };
  window.addEventListener('resize', updateSidebar);
  if (typeof ResizeObserver === 'function') {
    new ResizeObserver(updateSidebar).observe(sidebar);
  }
  updateSidebar();
}

// Keep native details/summary keyboard behavior; animate the measured height
// instead of guessing a maximum height for release notes of different lengths.
const releaseDetails = [...document.querySelectorAll('section[aria-labelledby="whats-new"] details')];
if (releaseDetails.length) {
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const releases = releaseDetails.map(details => ({
    details, group: details.getAttribute('name'), expanded: details.open,
  }));
  let frame;
  let followScroll = true;
  const settle = () => {
    cancelAnimationFrame(frame);
    for (const { details, expanded } of releases) {
      details.open = expanded;
      details.style.height = '';
      details.style.overflow = '';
    }
    document.documentElement.style.overflowAnchor = '';
  };
  const toggleRelease = release => {
    cancelAnimationFrame(frame);
    const startScroll = window.scrollY;
    const starts = releases.map(({ details }) => ({
      height: details.getBoundingClientRect().height, open: details.open,
    }));
    release.expanded = !release.expanded;
    if (release.expanded && release.group) {
      releases.forEach(other => {
        if (other !== release && other.group === release.group) other.expanded = false;
      });
    }

    // Measure the final layout, including simultaneous closing of another
    // release. Restore the current heights before the browser paints.
    settle();
    const ends = releases.map(({ details }) => details.getBoundingClientRect().height);
    const bounds = release.details.getBoundingClientRect();
    const top = bounds.top + window.scrollY;
    const margin = 24;
    let endScroll = startScroll;
    if (top < startScroll + margin || bounds.height > window.innerHeight - margin * 2) {
      endScroll = top - margin;
    } else if (top + bounds.height > startScroll + window.innerHeight - margin) {
      endScroll = top + bounds.height - window.innerHeight + margin;
    }
    endScroll = Math.max(0, Math.min(endScroll,
      document.documentElement.scrollHeight - window.innerHeight));
    if (reducedMotion.matches) {
      window.scrollTo({ top: endScroll, behavior: 'instant' });
      return;
    }

    releases.forEach(({ details, expanded }, index) => {
      // Contents stay visible until their closing animation finishes.
      details.open = starts[index].open || expanded;
      details.style.height = `${starts[index].height}px`;
      details.style.overflow = 'hidden';
    });
    document.documentElement.style.overflowAnchor = 'none';
    window.scrollTo({ top: startScroll, behavior: 'instant' });
    followScroll = true;
    const started = performance.now();
    const animate = now => {
      const progress = Math.min(1, (now - started) / 260);
      const eased = (1 - Math.cos(Math.PI * progress)) / 2;
      releases.forEach(({ details }, index) => {
        details.style.height = `${starts[index].height + (ends[index] - starts[index].height) * eased}px`;
      });
      // Height and scrolling share the same clock and easing curve.
      if (followScroll) window.scrollTo({
        top: startScroll + (endScroll - startScroll) * eased, behavior: 'instant',
      });
      if (progress < 1) frame = requestAnimationFrame(animate);
      else settle();
    };
    frame = requestAnimationFrame(animate);
  };
  for (const release of releases) {
    // Native grouping closes siblings instantly. Manage the same grouping here
    // so the previous release can collapse smoothly as the next one opens.
    release.details.removeAttribute('name');
    release.details.querySelector('summary').addEventListener('click', event => {
      event.preventDefault();
      toggleRelease(release);
    });
  }
  // A resize can change text wrapping and the target height mid-animation.
  window.addEventListener('resize', settle);
  reducedMotion.addEventListener('change', settle);
  // Let the reader take over scrolling without fighting the animation.
  window.addEventListener('wheel', () => { followScroll = false; }, { passive: true });
  window.addEventListener('touchstart', () => { followScroll = false; }, { passive: true });
}

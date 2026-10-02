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

// Shared Navigation Component
// Injects the top navigation into any page with a <header id="top-nav"></header>

(function() {
  'use strict';

  function getInitials(name) {
    if (!name) return '?';
    const parts = name.trim().split(/\s+/);
    if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
  }

  function getStoredGuest() {
    try {
      const stored = localStorage.getItem('pb_guest');
      return stored ? JSON.parse(stored) : null;
    } catch {
      return null;
    }
  }

  function getCurrentPage() {
    const path = window.location.pathname.split('/').pop() || 'index.html';
    return path.replace('.html', '');
  }

  function brandMarkHtml() {
    return `<span class="brand-mark" aria-hidden="true"><span></span><span></span><span></span><span></span></span>`;
  }

  function renderNav() {
    const header = document.getElementById('top-nav');
    if (!header) return;

    const guest = getStoredGuest();
    const currentPage = getCurrentPage();
    const hasGuest = guest && guest.name;

    const bookPages = ['index', 'schedule', 'booking-form'];
    const reservationPages = ['reservation', 'my-reservation', 'receipt'];

    const navLinks = [
      { href: 'schedule.html', label: 'Book a court', active: bookPages.includes(currentPage) },
      { href: 'my-reservation.html', label: 'My reservation', active: reservationPages.includes(currentPage) },
      { href: 'help.html', label: 'Help', active: currentPage === 'help' }
    ];

    const linksHtml = navLinks.map(link => {
      return `<a href="${link.href}" class="nav-link${link.active ? ' active' : ''}">${link.label}</a>`;
    }).join('');

    const avatarHtml = hasGuest
      ? `<span class="nav-avatar" title="${guest.name}">${getInitials(guest.name)}</span>`
      : '';

    header.innerHTML = `
      <nav class="top-nav" role="navigation" aria-label="Main navigation">
        <div class="container">
          <a href="index.html" class="nav-brand" aria-label="Pickleball courts - Home">
            ${brandMarkHtml()}
            <span class="nav-wordmark">Pickleball courts</span>
          </a>
          <div class="nav-right">
            <div class="nav-links">${linksHtml}</div>
            ${avatarHtml}
          </div>
        </div>
      </nav>
    `;
  }

  function renderFooter(el) {
    if (!el) return;
    el.className = 'site-footer';
    el.innerHTML = `
      <div class="container">
        <div class="footer-left">Pickleball courts · More time on the court.</div>
        <div class="footer-right">Need a hand? Contact the front desk</div>
      </div>
    `;
  }

  function init() {
    renderNav();
    document.querySelectorAll('footer.footer, footer.site-footer, footer[data-site-footer]').forEach(renderFooter);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  window.PBNav = { render: renderNav, getInitials, getStoredGuest, brandMarkHtml };
})();

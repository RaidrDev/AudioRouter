// Scroll-reveal. Only opt into the hidden-until-scrolled-into-view styling once
// we can actually guarantee the reveal will happen — otherwise a slow or failed
// script load would leave whole sections invisible forever.
if ('IntersectionObserver' in window) {
  document.documentElement.classList.add('js-reveal');

  const revealEls = document.querySelectorAll('.reveal');
  const io = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        entry.target.classList.add('in');
        io.unobserve(entry.target);
      }
    }
  }, { threshold: 0.15 });
  revealEls.forEach((el) => io.observe(el));

  // Belt and suspenders: if for any reason an element never intersects
  // (e.g. it's shorter than the viewport margin math expects), don't leave
  // it invisible forever.
  setTimeout(() => {
    document.querySelectorAll('.reveal:not(.in)').forEach((el) => el.classList.add('in'));
  }, 2500);
}

// Pull the current version/download link straight from the appcast so this page
// never has to be hand-updated when a new release goes out.
function humanSize(bytes) {
  const n = Number(bytes);
  if (!n) return '';
  const mb = n / (1024 * 1024);
  return mb >= 1 ? `${mb.toFixed(1)} MB` : `${Math.round(n / 1024)} KB`;
}

fetch('/appcast.xml')
  .then((r) => r.text())
  .then((text) => {
    const doc = new DOMParser().parseFromString(text, 'text/xml');
    const item = doc.querySelector('item');
    if (!item) return;

    const ns = 'http://www.andymatuschak.org/xml-namespaces/sparkle';
    const version = item.getElementsByTagNameNS(ns, 'shortVersionString')[0]?.textContent;
    const enclosure = item.querySelector('enclosure');
    const url = enclosure?.getAttribute('url');
    const length = enclosure?.getAttribute('length');

    if (url) {
      document.querySelectorAll('#hero-download, #nav-download, #main-download')
        .forEach((el) => { el.href = url; });
    }
    if (version) {
      document.getElementById('hero-version').textContent = version;
      document.getElementById('cta-version').textContent = `v${version}`;
    }
    if (length) {
      document.getElementById('cta-size').textContent = humanSize(length);
    }
  })
  .catch(() => { /* keep the static fallback values in the HTML */ });

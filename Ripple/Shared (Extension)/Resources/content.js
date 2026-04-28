(function () {
  'use strict';

  // ── Demo link generator (same swap point as popup.js) ────────
  // PRODUCTION SWAP: replace with a fetch() to your backend API
  function generateRippleLink(productUrl) {
    const id = Math.random().toString(36).slice(2, 9);
    return Promise.resolve(`https://sharewithripple.com/s/${id}`);
  }

  // ── Toast notification ────────────────────────────────────────
  function showToast(message) {
    const existing = document.getElementById('ripple-toast');
    if (existing) existing.remove();

    const style = document.createElement('style');
    style.textContent = `
      @keyframes ripple-slide-up {
        from { opacity: 0; transform: translateX(-50%) translateY(10px); }
        to   { opacity: 1; transform: translateX(-50%) translateY(0); }
      }
    `;
    document.head.appendChild(style);

    const toast = document.createElement('div');
    toast.id = 'ripple-toast';
    toast.textContent = message;
    Object.assign(toast.style, {
      position:     'fixed',
      bottom:       '28px',
      left:         '50%',
      transform:    'translateX(-50%)',
      background:   'linear-gradient(135deg, #5b8af5, #38bdf8)',
      color:        '#fff',
      padding:      '10px 20px',
      borderRadius: '999px',
      fontFamily:   '-apple-system, system-ui, sans-serif',
      fontSize:     '13px',
      fontWeight:   '600',
      zIndex:       '2147483647',
      boxShadow:    '0 4px 24px rgba(91,138,245,0.45)',
      animation:    'ripple-slide-up 0.2s ease',
      pointerEvents:'none',
    });
    document.body.appendChild(toast);

    setTimeout(() => {
      toast.style.transition = 'opacity 0.25s';
      toast.style.opacity = '0';
      setTimeout(() => toast.remove(), 250);
    }, 2200);
  }

  // ── Silent clipboard interception ─────────────────────────────
  // Fires when the user copies anything on the page (Cmd+C, Edit→Copy,
  // right-click→Copy Link). Does NOT fire for address-bar copies —
  // use the popup for that case.
  document.addEventListener('copy', async (e) => {
    if (!detectProduct()) return;

    const copied = window.getSelection()?.toString().trim() ||
                   e.clipboardData?.getData('text/plain')?.trim() || '';

    // Only intercept if what's being copied looks like a URL
    let isUrl = false;
    try { new URL(copied); isUrl = true; } catch { /* not a URL */ }
    if (!isUrl) return;

    e.preventDefault();
    const rippleUrl = await generateRippleLink(location.href);
    e.clipboardData.setData('text/plain', rippleUrl);
    showToast('✓ Ripple link copied');
  });

  const PRODUCT_DOMAINS = [
    'amazon.com', 'amazon.co.uk', 'amazon.ca', 'amazon.de', 'amazon.fr',
    'amazon.co.jp', 'amazon.in', 'amazon.com.br',
    'target.com', 'walmart.com', 'bestbuy.com', 'etsy.com', 'ebay.com',
    'wayfair.com', 'chewy.com', 'homedepot.com', 'lowes.com', 'costco.com',
    'macys.com', 'nordstrom.com', 'zappos.com', 'rei.com',
    'bhphotovideo.com', 'newegg.com', 'adorama.com',
  ];

  function isKnownProductDomain(hostname) {
    return PRODUCT_DOMAINS.some(d => hostname === d || hostname.endsWith(`.${d}`));
  }

  function hasProductOgType() {
    const el = document.querySelector('meta[property="og:type"]');
    return el?.content?.toLowerCase() === 'product';
  }

  function hasProductSchemaJsonLd() {
    for (const script of document.querySelectorAll('script[type="application/ld+json"]')) {
      try {
        const data = JSON.parse(script.textContent);
        const items = Array.isArray(data['@graph']) ? data['@graph'] : [data];
        for (const item of items) {
          const type = item['@type'];
          const types = Array.isArray(type) ? type : [type];
          if (types.some(t => typeof t === 'string' && t.toLowerCase().includes('product'))) return true;
        }
      } catch { /* malformed JSON-LD — skip */ }
    }
    return false;
  }

  function extractTitle() {
    const og = document.querySelector('meta[property="og:title"]');
    if (og?.content) return og.content.trim();

    for (const script of document.querySelectorAll('script[type="application/ld+json"]')) {
      try {
        const data = JSON.parse(script.textContent);
        const items = Array.isArray(data['@graph']) ? data['@graph'] : [data];
        for (const item of items) {
          const types = Array.isArray(item['@type']) ? item['@type'] : [item['@type']];
          if (types.some(t => typeof t === 'string' && t.toLowerCase().includes('product')) && item.name) {
            return String(item.name).trim();
          }
        }
      } catch { /* skip */ }
    }

    return document.title?.trim() || '';
  }

  function extractDomain() {
    return location.hostname.replace(/^www\./, '');
  }

  function detectProduct() {
    const hostname = location.hostname.replace(/^www\./, '');
    return isKnownProductDomain(hostname) || hasProductOgType() || hasProductSchemaJsonLd();
  }

  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (message?.type !== 'RIPPLE_GET_META') return false;
    const isProduct = detectProduct();
    sendResponse({
      isProduct,
      title: isProduct ? extractTitle() : null,
      domain: extractDomain(),
    });
    return false;
  });
})();

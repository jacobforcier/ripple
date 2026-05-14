(function () {
  'use strict';

  // ── Demo link generator with per-URL caching ─────────────────
  // PRODUCTION SWAP: replace with a fetch() to your backend API.
  // The cache + inFlight guard avoid duplicate API calls and
  // produce stable links when the same URL is shared multiple times.
  const linkCache = new Map();        // sourceUrl -> rippleUrl
  const inFlight  = new Map();        // sourceUrl -> Promise<rippleUrl>

  function generateRippleLink(productUrl) {
    if (linkCache.has(productUrl)) return Promise.resolve(linkCache.get(productUrl));
    if (inFlight.has(productUrl))  return inFlight.get(productUrl);

    const promise = (async () => {
      const id = Math.random().toString(36).slice(2, 9);
      const rippleUrl = `https://sharewithripple.com/s/${id}`;
      linkCache.set(productUrl, rippleUrl);
      return rippleUrl;
    })().finally(() => {
      // Clear the in-flight entry in `finally` (not inside the async body) so
      // it runs *after* `inFlight.set` below — and keeps working once this
      // becomes a real `fetch()` with actual awaits.
      inFlight.delete(productUrl);
    });

    inFlight.set(productUrl, promise);
    return promise;
  }

  // ── Toast notification ────────────────────────────────────────
  // Inject the keyframes once — not a fresh <style> element on every toast.
  function ensureToastStyles() {
    if (document.getElementById('ripple-toast-styles')) return;
    const style = document.createElement('style');
    style.id = 'ripple-toast-styles';
    style.textContent = `
      @keyframes ripple-slide-up {
        from { opacity: 0; transform: translateX(-50%) translateY(10px); }
        to   { opacity: 1; transform: translateX(-50%) translateY(0); }
      }
    `;
    document.head.appendChild(style);
  }

  function showToast(message) {
    const existing = document.getElementById('ripple-toast');
    if (existing) existing.remove();

    ensureToastStyles();

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
  //
  // This handler MUST stay synchronous: a clipboard event's data can only
  // be written during the event's dispatch, never after an `await` (by then
  // the event is done and setData silently no-ops — leaving stale clipboard
  // content while still showing a success toast). So we warm the link cache
  // ahead of time and read from it synchronously here.
  document.addEventListener('copy', (e) => {
    if (!detectProduct()) return;

    const copied = window.getSelection()?.toString().trim() ||
                   e.clipboardData?.getData('text/plain')?.trim() || '';

    // Only intercept if what's being copied looks like a URL
    let isUrl = false;
    try { new URL(copied); isUrl = true; } catch { /* not a URL */ }
    if (!isUrl) return;

    const rippleUrl = linkCache.get(location.href);
    if (rippleUrl) {
      // Cache is warm — swap the clipboard contents synchronously.
      e.preventDefault();
      e.clipboardData.setData('text/plain', rippleUrl);
      showToast('✓ Ripple link copied');
    } else {
      // Not ready yet (a copy before warm-up finished). Let the normal copy
      // proceed and prime the cache so the next copy is intercepted.
      generateRippleLink(location.href);
    }
  });

  // Warm the link cache as soon as we know this is a product page, so the
  // copy handler above can read it synchronously on the user's first copy.
  function warmLinkCache() {
    if (detectProduct()) generateRippleLink(location.href);
  }

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

  warmLinkCache();
})();

// ─────────────────────────────────────────────────────────────────────────────
//  DEMO MODE — replace generateRippleLink() with a real API call once the
//  Skimlinks backend is ready. Everything else in this file stays the same.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * DEMO: returns a placeholder Ripple short-link.
 *
 * PRODUCTION SWAP — replace this entire function with:
 *
 *   async function generateRippleLink(productUrl) {
 *     const res = await fetch('https://api.sharewithripple.com/v1/links', {
 *       method: 'POST',
 *       headers: { 'Content-Type': 'application/json' },
 *       body: JSON.stringify({ url: productUrl }),
 *     });
 *     if (!res.ok) throw new Error(`API error ${res.status}`);
 *     const data = await res.json();
 *     return data.short_url;
 *   }
 */
async function generateRippleLink(productUrl) {
  const id = Math.random().toString(36).slice(2, 9);
  return `https://sharewithripple.com/s/${id}`;
}

// ── State helpers ─────────────────────────────────────────────────────────────

function showState(name) {
  for (const id of ['state-loading', 'state-not-product', 'state-product']) {
    document.getElementById(id).classList.toggle('active', id === `state-${name}`);
  }
}

function setSuccess() {
  const btn = document.getElementById('copy-btn');
  const icon = document.getElementById('btn-icon');
  const txt = document.getElementById('btn-text');

  btn.disabled = true;
  btn.classList.add('success');
  icon.innerHTML = `<path d="M3 8l4 4 6-6" stroke="#fff" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>`;
  txt.textContent = 'Copied!';

  setTimeout(() => {
    btn.disabled = false;
    btn.classList.remove('success');
    icon.innerHTML = `
      <path d="M6.5 9.5a3.535 3.535 0 0 0 5 0l2-2a3.536 3.536 0 0 0-5-5l-1 1" stroke="#fff" stroke-width="1.5" stroke-linecap="round"/>
      <path d="M9.5 6.5a3.535 3.535 0 0 0-5 0l-2 2a3.536 3.536 0 0 0 5 5l1-1" stroke="#fff" stroke-width="1.5" stroke-linecap="round"/>
    `;
    txt.textContent = 'Copy Ripple link';
  }, 2500);
}

// ── Main ──────────────────────────────────────────────────────────────────────

(async () => {
  showState('loading');

  let tab;
  try {
    [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  } catch {
    showState('not-product');
    return;
  }

  const url = tab?.url ?? '';
  if (!tab?.id || !url || url.startsWith('chrome://') || url.startsWith('about:')) {
    showState('not-product');
    return;
  }

  // Ask the content script for page metadata, injecting it first if needed
  let meta;
  try {
    meta = await chrome.tabs.sendMessage(tab.id, { type: 'RIPPLE_GET_META' });
  } catch {
    try {
      await chrome.scripting.executeScript({ target: { tabId: tab.id }, files: ['content.js'] });
      meta = await chrome.tabs.sendMessage(tab.id, { type: 'RIPPLE_GET_META' });
    } catch {
      showState('not-product');
      return;
    }
  }

  if (!meta?.isProduct) {
    showState('not-product');
    return;
  }

  document.getElementById('domain-label').textContent = meta.domain;
  document.getElementById('product-title').textContent = meta.title || 'Product';
  showState('product');

  // Cache: same source URL → same Ripple link for this popup session
  let cachedRippleUrl = null;
  let inFlight = false;

  const btn = document.getElementById('copy-btn');
  btn.addEventListener('click', async () => {
    if (btn.disabled || inFlight) return;
    inFlight = true;
    btn.disabled = true;
    try {
      if (!cachedRippleUrl) {
        cachedRippleUrl = await generateRippleLink(url);
      }
      await navigator.clipboard.writeText(cachedRippleUrl);
      setSuccess();
    } catch (err) {
      console.error('[Ripple] Copy failed:', err);
      btn.disabled = false;
    } finally {
      inFlight = false;
    }
  });
})();

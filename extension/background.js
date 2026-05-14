// Ripple background service worker.
//
// Owns every call to the Ripple API. Content scripts run in the page's origin
// and are blocked by CORS; the popup runs in the extension origin. The
// background worker is the one context with host_permissions for
// api.sharewithripple.com, so routing all API calls through here keeps a
// single, CORS-free path to the backend.

const API_BASE = 'https://api.sharewithripple.com';

chrome.runtime.onInstalled.addListener(({ reason }) => {
  if (reason === 'install') {
    console.log('[Ripple] Installed. Welcome!');
  }
});

// Creates a Ripple link for a product URL via POST /v1/links.
async function createRippleLink(sourceUrl) {
  const res = await fetch(`${API_BASE}/v1/links`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ source_url: sourceUrl }),
  });
  if (!res.ok) throw new Error(`Ripple API error ${res.status}`);
  const data = await res.json();
  return data.ripple_url;
}

// Message bridge: the popup and content scripts ask the worker to create links.
chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type !== 'RIPPLE_CREATE_LINK') return false;

  createRippleLink(message.sourceUrl)
    .then((rippleUrl) => sendResponse({ ok: true, rippleUrl }))
    .catch((err) => sendResponse({ ok: false, error: String(err?.message || err) }));

  return true; // keep the message channel open for the async sendResponse
});

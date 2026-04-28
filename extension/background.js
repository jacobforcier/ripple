// Minimal MV3 service worker — required by manifest.json.
// All functionality lives in popup.js and content.js.
//
// Future use: cache generated Ripple links to avoid duplicate API calls,
// handle onboarding flow, badge the extension icon with earnings.

chrome.runtime.onInstalled.addListener(({ reason }) => {
  if (reason === 'install') {
    console.log('[Ripple] Installed. Welcome!');
  }
});

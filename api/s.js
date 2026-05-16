// ─────────────────────────────────────────────────────────────────────────────
//  /s/[id] — Ripple link redirect page (server-rendered)
//
//  Why this is a function instead of static HTML: link-preview bots (iMessage,
//  X, Slack) fetch this URL to build a preview card. We want that card to show
//  the PRODUCT — title, image, description from the source URL — not a generic
//  Ripple card. So at request time we look up the link's cached OG metadata
//  from the backend and inline it into the page's <meta> tags.
//
//  Humans get the same HTML; the in-page JS does the click logging + redirect
//  exactly as before. Preview bots only read the OG tags.
//
//  Routed via vercel.json: /s/<id> → /api/s?id=<id>
// ─────────────────────────────────────────────────────────────────────────────

const API_BASE  = 'https://api.sharewithripple.com';
const SITE_BASE = 'https://sharewithripple.com';

const FALLBACK_OG = {
  title:       'Ripple link',
  description: "A shared product link. The sharer may earn a small commission if you buy — at no extra cost to you.",
  image:       `${SITE_BASE}/og-image.png`,
};

export default async function handler(req, res) {
  const id = String(req.query?.id ?? '').trim();
  res.setHeader('Content-Type', 'text/html; charset=utf-8');

  if (!id) {
    res.statusCode = 400;
    return res.end(renderError("That doesn't look like a Ripple link."));
  }

  let link = null;
  try {
    const r = await fetch(`${API_BASE}/v1/links/${encodeURIComponent(id)}/preview`, {
      headers: { 'User-Agent': 'ripple-redirect-page/1.0' },
    });
    if (r.ok) link = await r.json();
  } catch (err) {
    console.error('[s] preview fetch failed:', err);
  }

  if (!link) {
    res.statusCode = 404;
    return res.end(renderError("This Ripple link isn't available."));
  }

  // Resolve OG tags. We always serve our OWN image (never hotlink the retailer's
  // CDN) and we prefix the title with "Ripple →" so link previews can't be
  // mistaken for an actual retailer page — that pattern trips Safe Browsing's
  // social-engineering classifier as brand impersonation.
  const productLabel = link.og_title
    || (link.retailer ? `a product on ${link.retailer}` : 'a shared product');
  const og = {
    title:       `Ripple → ${productLabel}`,
    description: link.og_description || FALLBACK_OG.description,
    image:       FALLBACK_OG.image,
  };

  res.statusCode = 200;
  return res.end(renderRedirect({ id, retailer: link.retailer, og }));
}

// ── HTML rendering ───────────────────────────────────────────────────────────

function renderRedirect({ id, retailer, og }) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>${esc(og.title)}</title>
  <meta name="description" content="${esc(og.description)}" />
  <meta name="robots" content="noindex" />

  <!-- Product-specific link previews (iMessage, X, Slack, …). -->
  <meta property="og:type" content="website" />
  <meta property="og:site_name" content="Ripple" />
  <meta property="og:title" content="${esc(og.title)}" />
  <meta property="og:description" content="${esc(og.description)}" />
  <meta property="og:image" content="${esc(og.image)}" />
  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content="${esc(og.title)}" />
  <meta name="twitter:description" content="${esc(og.description)}" />
  <meta name="twitter:image" content="${esc(og.image)}" />

  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet" />
  <style>${REDIRECT_CSS}</style>
</head>
<body>
  <div class="rings" aria-hidden="true">
    <div class="ring"></div><div class="ring"></div>
    <div class="ring"></div><div class="ring"></div>
  </div>

  <div class="card" id="state-valid">
    <div class="logo">ripple</div>
    <h1>Heads up — this is a Ripple link</h1>
    <p class="disclosure">
      <strong id="sharer-line">The person who shared this</strong> may earn a small
      commission if you make a purchase — at <strong>no extra cost to you</strong>.
      It's just word-of-mouth, rewarded.
    </p>
    <div class="destination">
      <span>You're heading to</span>
      <span class="arrow">&rarr;</span>
      <span id="retailer-name">${esc(retailer || 'the store')}</span>
    </div>
    <a class="continue-btn" id="continue-btn" href="#" rel="nofollow noopener">Continue to <span id="retailer-name-btn">${esc(retailer || 'the store')}</span></a>
    <a class="what-link" href="/">What is Ripple?</a>
  </div>

  <div class="card error hidden" id="state-error">
    <div class="logo">ripple</div>
    <h1>This link isn't available</h1>
    <p class="disclosure">
      We couldn't find a destination for this Ripple link. It may have expired
      or been mistyped.
    </p>
    <a class="continue-btn" href="/">Go to Ripple</a>
  </div>

  <script>
    const API_BASE = ${JSON.stringify(API_BASE)};
    const LINK_ID  = ${JSON.stringify(id)};

    // GET /v1/links/:id — also records a click. Returns { url, retailer, sharer }.
    async function resolveLink() {
      try {
        const res = await fetch(\`\${API_BASE}/v1/links/\${encodeURIComponent(LINK_ID)}\`);
        if (!res.ok) return null;
        return await res.json();
      } catch { return null; }
    }

    (async () => {
      const link = await resolveLink();
      if (!link || !link.url) {
        document.getElementById('state-valid').classList.add('hidden');
        document.getElementById('state-error').classList.remove('hidden');
        return;
      }
      if (link.sharer) {
        document.getElementById('sharer-line').textContent =
          \`\${link.sharer} (who shared this)\`;
      }
      if (link.retailer) {
        document.getElementById('retailer-name').textContent = link.retailer;
        document.getElementById('retailer-name-btn').textContent = link.retailer;
      }
      const btn = document.getElementById('continue-btn');
      btn.href = link.url;
      // No auto-redirect: the user must click "Continue" to proceed. Auto-redirects
      // on a cross-domain interstitial trigger Safe Browsing's social-engineering
      // classifier.
    })();
  </script>
</body>
</html>`;
}

function renderError(message) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Ripple — link unavailable</title>
  <meta name="robots" content="noindex" />
  <style>${REDIRECT_CSS}</style>
</head>
<body>
  <div class="card error">
    <div class="logo">ripple</div>
    <h1>This link isn't available</h1>
    <p class="disclosure">${esc(message)}</p>
    <a class="continue-btn" href="/">Go to Ripple</a>
  </div>
</body>
</html>`;
}

function esc(s) {
  return String(s ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// ── Shared CSS ───────────────────────────────────────────────────────────────

const REDIRECT_CSS = `
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

:root {
  --bg:        #07070f;
  --surface:   rgba(255,255,255,0.04);
  --border:    rgba(255,255,255,0.08);
  --accent:    #5b8af5;
  --accent2:   #38bdf8;
  --text:      #eeeeff;
  --muted:     #7878a0;
  --radius:    12px;
}

body {
  font-family: 'Inter', system-ui, sans-serif;
  background: var(--bg);
  color: var(--text);
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 24px;
  overflow: hidden;
}

.rings {
  position: fixed;
  top: 50%; left: 50%;
  transform: translate(-50%, -50%);
  pointer-events: none;
  z-index: 0;
}
.ring {
  position: absolute;
  border-radius: 50%;
  border: 1px solid rgba(91, 138, 245, 0.16);
  top: 50%; left: 50%;
  transform: translate(-50%, -50%) scale(0.85);
  animation: ring-pulse 5s ease-out infinite;
}
.ring:nth-child(1) { width: 220px;  height: 220px;  animation-delay: 0s; }
.ring:nth-child(2) { width: 440px;  height: 440px;  animation-delay: 1.2s; }
.ring:nth-child(3) { width: 660px;  height: 660px;  animation-delay: 2.4s; }
.ring:nth-child(4) { width: 880px;  height: 880px;  animation-delay: 3.6s; }
@keyframes ring-pulse {
  0%   { opacity: 0;   transform: translate(-50%, -50%) scale(0.85); }
  20%  { opacity: 1; }
  100% { opacity: 0;   transform: translate(-50%, -50%) scale(1.1); }
}

.card {
  position: relative;
  z-index: 1;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 20px;
  padding: 44px 40px;
  max-width: 460px;
  width: 100%;
  text-align: center;
  backdrop-filter: blur(12px);
}

.logo {
  font-size: 24px;
  font-weight: 700;
  letter-spacing: -0.5px;
  background: linear-gradient(135deg, var(--accent), var(--accent2));
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
  margin-bottom: 28px;
}

h1 {
  font-size: 22px;
  font-weight: 700;
  letter-spacing: -0.5px;
  line-height: 1.3;
  margin-bottom: 14px;
}

.disclosure {
  font-size: 15px;
  color: var(--muted);
  line-height: 1.6;
  margin-bottom: 28px;
}
.disclosure strong { color: var(--text); font-weight: 600; }

.destination {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 10px;
  background: rgba(91,138,245,0.08);
  border: 1px solid rgba(91,138,245,0.2);
  border-radius: var(--radius);
  padding: 14px 18px;
  font-size: 15px;
  font-weight: 600;
  margin-bottom: 28px;
}
.destination .arrow { color: var(--accent2); }

.countdown {
  font-size: 13px;
  color: var(--muted);
  margin-bottom: 20px;
}
.countdown strong { color: var(--accent2); }

.continue-btn {
  display: inline-block;
  width: 100%;
  background: linear-gradient(135deg, var(--accent), var(--accent2));
  color: #fff;
  border: none;
  padding: 15px 28px;
  border-radius: var(--radius);
  font-size: 15px;
  font-weight: 600;
  font-family: inherit;
  cursor: pointer;
  text-decoration: none;
  transition: opacity 0.2s, transform 0.1s;
}
.continue-btn:hover { opacity: 0.88; }
.continue-btn:active { transform: scale(0.99); }

.what-link {
  display: inline-block;
  margin-top: 20px;
  font-size: 13px;
  color: var(--muted);
  text-decoration: none;
  transition: color 0.2s;
}
.what-link:hover { color: var(--text); }

.error h1 { margin-bottom: 10px; }
.hidden { display: none; }
`;

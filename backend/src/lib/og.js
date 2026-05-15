// ─────────────────────────────────────────────────────────────────────────────
//  Open Graph metadata scraper.
//
//  When a Ripple link is created, we fetch the source URL once and cache its
//  OG title/image/description. The redirect page serves these as its own OG
//  tags, so iMessage / X / Slack previews show the *product* — not a generic
//  Ripple card.
//
//  This is best-effort: many sites (Amazon, in particular) selectively serve
//  bot-friendly markup, so we use a browser User-Agent. On any failure
//  (timeout, HTTP error, missing tags) we return null and the redirect page
//  falls back to Ripple's generic OG tags.
// ─────────────────────────────────────────────────────────────────────────────

const FETCH_TIMEOUT_MS = 8000;
const MAX_HTML_BYTES = 256 * 1024; // 256 KB is plenty for the document <head>

const BROWSER_HEADERS = {
  'User-Agent':
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 ' +
    '(KHTML, like Gecko) Version/17.0 Safari/605.1.15',
  Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'en-US,en;q=0.9',
};

/**
 * Fetches a URL and extracts its Open Graph metadata.
 * Returns { title, image, description } (any may be null), or null on failure.
 */
export async function fetchOG(url) {
  try {
    const res = await fetch(url, {
      headers: BROWSER_HEADERS,
      redirect: 'follow',
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
    });
    if (!res.ok) return null;

    const contentType = res.headers.get('content-type') || '';
    if (!contentType.includes('text/html')) return null;

    // We only need the <head>. Read a bounded amount of bytes.
    const html = await readLimited(res, MAX_HTML_BYTES);
    return extractOG(html);
  } catch (err) {
    console.error('[og] fetch failed:', err?.message || err);
    return null;
  }
}

/**
 * Pulls OG-style metadata out of an HTML string. Pure — exported for tests.
 * Falls back to twitter:* and <title> when OG tags are missing.
 */
export function extractOG(html) {
  if (typeof html !== 'string' || html.length === 0) return null;

  const head = sliceHead(html);

  const get = (property) => {
    // Matches:
    //   <meta property="og:title" content="…">
    //   <meta name="twitter:title" content="…">
    // and the same with attribute order swapped.
    const escaped = property.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const patterns = [
      new RegExp(
        `<meta[^>]+(?:property|name)=["']${escaped}["'][^>]*content=["']([^"']*)["']`,
        'i'
      ),
      new RegExp(
        `<meta[^>]+content=["']([^"']*)["'][^>]*(?:property|name)=["']${escaped}["']`,
        'i'
      ),
    ];
    for (const re of patterns) {
      const match = head.match(re);
      if (match) return decodeEntities(match[1].trim()) || null;
    }
    return null;
  };

  const title =
    get('og:title') ||
    get('twitter:title') ||
    (head.match(/<title[^>]*>([^<]+)<\/title>/i)?.[1]?.trim()
      ? decodeEntities(head.match(/<title[^>]*>([^<]+)<\/title>/i)[1].trim())
      : null);

  const image = get('og:image') || get('twitter:image') || get('twitter:image:src');
  const description =
    get('og:description') || get('twitter:description') || get('description');

  if (!title && !image && !description) return null;
  return { title, image, description };
}

// ── Helpers ──────────────────────────────────────────────────────────────────

async function readLimited(res, maxBytes) {
  const reader = res.body.getReader();
  const decoder = new TextDecoder('utf-8');
  let received = 0;
  let html = '';
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    received += value.length;
    html += decoder.decode(value, { stream: true });
    if (received >= maxBytes) {
      try { await reader.cancel(); } catch { /* ignore */ }
      break;
    }
  }
  html += decoder.decode();
  return html;
}

function sliceHead(html) {
  const end = html.search(/<\/head>/i);
  return end > 0 ? html.slice(0, end) : html.slice(0, MAX_HTML_BYTES);
}

function decodeEntities(s) {
  return s
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&#x27;/gi, "'")
    .replace(/&nbsp;/g, ' ');
}

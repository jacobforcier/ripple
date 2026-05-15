// ═════════════════════════════════════════════════════════════════════════════
//  AFFILIATE LINK GENERATION
//
//  This is where Ripple turns a plain product URL into a tracked affiliate URL.
//  We route per-retailer:
//
//    • Amazon (any country)  → append our Associates tag (no API/approval
//                              needed — this is the standard "tag=…" mechanism
//                              that Amazon attributes via a 24h cookie).
//    • Everything else       → passthrough until Sovrn (or another aggregator)
//                              is approved. Then add a Sovrn branch here.
//
//  When Sovrn comes back, the swap is: in `generateAffiliateUrl`, add an
//  `else` branch that calls Sovrn's `/commerce/links` API.
// ═════════════════════════════════════════════════════════════════════════════

/**
 * Generates the tracked affiliate URL for a given product page. Falls back to
 * the original URL if the retailer isn't supported yet.
 */
export async function generateAffiliateUrl(sourceUrl) {
  if (isAmazonUrl(sourceUrl)) {
    return applyAmazonTag(sourceUrl);
  }
  // Sovrn / other aggregator slot — passthrough until wired up.
  return sourceUrl;
}

// ── Amazon Associates ────────────────────────────────────────────────────────
//
// Standard Amazon affiliate links work by appending `?tag=<associate-id>` to
// the product URL. Amazon attributes any purchase within 24 hours of that
// click to the associate. No API call needed for basic attribution.

/** Detects every Amazon storefront we serve (US + international + short URLs). */
export function isAmazonUrl(sourceUrl) {
  try {
    const host = new URL(sourceUrl).hostname.replace(/^www\./, '').toLowerCase();
    return host === 'amazon.com' ||
           host === 'smile.amazon.com' ||
           host === 'm.amazon.com' ||
           // Amazon's own short-URL domains (the iOS/Android Share button
           // produces `a.co/d/…` URLs; some marketing tools produce `amzn.to/…`).
           // Amazon preserves the `tag` query parameter through these redirects.
           host === 'a.co' ||
           host === 'amzn.to' ||
           host === 'amzn.com' ||
           /^amazon\.(co\.uk|ca|de|fr|co\.jp|in|com\.br|com\.mx|it|es|nl|se|pl|com\.au|sg|ae|sa)$/.test(host) ||
           host.endsWith('.amazon.com');
  } catch {
    return false;
  }
}

/**
 * Returns the source URL with our Associates `tag` query parameter set.
 * Replaces any existing `tag=...` (so a previous affiliate's tag can't
 * accidentally — or maliciously — pass through us un-overridden).
 */
export function applyAmazonTag(sourceUrl) {
  const tag = process.env.AMAZON_ASSOCIATE_TAG;
  if (!tag) {
    // Tag isn't configured — return the URL unchanged so the redirect still
    // works. Earnings won't be attributed; this is the safe failure mode.
    console.warn('[affiliate] AMAZON_ASSOCIATE_TAG is not set — Amazon link untagged');
    return sourceUrl;
  }
  try {
    const url = new URL(sourceUrl);
    url.searchParams.set('tag', tag);
    return url.toString();
  } catch {
    return sourceUrl;
  }
}

// ── Retailer detection ───────────────────────────────────────────────────────
// Derives a human-readable retailer name from a product URL. Used for the
// redirect page ("Continuing to → Amazon") and for analytics. Independent of
// the affiliate-network logic above.
const RETAILER_BY_DOMAIN = {
  'amazon.com': 'Amazon',
  'amazon.co.uk': 'Amazon',
  'amazon.ca': 'Amazon',
  'amazon.de': 'Amazon',
  'amazon.fr': 'Amazon',
  'amazon.co.jp': 'Amazon',
  'amazon.in': 'Amazon',
  'amazon.com.br': 'Amazon',
  // Amazon's short-URL domains — used by the mobile Share button.
  'a.co': 'Amazon',
  'amzn.to': 'Amazon',
  'amzn.com': 'Amazon',
  'target.com': 'Target',
  'walmart.com': 'Walmart',
  'bestbuy.com': 'Best Buy',
  'etsy.com': 'Etsy',
  'ebay.com': 'eBay',
  'wayfair.com': 'Wayfair',
  'chewy.com': 'Chewy',
  'homedepot.com': 'Home Depot',
  'lowes.com': "Lowe's",
  'costco.com': 'Costco',
  'macys.com': "Macy's",
  'nordstrom.com': 'Nordstrom',
  'zappos.com': 'Zappos',
  'rei.com': 'REI',
  'bhphotovideo.com': 'B&H Photo',
  'newegg.com': 'Newegg',
  'adorama.com': 'Adorama',
};

export function detectRetailer(sourceUrl) {
  try {
    const host = new URL(sourceUrl).hostname.replace(/^www\./, '').toLowerCase();
    for (const [domain, name] of Object.entries(RETAILER_BY_DOMAIN)) {
      if (host === domain || host.endsWith(`.${domain}`)) return name;
    }
    // Unknown retailer — fall back to a title-cased first label of the domain.
    const label = host.split('.')[0];
    return label ? label.charAt(0).toUpperCase() + label.slice(1) : null;
  } catch {
    return null;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  AFFILIATE LINK GENERATION — STUBBED
//
//  This file is the ONLY part of the backend that depends on the affiliate
//  network. Everything else — link storage, resolution, click tracking,
//  earnings aggregation — is real and fully testable today.
//
//  PRODUCTION SWAP — once the Sovrn Commerce application is approved, replace
//  the body of generateAffiliateUrl() with a real Sovrn API call. Roughly:
//
//    export async function generateAffiliateUrl(sourceUrl) {
//      const res = await fetch('https://api.sovrn.com/commerce/links', {
//        method: 'POST',
//        headers: {
//          Authorization: `Bearer ${process.env.SOVRN_API_KEY}`,
//          'Content-Type': 'application/json',
//        },
//        body: JSON.stringify({ url: sourceUrl }),
//      });
//      if (!res.ok) throw new Error(`Sovrn API error ${res.status}`);
//      const data = await res.json();
//      return data.affiliateUrl;       // adjust to Sovrn's actual response shape
//    }
//
//  Until then we run in PASSTHROUGH MODE: the "affiliate" URL is just the
//  source URL, so the create -> resolve -> redirect -> click pipeline works
//  end to end and only commission attribution is missing.
// ═════════════════════════════════════════════════════════════════════════════

export async function generateAffiliateUrl(sourceUrl) {
  // DEMO / passthrough — no tracking wrapper applied yet.
  return sourceUrl;
}

// ── Retailer detection ───────────────────────────────────────────────────────
// Derives a human-readable retailer name from a product URL. Used for the
// redirect page ("Continuing to → Amazon") and for analytics. This logic is
// real and stays as-is in production — it does not depend on the network.
const RETAILER_BY_DOMAIN = {
  'amazon.com': 'Amazon',
  'amazon.co.uk': 'Amazon',
  'amazon.ca': 'Amazon',
  'amazon.de': 'Amazon',
  'amazon.fr': 'Amazon',
  'amazon.co.jp': 'Amazon',
  'amazon.in': 'Amazon',
  'amazon.com.br': 'Amazon',
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

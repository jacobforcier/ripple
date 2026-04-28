(function () {
  'use strict';

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

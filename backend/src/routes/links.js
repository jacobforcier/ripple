import { Router } from 'express';
import { newShortId } from '../lib/shortId.js';
import { hashIp } from '../lib/hashIp.js';
import { rateLimit } from '../lib/rateLimit.js';
import { generateAffiliateUrl, detectRetailer } from '../lib/affiliate.js';
import { fetchOG as defaultFetchOG } from '../lib/og.js';

// The `db` client and OG fetcher are injected so the routes can be tested
// with a mock db and a no-op OG fetcher (no real network calls in tests).
export function makeLinksRouter(db, { fetchOG = defaultFetchOG } = {}) {
  const router = Router();

  // Per-IP cap on link creation. A real user makes a handful of links; this
  // stops a script from generating thousands. Higher ceiling than user
  // creation since one person legitimately creates more links than accounts.
  const createLimit = rateLimit(db, {
    bucket: 'links:create',
    max: Number(process.env.RL_LINKS_MAX ?? 60),
    windowSec: Number(process.env.RL_LINKS_WINDOW_SEC ?? 3600),
  });

  // ── POST /v1/links ─────────────────────────────────────────────────────────
  // Create a Ripple link. Called by the extension popup, the content script,
  // and the iOS / macOS Share Extensions.
  //   body: { source_url: string, user_id?: uuid }
  //   201:  { id, ripple_url, source_url, retailer }
  //   429:  { error }  — too many creations from this IP
  router.post('/', createLimit, async (req, res) => {
    const { source_url, user_id } = req.body ?? {};

    if (!source_url || typeof source_url !== 'string') {
      return res.status(400).json({ error: 'source_url is required' });
    }

    let parsed;
    try {
      parsed = new URL(source_url);
    } catch {
      return res.status(400).json({ error: 'source_url is not a valid URL' });
    }
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      return res.status(400).json({ error: 'source_url must be an http(s) URL' });
    }

    const retailer = detectRetailer(source_url);

    // Scrape Open Graph metadata from the source URL so the redirect page
    // can render product-specific link previews (iMessage / X / Slack cards
    // show the product, not a generic Ripple card). Best-effort: on failure
    // we store nulls and the redirect page falls back to Ripple's defaults.
    const og = (await fetchOG(source_url)) ?? {};

    // Insert, retrying on the (very unlikely) short-id collision.
    //
    // The affiliate URL is generated INSIDE the loop because it embeds the
    // link `id` as the affiliate-network sub-tag (Amazon `ascsubtag`). That's
    // what lets a commission in Amazon's report be attributed back to this
    // exact link — and therefore this user. For Amazon this is pure string
    // work (no network call), so regenerating per attempt is cheap. If an
    // API-backed network is added later, hoist its call out and re-apply only
    // the subtag here.
    for (let attempt = 0; attempt < 5; attempt++) {
      const id = newShortId();

      let affiliate_url;
      try {
        affiliate_url = await generateAffiliateUrl(source_url, { subtag: id });
      } catch (err) {
        console.error('[links] affiliate generation failed:', err);
        return res.status(502).json({ error: 'Could not generate an affiliate link' });
      }

      const { error } = await db.from('links').insert({
        id,
        user_id: user_id ?? null,
        source_url,
        affiliate_url,
        retailer,
        og_title: og.title ?? null,
        og_image: og.image ?? null,
        og_description: og.description ?? null,
      });

      if (!error) {
        return res.status(201).json({
          id,
          ripple_url: `https://sharewithripple.com/s/${id}`,
          source_url,
          retailer,
        });
      }
      if (error.code === '23505') continue; // unique_violation — new id, retry
      console.error('[links] insert failed:', error);
      return res.status(500).json({ error: 'Failed to create link' });
    }

    return res.status(500).json({ error: 'Could not allocate a unique link id' });
  });

  // ── GET /v1/links ──────────────────────────────────────────────────────────
  // List a user's links with click counts and earnings. Backs the dashboard /
  // iOS history screen.
  //   query: ?user_id=uuid
  //   200:   { links: [ { id, source_url, retailer, created_at, click_count, ... } ] }
  router.get('/', async (req, res) => {
    const { user_id } = req.query;
    if (!user_id) {
      return res.status(400).json({ error: 'user_id query parameter is required' });
    }

    const { data, error } = await db
      .from('link_stats')
      .select('*')
      .eq('user_id', user_id)
      .order('created_at', { ascending: false });

    if (error) {
      console.error('[links] list failed:', error);
      return res.status(500).json({ error: 'Failed to load links' });
    }
    return res.json({ links: data });
  });

  // ── GET /v1/links/:id/preview ──────────────────────────────────────────────
  // Returns a link's display metadata WITHOUT logging a click. Used by the
  // /s/[id] page's server-side renderer to populate Open Graph tags — we
  // don't want a click counted for every link-preview bot fetch.
  //   200: { id, source_url, retailer, og_title, og_image, og_description }
  //   404: { error }
  router.get('/:id/preview', async (req, res) => {
    const { id } = req.params;

    const { data, error } = await db
      .from('links')
      .select('id, source_url, retailer, og_title, og_image, og_description')
      .eq('id', id)
      .maybeSingle();

    if (error) {
      console.error('[links] preview lookup failed:', error);
      return res.status(500).json({ error: 'Failed to load link' });
    }
    if (!data) return res.status(404).json({ error: 'Link not found' });
    return res.json(data);
  });

  // ── GET /v1/links/:id ──────────────────────────────────────────────────────
  // Resolve a Ripple link and record the click. Called by the /s/[id] redirect
  // page from the user's browser (not by preview bots — use /preview for that).
  //   200: { url, retailer, sharer }
  //   404: { error }
  router.get('/:id', async (req, res) => {
    const { id } = req.params;

    const { data: link, error } = await db
      .from('links')
      .select('id, source_url, affiliate_url, retailer, users ( display_name )')
      .eq('id', id)
      .maybeSingle();

    if (error) {
      console.error('[links] resolve failed:', error);
      return res.status(500).json({ error: 'Failed to resolve link' });
    }
    if (!link) {
      return res.status(404).json({ error: 'Link not found' });
    }

    // Record the click. Don't fail the redirect if logging hiccups.
    const { error: clickError } = await db.from('clicks').insert({
      link_id: id,
      ip_hash: hashIp(req),
      user_agent: req.get('user-agent') ?? null,
    });
    if (clickError) console.error('[links] click logging failed:', clickError);

    return res.json({
      url: link.affiliate_url ?? link.source_url,
      retailer: link.retailer,
      sharer: link.users?.display_name ?? null,
    });
  });

  return router;
}

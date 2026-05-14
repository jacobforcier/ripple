import { Router } from 'express';
import { newShortId } from '../lib/shortId.js';
import { hashIp } from '../lib/hashIp.js';
import { generateAffiliateUrl, detectRetailer } from '../lib/affiliate.js';

// The `db` client is injected so the routes can be tested with a mock.
export function makeLinksRouter(db) {
  const router = Router();

  // ── POST /v1/links ─────────────────────────────────────────────────────────
  // Create a Ripple link. Called by the extension popup, the content script,
  // and the iOS / macOS Share Extensions.
  //   body: { source_url: string, user_id?: uuid }
  //   201:  { id, ripple_url, source_url, retailer }
  router.post('/', async (req, res) => {
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

    let affiliate_url;
    try {
      affiliate_url = await generateAffiliateUrl(source_url);
    } catch (err) {
      console.error('[links] affiliate generation failed:', err);
      return res.status(502).json({ error: 'Could not generate an affiliate link' });
    }
    const retailer = detectRetailer(source_url);

    // Insert, retrying on the (very unlikely) short-id collision.
    for (let attempt = 0; attempt < 5; attempt++) {
      const id = newShortId();
      const { error } = await db.from('links').insert({
        id,
        user_id: user_id ?? null,
        source_url,
        affiliate_url,
        retailer,
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

  // ── GET /v1/links/:id ──────────────────────────────────────────────────────
  // Resolve a Ripple link and record the click. Called by the /s/[id] redirect
  // page.
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

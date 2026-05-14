import { Router } from 'express';

// The `db` client is injected so the routes can be tested with a mock.
export function makeTrendingRouter(db) {
  const router = Router();

  // ── GET /v1/trending ───────────────────────────────────────────────────────
  // The retailers Ripple users have shared links from most over the last 7
  // days. Backs the Trending tab in the iOS app.
  //   200: { period: "week", trending: [ { rank, retailer, share_count } ] }
  //
  // Note: week-over-week rank movement (up/down/new) isn't returned yet — that
  // needs a periodic snapshot of rankings to diff against. The app degrades
  // gracefully (shows "steady") until that's added.
  router.get('/', async (_req, res) => {
    const since = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();

    const { data, error } = await db
      .from('links')
      .select('retailer')
      .gte('created_at', since)
      .not('retailer', 'is', null);

    if (error) {
      console.error('[trending] query failed:', error);
      return res.status(500).json({ error: 'Failed to load trending' });
    }

    // Aggregate by retailer — the supabase-js client doesn't expose GROUP BY
    // directly, and at early-stage volumes this is trivial to do in memory.
    const counts = new Map();
    for (const row of data) {
      counts.set(row.retailer, (counts.get(row.retailer) ?? 0) + 1);
    }

    const trending = [...counts.entries()]
      .map(([retailer, share_count]) => ({ retailer, share_count }))
      .sort((a, b) => b.share_count - a.share_count)
      .map((row, index) => ({ rank: index + 1, ...row }));

    return res.json({ period: 'week', trending });
  });

  return router;
}

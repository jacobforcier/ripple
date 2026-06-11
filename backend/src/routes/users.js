import { Router } from 'express';
import { rateLimit } from '../lib/rateLimit.js';
import { computeMilestones } from '../lib/milestones.js';

// The `db` client is injected so the routes can be tested with a mock.
export function makeUsersRouter(db) {
  const router = Router();

  // Anonymous-user creation is the most abusable endpoint (no auth, creates a
  // row). Cap per-IP creations so it can't be hammered to mass-create accounts.
  // Generous enough for shared NATs (offices, cafés) and app reinstalls.
  const createLimit = rateLimit(db, {
    bucket: 'users:create',
    max: Number(process.env.RL_USERS_MAX ?? 20),
    windowSec: Number(process.env.RL_USERS_WINDOW_SEC ?? 3600),
  });

  // ── POST /v1/users ─────────────────────────────────────────────────────────
  // Creates an anonymous user — a row with no email yet. Ripple is anonymous-
  // first: a user can share and earn immediately, with zero signup. The client
  // calls this once on first run, persists the returned id locally, and sends
  // it as `user_id` on every link it creates. A real account (email/auth) is
  // collected later, at payout time, when the user claims their balance.
  //   201: { id }
  //   429: { error }  — too many creations from this IP
  router.post('/', createLimit, async (_req, res) => {
    const { data, error } = await db
      .from('users')
      .insert({})
      .select('id')
      .single();

    if (error) {
      console.error('[users] create failed:', error);
      return res.status(500).json({ error: 'Failed to create user' });
    }
    return res.status(201).json({ id: data.id });
  });

  // ── GET /v1/users/:id/earnings ─────────────────────────────────────────────
  // Earnings summary for one user. Backs the earnings header in the dashboard /
  // iOS app. Amounts are the user's cut (after platform margin), in cents.
  //
  // `pending`   — sale registered, still inside the retailer's return window
  // `confirmed` — cleared by the affiliate network, withdrawable
  // `paid`      — already paid out to the user
  //   200: { user_id, lifetime_cents, pending_cents, confirmed_cents, paid_cents }
  router.get('/:id/earnings', async (req, res) => {
    const { id } = req.params;

    const { data, error } = await db
      .from('user_earnings')
      .select('*')
      .eq('user_id', id)
      .maybeSingle();

    if (error) {
      console.error('[users] earnings lookup failed:', error);
      return res.status(500).json({ error: 'Failed to load earnings' });
    }

    // No commissions yet → return a zeroed summary rather than 404.
    return res.json(
      data ?? {
        user_id: id,
        lifetime_cents: 0,
        pending_cents: 0,
        confirmed_cents: 0,
        paid_cents: 0,
      }
    );
  });

  // ── GET /v1/users/:id/milestones ───────────────────────────────────────────
  // Tier card + milestone checklist, computed from existing data (no writes).
  // Backs the earnings screen's progression UI and the app's celebration
  // moments (first click, earnings landing, tier-up).
  router.get('/:id/milestones', async (req, res) => {
    try {
      const payload = await computeMilestones(db, req.params.id);
      return res.json({ user_id: req.params.id, ...payload });
    } catch (err) {
      console.error('[users] milestones failed:', err);
      return res.status(500).json({ error: 'Failed to load milestones' });
    }
  });

  return router;
}

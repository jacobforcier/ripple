import { Router } from 'express';
import { db } from '../db.js';

export const usersRouter = Router();

// ── POST /v1/users ───────────────────────────────────────────────────────────
// Creates an anonymous user — a row with no email yet. Ripple is anonymous-
// first: a user can share and earn immediately, with zero signup. The client
// calls this once on first run, persists the returned id locally, and sends
// it as `user_id` on every link it creates. A real account (email/auth) is
// collected later, at payout time, when the user claims their balance.
//   201: { id }
usersRouter.post('/', async (_req, res) => {
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

// ── GET /v1/users/:id/earnings ───────────────────────────────────────────────
// Earnings summary for one user. Backs the earnings header in the dashboard /
// iOS app. Amounts are the user's cut (after platform margin), in cents.
//
// `pending`   — sale registered, still inside the retailer's return window
// `confirmed` — cleared by the affiliate network, withdrawable
// `paid`      — already paid out to the user
//   200: { user_id, lifetime_cents, pending_cents, confirmed_cents, paid_cents }
usersRouter.get('/:id/earnings', async (req, res) => {
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

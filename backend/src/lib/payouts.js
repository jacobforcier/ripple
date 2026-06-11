// Payout execution (B5d). Builds a batch of owed payouts and (on explicit
// approval) settles them via Stripe transfers. This is the money-movement
// layer — the orchestrating script (scripts/run_payouts.mjs) defaults to a
// dry run and only executes with --approve.
//
// Safety properties:
//   - Only pays users who are onboarded (connect_onboarded_at set) and meet a
//     minimum balance.
//   - Each transfer carries a deterministic Stripe idempotency key derived from
//     the user + the exact set of commissions, so re-running after a crash or
//     partial failure cannot double-pay: Stripe returns the original transfer.
//   - A failed transfer leaves its commissions 'confirmed' (not 'paid'), so the
//     next run retries them; nothing is silently lost.

import { createHash } from 'node:crypto';

/**
 * Build the list of payouts owed right now.
 *
 * @param {object} db
 * @param {object} opts
 * @param {number} opts.minCents  minimum balance to pay out (default $5.00)
 * @returns {Promise<Array<{user_id, amount_cents, commission_ids, stripe_connect_id}>>}
 */
export async function buildPayoutBatch(db, { minCents = 500 } = {}) {
  // Confirmed = cleared by the network, withdrawable, not yet paid.
  const { data: commissions, error: cErr } = await db
    .from('commissions')
    .select('id, user_id, group_id, user_cents')
    .eq('status', 'confirmed');
  if (cErr) throw new Error(`commission fetch failed: ${cErr.message}`);
  if (!commissions || commissions.length === 0) return [];

  // Sum per user, and per group pot.
  const byUser = new Map();
  const byGroup = new Map();
  for (const c of commissions) {
    if (c.group_id) {
      const e = byGroup.get(c.group_id) || { group_id: c.group_id, amount_cents: 0, commission_ids: [] };
      e.amount_cents += c.user_cents;
      e.commission_ids.push(c.id);
      byGroup.set(c.group_id, e);
    } else if (c.user_id) {
      const e = byUser.get(c.user_id) || { user_id: c.user_id, amount_cents: 0, commission_ids: [] };
      e.amount_cents += c.user_cents;
      e.commission_ids.push(c.id);
      byUser.set(c.user_id, e);
    } // orphaned (neither) — skip
  }

  // Group pots pay to the group's designated payout_user.
  if (byGroup.size > 0) {
    const { data: groups, error: gErr } = await db
      .from('groups')
      .select('id, payout_user_id')
      .in('id', [...byGroup.keys()]);
    if (gErr) throw new Error(`group fetch failed: ${gErr.message}`);
    for (const g of groups || []) {
      const e = byGroup.get(g.id);
      if (e) e.payout_user_id = g.payout_user_id;
    }
  }

  // Fetch payout-readiness for every receiving human (users + group recipients).
  const userIds = new Set([...byUser.keys()]);
  for (const e of byGroup.values()) if (e.payout_user_id) userIds.add(e.payout_user_id);
  if (userIds.size === 0) return [];
  const { data: users, error: uErr } = await db
    .from('users')
    .select('id, stripe_connect_id, connect_onboarded_at')
    .in('id', [...userIds]);
  if (uErr) throw new Error(`user fetch failed: ${uErr.message}`);
  const userMap = new Map((users || []).map((u) => [u.id, u]));

  const eligible = (uid) => {
    const u = userMap.get(uid);
    return u && u.stripe_connect_id && u.connect_onboarded_at ? u : null;
  };

  // Eligible = onboarded recipient AND >= minimum.
  const batch = [];
  for (const e of byUser.values()) {
    const u = eligible(e.user_id);
    if (!u || e.amount_cents < minCents) continue;
    batch.push({ ...e, stripe_connect_id: u.stripe_connect_id });
  }
  for (const e of byGroup.values()) {
    const u = e.payout_user_id ? eligible(e.payout_user_id) : null;
    if (!u || e.amount_cents < minCents) continue;
    // user_id here = transfer recipient; group_id marks it as a pot payout.
    batch.push({
      user_id: e.payout_user_id,
      group_id: e.group_id,
      amount_cents: e.amount_cents,
      commission_ids: e.commission_ids,
      stripe_connect_id: u.stripe_connect_id,
    });
  }
  return batch;
}

// Deterministic per (user, exact commission set) — re-running with the same
// owed commissions reuses the same key, so Stripe never creates a 2nd transfer.
export function payoutIdempotencyKey(userId, commissionIds) {
  const digest = createHash('sha256')
    .update(`${userId}:${[...commissionIds].sort().join(',')}`)
    .digest('hex');
  return `payout_${digest.slice(0, 40)}`;
}

/**
 * Execute a payout batch via Stripe transfers. Best-effort per recipient: one
 * failure doesn't abort the rest, and failures are recorded without flipping
 * their commissions to paid.
 *
 * @returns {Promise<Array<{user_id, status, amount_cents, transfer?, error?}>>}
 */
export async function executePayouts(db, stripe, batch, { log = () => {} } = {}) {
  const results = [];

  for (const entry of batch) {
    const { user_id, group_id = null, amount_cents, commission_ids, stripe_connect_id } = entry;
    try {
      const transfer = await stripe.transfers.create(
        {
          amount: amount_cents,
          currency: 'usd',
          destination: stripe_connect_id,
          metadata: {
            ripple_user_id: user_id,
            ...(group_id ? { ripple_group_id: group_id } : {}),
            commission_count: String(commission_ids.length),
          },
        },
        { idempotencyKey: payoutIdempotencyKey(user_id, commission_ids) }
      );

      const { data: payout, error: pErr } = await db
        .from('payouts')
        .insert({
          user_id,
          group_id,
          amount_cents,
          stripe_transfer_id: transfer.id,
          status: 'paid',
          paid_at: new Date().toISOString(),
        })
        .select('id')
        .single();
      if (pErr) throw new Error(`payout row insert failed: ${pErr.message}`);

      const { error: linkErr } = await db
        .from('commission_payouts')
        .insert(commission_ids.map((cid) => ({ payout_id: payout.id, commission_id: cid })));
      if (linkErr) throw new Error(`commission_payouts insert failed: ${linkErr.message}`);

      const { error: updErr } = await db
        .from('commissions')
        .update({ status: 'paid' })
        .in('id', commission_ids);
      if (updErr) throw new Error(`commission status update failed: ${updErr.message}`);

      results.push({ user_id, status: 'paid', amount_cents, transfer: transfer.id });
      log(`paid ${user_id}: $${(amount_cents / 100).toFixed(2)} (transfer ${transfer.id})`);
    } catch (err) {
      const message = String(err?.message || err);
      // Record the failure for audit; leave commissions 'confirmed' to retry.
      await db
        .from('payouts')
        .insert({ user_id, amount_cents, status: 'failed', error: message })
        .then(() => {}, () => {});
      results.push({ user_id, status: 'failed', amount_cents, error: message });
      log(`FAILED ${user_id}: ${message}`);
    }
  }

  return results;
}

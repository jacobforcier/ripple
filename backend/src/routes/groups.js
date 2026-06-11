// Ripple Groups — the opt-in "earn for us" mode. Individual earning is the
// default everywhere; a group only ever earns when a member explicitly points
// a link at it (links.js validates membership).

import { Router } from 'express';
import { newShortId } from '../lib/shortId.js';
import { rateLimit } from '../lib/rateLimit.js';

export function makeGroupsRouter(db) {
  const router = Router();

  const createLimit = rateLimit(db, {
    bucket: 'groups:create',
    max: Number(process.env.RL_GROUPS_MAX ?? 10),
    windowSec: Number(process.env.RL_GROUPS_WINDOW_SEC ?? 3600),
  });

  // ── POST /v1/groups ────────────────────────────────────────────────────
  // Create a group. Creator becomes owner, payout recipient, and first member.
  // Claims the group's own Amazon tracking id from the pool (best-effort —
  // shared-tag fallback if exhausted, same as users).
  //   body: { name, user_id }
  //   201: { id, name, join_code }
  router.post('/', createLimit, async (req, res) => {
    const name = String(req.body?.name || '').trim();
    const userId = req.body?.user_id;
    if (!name || name.length > 60) {
      return res.status(400).json({ error: 'a group name (≤60 chars) is required' });
    }
    if (!userId) return res.status(400).json({ error: 'user_id is required' });

    const { data: user, error: uErr } = await db
      .from('users').select('id').eq('id', userId).maybeSingle();
    if (uErr) return res.status(500).json({ error: 'lookup failed' });
    if (!user) return res.status(404).json({ error: 'user not found' });

    const join_code = newShortId();
    const { data: group, error: gErr } = await db
      .from('groups')
      .insert({ name, join_code, owner_user_id: userId, payout_user_id: userId })
      .select('id, name, join_code')
      .single();
    if (gErr) {
      console.error('[groups] create failed:', gErr);
      return res.status(500).json({ error: 'could not create group' });
    }

    const { error: mErr } = await db
      .from('group_members').insert({ group_id: group.id, user_id: userId });
    if (mErr) console.error('[groups] owner membership insert failed:', mErr);

    // Claim the group's tracking id (fail-soft; links fall back to shared tag).
    try {
      await db.rpc('claim_group_tracking_id', { p_group_id: group.id });
    } catch (err) {
      console.error('[groups] tracking-id claim failed:', err);
    }

    return res.status(201).json(group);
  });

  // ── POST /v1/groups/:code/join ─────────────────────────────────────────
  //   body: { user_id }   200: { id, name }   404: bad code
  router.post('/:code/join', async (req, res) => {
    const userId = req.body?.user_id;
    if (!userId) return res.status(400).json({ error: 'user_id is required' });

    const { data: group, error } = await db
      .from('groups').select('id, name').eq('join_code', req.params.code).maybeSingle();
    if (error) return res.status(500).json({ error: 'lookup failed' });
    if (!group) return res.status(404).json({ error: 'group not found' });

    const { error: mErr } = await db
      .from('group_members')
      .upsert({ group_id: group.id, user_id: userId }, { onConflict: 'group_id,user_id' });
    if (mErr) {
      console.error('[groups] join failed:', mErr);
      return res.status(500).json({ error: 'could not join group' });
    }
    return res.json(group);
  });

  // ── GET /v1/groups/:id ─────────────────────────────────────────────────
  // Group info + pot earnings (mirrors the user earnings shape).
  router.get('/:id', async (req, res) => {
    const { data: group, error } = await db
      .from('groups').select('id, name, join_code, owner_user_id, payout_user_id')
      .eq('id', req.params.id).maybeSingle();
    if (error) return res.status(500).json({ error: 'lookup failed' });
    if (!group) return res.status(404).json({ error: 'group not found' });

    const { data: earnings } = await db
      .from('group_earnings').select('*').eq('group_id', group.id).maybeSingle();
    return res.json({
      ...group,
      earnings: earnings ?? {
        group_id: group.id, lifetime_cents: 0,
        pending_cents: 0, confirmed_cents: 0, paid_cents: 0,
      },
    });
  });

  return router;
}

// Internal admin endpoints. Not for the extension, the website, or the iOS app.
// Backs the CSV ingestion script (B5b) and any future operator tooling.
//
// Auth: a single shared secret in process.env.ADMIN_API_KEY, sent as the
// X-Admin-Key header. Constant-time compared. We fail CLOSED if the env var is
// unset so a misconfigured deploy can't accidentally expose the endpoint.

import { Router } from 'express';
import { timingSafeEqual } from 'node:crypto';
import { recordCommission } from '../lib/commissions.js';

export function makeAdminRouter(db) {
  const router = Router();

  // ── Auth middleware ────────────────────────────────────────────────────
  router.use((req, res, next) => {
    const expected = process.env.ADMIN_API_KEY || '';
    const provided = req.header('x-admin-key') || '';

    // No key configured → endpoint is disabled. Don't leak why.
    if (!expected) {
      return res.status(503).json({ error: 'admin endpoint not configured' });
    }

    // Equal-length check guards timingSafeEqual (which throws on length
    // mismatch) and any timing-channel leak about the expected length.
    const ok =
      provided.length === expected.length &&
      timingSafeEqual(Buffer.from(provided), Buffer.from(expected));
    if (!ok) {
      return res.status(401).json({ error: 'unauthorized' });
    }
    next();
  });

  // ── POST /v1/admin/commissions ─────────────────────────────────────────
  // Batch-record commissions. Best-effort per row — one bad row doesn't
  // tank the rest (re-runs are idempotent on (retailer, externalRef)).
  //
  //   body: { commissions: [
  //     { linkId, retailer, grossCents, userCents, status?, occurredAt, externalRef? },
  //     …
  //   ] }
  //   201: { recorded, results: [{ index, id?, status?, error? }] }
  //   400: invalid envelope
  //   413: batch too large
  router.post('/commissions', async (req, res) => {
    const items = Array.isArray(req.body?.commissions) ? req.body.commissions : null;
    if (!items || items.length === 0) {
      return res.status(400).json({ error: 'commissions array required' });
    }
    if (items.length > 1000) {
      return res.status(413).json({ error: 'batch too large (max 1000)' });
    }

    const results = [];
    let recorded = 0;
    for (let i = 0; i < items.length; i++) {
      try {
        const out = await recordCommission(db, items[i]);
        results.push({ index: i, id: out.id, status: out.status });
        recorded++;
      } catch (err) {
        results.push({ index: i, error: String(err?.message || err) });
      }
    }
    return res.status(201).json({ recorded, results });
  });

  return router;
}

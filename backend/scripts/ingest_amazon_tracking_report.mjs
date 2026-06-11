// B5b — ingest an Amazon Associates "Tracking ID" report.
//
// Amazon doesn't expose ascsubtag reporting to regular associates, but the
// per-Tracking-ID report IS available to everyone. We assign each sharer their
// own tracking id (see lib/trackingIds.js), so this report's per-id earnings
// map directly to a user.
//
// Usage, from backend/:
//   node scripts/ingest_amazon_tracking_report.mjs <report.csv> --period=2026-05
//   (optional)  --split=0.5   FLAT override of the user's share. Without it,
//   each user's share comes from their TIER (Drop 40% → Tide 55%, see
//   lib/tiers.js); groups are flat 50%.
//
// Idempotent: external_ref = "<tracking_id>:<period>", so re-ingesting the same
// month UPDATES that user's commission row to the latest total instead of
// duplicating. Run after each report pull; safe to re-run.
//
// Expected columns (from a real export):
//   Tracking Id, Clicks, Items Ordered, Ordered Revenue, Items Shipped,
//   Items Returned, ..., Total Earnings, Bonus, Items Shipped Earnings, ...

import 'dotenv/config';
import { readFileSync } from 'node:fs';
import { parse } from 'csv-parse/sync';
import { createClient } from '@supabase/supabase-js';
import { recordCommission } from '../src/lib/commissions.js';
import { ingestRateFor } from '../src/lib/tiers.js';

const [csvPath] = process.argv.slice(2).filter((a) => !a.startsWith('--'));
const periodArg = process.argv.find((a) => a.startsWith('--period='));
const splitArg = process.argv.find((a) => a.startsWith('--split='));
const period = periodArg ? periodArg.split('=')[1] : null;
const userShare = splitArg ? parseFloat(splitArg.split('=')[1]) : 0.5;

if (!csvPath || !period) {
  console.error('Usage: node scripts/ingest_amazon_tracking_report.mjs <report.csv> --period=YYYY-MM [--split=0.5]');
  process.exit(1);
}

const dollarsToCents = (s) => Math.round(parseFloat(String(s).replace(/[^0-9.\-]/g, '') || '0') * 100);

const db = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

const rows = parse(readFileSync(csvPath), { columns: true, skip_empty_lines: true, trim: true });
console.log(`\nIngesting ${rows.length} row(s) from ${csvPath} for period ${period} (user share ${userShare})\n`);

let recorded = 0, skipped = 0, unmapped = 0;
for (const row of rows) {
  const trackingId = row['Tracking Id'];
  const grossCents = dollarsToCents(row['Total Earnings']);
  if (!trackingId || grossCents <= 0) { skipped++; continue; }

  // Map tracking id → its owner (a user, or a group pot) via the pool.
  const { data: pool, error: poolErr } = await db
    .from('amazon_tracking_ids')
    .select('user_id, group_id')
    .eq('tracking_id', trackingId)
    .maybeSingle();
  if (poolErr) { console.error(`  ${trackingId}: pool lookup failed: ${poolErr.message}`); skipped++; continue; }
  if (!pool || (!pool.user_id && !pool.group_id)) {
    // Unassigned id (or the default shared tag) — no owner to attribute to.
    console.log(`  ${trackingId}: no owner mapped — skipping ($${(grossCents/100).toFixed(2)})`);
    unmapped++;
    continue;
  }

  // Split rate: the owner's TIER (Drop→Tide) decides the user's share, based
  // on their lifetime confirmed earnings BEFORE this row. Groups stay at 50%.
  // An explicit --split=X on the command line overrides tiers entirely.
  let rate = userShare;
  if (!splitArg) {
    if (pool.group_id) {
      rate = ingestRateFor({ isGroup: true });
    } else {
      const { data: earn } = await db
        .from('user_earnings')
        .select('confirmed_cents, paid_cents')
        .eq('user_id', pool.user_id)
        .maybeSingle();
      rate = ingestRateFor({
        lifetimeConfirmedCents: (earn?.confirmed_cents ?? 0) + (earn?.paid_cents ?? 0),
      });
    }
  }

  const userCents = Math.round(grossCents * rate);
  try {
    await recordCommission(db, {
      ...(pool.group_id ? { groupId: pool.group_id } : { userId: pool.user_id }),
      retailer: 'Amazon',
      grossCents,
      userCents,
      status: 'confirmed',
      occurredAt: `${period}-01T00:00:00Z`,
      externalRef: `${trackingId}:${period}`,
    });
    recorded++;
    const owner = pool.group_id ? `group ${pool.group_id}` : `user ${pool.user_id}`;
    console.log(`  ${trackingId} → ${owner}: gross $${(grossCents/100).toFixed(2)} / share $${(userCents/100).toFixed(2)}`);
  } catch (err) {
    console.error(`  ${trackingId}: recordCommission failed: ${err.message}`);
    skipped++;
  }
}

console.log(`\nDone. recorded=${recorded} unmapped=${unmapped} skipped=${skipped}\n`);

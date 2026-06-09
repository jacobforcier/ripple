// Payout runner (B5d). Reviews and (on explicit approval) executes payouts.
//
// Usage, from backend/:
//   node scripts/run_payouts.mjs              # DRY RUN — shows what would pay
//   node scripts/run_payouts.mjs --min=1000   # dry run, $10.00 minimum
//   node scripts/run_payouts.mjs --approve     # ACTUALLY transfers money
//
// Dry run is the default and moves no money. --approve is the human approval
// step — a person must run it deliberately. Always dry-run first and read the
// batch before approving. In live mode this moves REAL money.

import 'dotenv/config';
import { createClient } from '@supabase/supabase-js';
import { getStripe } from '../src/lib/stripe.js';
import { buildPayoutBatch, executePayouts } from '../src/lib/payouts.js';

const args = process.argv.slice(2);
const approve = args.includes('--approve');
const minArg = args.find((a) => a.startsWith('--min='));
const minCents = minArg ? parseInt(minArg.split('=')[1], 10) : 500;

const usd = (cents) => `$${(cents / 100).toFixed(2)}`;

const db = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

const batch = await buildPayoutBatch(db, { minCents });

console.log(`\nPayout batch — minimum ${usd(minCents)} — ${batch.length} recipient(s)\n`);
let total = 0;
for (const e of batch) {
  total += e.amount_cents;
  console.log(`  ${e.user_id}   ${usd(e.amount_cents).padStart(9)}   ${e.commission_ids.length} commission(s)   → ${e.stripe_connect_id}`);
}
console.log(`\n  TOTAL: ${usd(total)}\n`);

if (batch.length === 0) {
  console.log('Nothing to pay out.\n');
  process.exit(0);
}

if (!approve) {
  console.log('DRY RUN — no money moved.');
  console.log('Re-run with --approve to execute these transfers.\n');
  process.exit(0);
}

const stripe = getStripe();
if (!stripe) {
  console.error('ERROR: STRIPE_SECRET_KEY is not configured. Aborting.\n');
  process.exit(1);
}

console.log('--approve set. Executing transfers via Stripe...\n');
const results = await executePayouts(db, stripe, batch, { log: (m) => console.log('  ' + m) });

const paid = results.filter((r) => r.status === 'paid');
const failed = results.filter((r) => r.status === 'failed');
const paidTotal = paid.reduce((s, r) => s + r.amount_cents, 0);

console.log(`\nDone. paid=${paid.length} (${usd(paidTotal)})  failed=${failed.length}`);
if (failed.length) {
  console.log('\nFailures (commissions left confirmed for retry):');
  for (const f of failed) console.log(`  ${f.user_id}: ${f.error}`);
}
console.log('');
process.exit(failed.length ? 1 : 0);

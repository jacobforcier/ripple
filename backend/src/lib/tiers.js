// Earning tiers (Drop → Ripple → Wave → Tide).
//
// The platform split, reframed as a ladder the user climbs. Tiers are based on
// LIFETIME CONFIRMED EARNINGS (the user's own cents, confirmed + paid) — never
// on actions like links created, which would be gameable. Tiers never decay.
//
// The rate applies at INGEST time: a commission is split at the rate of the
// owner's tier when the report row is recorded. Climbing affects future
// earnings, not past ones — simple to reason about, honest to display.
//
// Thresholds are config-grade guesses until beta data exists; tune freely
// (env-overridable), but never lower a live user's already-earned tier.

export const TIERS = [
  { name: 'Drop',   rate: 0.40, minCents: 0 },
  { name: 'Ripple', rate: 0.45, minCents: 1 },     // first confirmed cent
  { name: 'Wave',   rate: 0.50, minCents: 1000 },  // $10 lifetime confirmed
  { name: 'Tide',   rate: 0.55, minCents: 5000 },  // $50 lifetime confirmed
];

/** The tier for a lifetime-confirmed-earnings total (confirmed + paid cents). */
export function tierForEarnings(lifetimeConfirmedCents) {
  const cents = Math.max(0, lifetimeConfirmedCents | 0);
  let current = TIERS[0];
  for (const t of TIERS) if (cents >= t.minCents) current = t;
  return current;
}

/** Tier + progress payload for the API/app. */
export function tierProgress(lifetimeConfirmedCents) {
  const cents = Math.max(0, lifetimeConfirmedCents | 0);
  const current = tierForEarnings(cents);
  const idx = TIERS.indexOf(current);
  const next = TIERS[idx + 1] ?? null;
  return {
    tier: current.name,
    rate: current.rate,
    lifetime_confirmed_cents: cents,
    next: next
      ? { tier: next.name, rate: next.rate, remaining_cents: Math.max(0, next.minCents - cents) }
      : null, // top of the ladder
  };
}

/**
 * The split rate to apply when ingesting a commission for a user, given their
 * lifetime confirmed earnings BEFORE this commission. Groups stay at a flat
 * 50% in v1 (pots don't climb tiers — revisit if group usage takes off).
 */
export function ingestRateFor({ lifetimeConfirmedCents = 0, isGroup = false }) {
  if (isGroup) return 0.5;
  return tierForEarnings(lifetimeConfirmedCents).rate;
}

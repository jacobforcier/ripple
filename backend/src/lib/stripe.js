import Stripe from 'stripe';

// Lazy singleton Stripe client.
//
// Read the key at call time (not module load) so the rest of the app and the
// test suite don't crash when STRIPE_SECRET_KEY isn't configured. Returns null
// when unset — callers treat "no client" as "payouts not configured yet" and
// respond 503 rather than throwing.
let _stripe = null;

export function getStripe() {
  if (_stripe) return _stripe;
  const key = process.env.STRIPE_SECRET_KEY;
  if (!key) return null;
  _stripe = new Stripe(key);
  return _stripe;
}

// Test seam: let tests reset the memoized client between cases.
export function _resetStripeForTests() {
  _stripe = null;
}

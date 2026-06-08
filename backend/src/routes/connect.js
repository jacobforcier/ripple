// Stripe Connect onboarding (B5c). Lets a user attach a payout account so B5d
// can transfer their earnings.
//
// Flow:
//   1. POST /v1/users/:id/claim          — attach an email to the anon user
//   2. POST /v1/users/:id/connect/start  — create an Express account + return a
//                                          Stripe-hosted onboarding URL
//   3. (user completes Stripe's form; the account.updated webhook flips
//      connect_onboarded_at once payouts are enabled — see stripeWebhook.js)
//   4. GET  /v1/users/:id/connect/status — current onboarding state
//
// The Stripe client is injected (like db) so tests can pass a mock; in prod it
// falls back to the lazy singleton in lib/stripe.js.

import { Router } from 'express';
import { getStripe } from '../lib/stripe.js';

const SITE_URL = process.env.SITE_URL || 'https://www.sharewithripple.com';
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function makeConnectRouter(db, { stripe: injectedStripe } = {}) {
  const router = Router();
  const resolveStripe = () => injectedStripe || getStripe();

  // ── POST /v1/users/:id/claim ────────────────────────────────────────────
  // Attach an email to an anonymous user. Required before onboarding so Stripe
  // has somewhere to send account notices. Idempotent: re-claiming the same
  // email on the same user is fine.
  //   body: { email }
  //   200: { id, email }   400: bad email   404: no user   409: email in use
  router.post('/:id/claim', async (req, res) => {
    const { id } = req.params;
    const email = String(req.body?.email || '').trim().toLowerCase();
    if (!EMAIL_RE.test(email)) {
      return res.status(400).json({ error: 'a valid email is required' });
    }

    const { data: user, error: lookupErr } = await db
      .from('users')
      .select('id, email')
      .eq('id', id)
      .maybeSingle();
    if (lookupErr) {
      console.error('[connect] claim lookup failed:', lookupErr);
      return res.status(500).json({ error: 'lookup failed' });
    }
    if (!user) return res.status(404).json({ error: 'user not found' });

    const { error: updErr } = await db.from('users').update({ email }).eq('id', id);
    if (updErr) {
      // Most likely a unique-violation: the email belongs to another user.
      console.error('[connect] claim update failed:', updErr);
      return res.status(409).json({ error: 'that email is already in use' });
    }
    return res.json({ id, email });
  });

  // ── POST /v1/users/:id/connect/start ────────────────────────────────────
  // Create (or reuse) the user's Express account and return a fresh onboarding
  // URL. The client redirects the user there; Stripe hosts the rest.
  //   200: { url, account }   400: no email yet   404: no user
  //   502: stripe error       503: payouts not configured
  router.post('/:id/connect/start', async (req, res) => {
    const stripe = resolveStripe();
    if (!stripe) return res.status(503).json({ error: 'payouts are not configured yet' });

    const { id } = req.params;
    const { data: user, error } = await db
      .from('users')
      .select('id, email, stripe_connect_id')
      .eq('id', id)
      .maybeSingle();
    if (error) {
      console.error('[connect] start lookup failed:', error);
      return res.status(500).json({ error: 'lookup failed' });
    }
    if (!user) return res.status(404).json({ error: 'user not found' });
    if (!user.email) {
      return res.status(400).json({ error: 'claim an email before connecting payouts' });
    }

    try {
      let accountId = user.stripe_connect_id;
      if (!accountId) {
        const account = await stripe.accounts.create({
          type: 'express',
          email: user.email,
          // Ripple users only RECEIVE payouts — they're individuals, not
          // businesses selling things. Setting business_type skips the
          // company/business branch of onboarding.
          //
          // (The lighter "recipient" service agreement would be ideal, but
          // Stripe only allows it for cross-border payouts — a US platform
          // paying US recipients can't use it.)
          business_type: 'individual',
          capabilities: { transfers: { requested: true } },
          // PREFILL the business profile. Stripe only asks the user for fields
          // that are still missing, so by supplying the URL, industry, and a
          // description here, the user is never prompted for a website or
          // "what do you sell." What remains is the unavoidable US identity +
          // bank verification (KYC), which every payout recipient must do.
          business_profile: {
            url: 'https://www.sharewithripple.com',
            mcc: '5969', // Direct marketing / direct response
            product_description:
              'Receives a small reward when a friend buys through a product link they shared via Ripple.',
          },
          metadata: { ripple_user_id: id },
        });
        accountId = account.id;
        const { error: saveErr } = await db
          .from('users')
          .update({ stripe_connect_id: accountId })
          .eq('id', id);
        if (saveErr) {
          // Persisting the id failed — surface it rather than orphan the account.
          console.error('[connect] failed to save stripe_connect_id:', saveErr);
          return res.status(500).json({ error: 'could not persist account' });
        }
      }

      const link = await stripe.accountLinks.create({
        account: accountId,
        refresh_url: `${SITE_URL}/?connect=refresh`,
        return_url: `${SITE_URL}/?connect=return`,
        type: 'account_onboarding',
      });
      return res.json({ url: link.url, account: accountId });
    } catch (err) {
      console.error('[connect] start failed:', err);
      return res.status(502).json({ error: 'could not start onboarding' });
    }
  });

  // ── GET /v1/users/:id/connect/status ────────────────────────────────────
  // Current onboarding state. Reads live truth from Stripe when available,
  // falling back to the DB flag if Stripe isn't configured.
  //   200: { connected, payouts_enabled, details_submitted?, account?, onboarded_at? }
  router.get('/:id/connect/status', async (req, res) => {
    const { id } = req.params;
    const { data: user, error } = await db
      .from('users')
      .select('id, stripe_connect_id, connect_onboarded_at')
      .eq('id', id)
      .maybeSingle();
    if (error) {
      console.error('[connect] status lookup failed:', error);
      return res.status(500).json({ error: 'lookup failed' });
    }
    if (!user) return res.status(404).json({ error: 'user not found' });

    if (!user.stripe_connect_id) {
      return res.json({ connected: false, payouts_enabled: false });
    }

    const stripe = resolveStripe();
    if (!stripe) {
      // No live client — report what we know from the webhook-maintained flag.
      const onboarded = !!user.connect_onboarded_at;
      return res.json({
        connected: true,
        payouts_enabled: onboarded,
        account: user.stripe_connect_id,
        onboarded_at: user.connect_onboarded_at,
      });
    }

    try {
      const account = await stripe.accounts.retrieve(user.stripe_connect_id);
      return res.json({
        connected: true,
        account: user.stripe_connect_id,
        payouts_enabled: !!account.payouts_enabled,
        details_submitted: !!account.details_submitted,
        onboarded_at: user.connect_onboarded_at,
      });
    } catch (err) {
      console.error('[connect] status retrieve failed:', err);
      return res.status(502).json({ error: 'could not load account status' });
    }
  });

  return router;
}

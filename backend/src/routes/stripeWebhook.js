// Stripe webhook handler (B5c). Receives Connect events and keeps our DB in
// sync with Stripe's view of each user's payout account.
//
// IMPORTANT: signature verification needs the RAW request body, so this router
// uses express.raw() and MUST be mounted before the global express.json() in
// app.js. If json() parses the body first, the signature check always fails.
//
// Events handled (configured on the Stripe endpoint, "Connected accounts" scope):
//   account.updated                  → set connect_onboarded_at when payouts_enabled
//   account.application.deauthorized → user disconnected; clear their account
//   payout.paid / payout.failed      → logged now; B5d will consume these

import { Router } from 'express';
import express from 'express';
import { getStripe } from '../lib/stripe.js';

export function makeStripeWebhookRouter(db, { stripe: injectedStripe } = {}) {
  const router = Router();

  router.post('/webhook', express.raw({ type: '*/*' }), async (req, res) => {
    const stripe = injectedStripe || getStripe();
    const secret = process.env.STRIPE_WEBHOOK_SECRET;
    if (!stripe || !secret) {
      return res.status(503).json({ error: 'webhook not configured' });
    }

    let event;
    try {
      event = stripe.webhooks.constructEvent(
        req.body,
        req.headers['stripe-signature'],
        secret
      );
    } catch (err) {
      console.error('[stripe webhook] signature verification failed:', err.message);
      return res.status(400).json({ error: 'invalid signature' });
    }

    try {
      await handleEvent(db, event);
    } catch (err) {
      // 500 → Stripe retries with backoff, which is what we want for a
      // transient DB hiccup.
      console.error(`[stripe webhook] handler error for ${event.type}:`, err);
      return res.status(500).json({ error: 'handler error' });
    }

    return res.json({ received: true });
  });

  return router;
}

// Exported for direct unit testing without HTTP/signature plumbing.
export async function handleEvent(db, event) {
  switch (event.type) {
    case 'account.updated': {
      const account = event.data.object;
      // Only flip the flag once Stripe says the account can actually receive
      // payouts. Idempotent — re-delivery just rewrites the same timestamp.
      if (account?.payouts_enabled) {
        const { error } = await db
          .from('users')
          .update({ connect_onboarded_at: new Date().toISOString() })
          .eq('stripe_connect_id', account.id);
        if (error) throw new Error(`account.updated DB write failed: ${error.message}`);
      }
      break;
    }

    case 'account.application.deauthorized': {
      // The user disconnected Ripple from their Stripe account. event.account is
      // the connected account id. Clear our linkage so they can re-onboard clean.
      const accountId = event.account || event.data?.object?.id;
      if (accountId) {
        const { error } = await db
          .from('users')
          .update({ stripe_connect_id: null, connect_onboarded_at: null })
          .eq('stripe_connect_id', accountId);
        if (error) throw new Error(`deauthorized DB write failed: ${error.message}`);
      }
      break;
    }

    case 'payout.paid':
    case 'payout.failed':
      // B5d (payout execution) will reconcile these against the payouts table.
      // For now just observe them.
      console.log(`[stripe webhook] ${event.type}:`, event.data?.object?.id);
      break;

    default:
      // Ignore everything else; Stripe sends more than we subscribe to.
      break;
  }
}

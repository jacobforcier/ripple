-- ── Stripe Connect onboarding state ─────────────────────────────────────────
-- users.stripe_connect_id already exists (the Express account id). This adds a
-- timestamp marking when that account became payout-ready, set by the
-- account.updated webhook once Stripe reports payouts_enabled=true.
--
-- Why a separate column instead of inferring from stripe_connect_id: an account
-- can exist (id stored) but not yet be onboarded (user abandoned the Stripe
-- form). connect_onboarded_at NULL = account created but not payout-ready;
-- non-NULL = good to receive transfers. B5d (payouts) only pays onboarded users.

alter table users
    add column if not exists connect_onboarded_at timestamptz;

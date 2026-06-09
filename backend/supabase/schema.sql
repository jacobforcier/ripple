-- ═════════════════════════════════════════════════════════════════════════════
--  Ripple — database schema (Supabase / Postgres)
--
--  Run this in the Supabase SQL editor to provision the database.
--  The API connects with the service-role key and bypasses RLS; RLS policies
--  below are a safety net for any future client-side (anon key) access.
-- ═════════════════════════════════════════════════════════════════════════════

-- ── Users ────────────────────────────────────────────────────────────────────
-- One row per Ripple user. Anonymous-first: a user can share and earn before
-- they have an email. `email` is collected later, at payout time, when the
-- user creates a real account and claims their balance — so it's nullable.
-- The UNIQUE constraint still holds (Postgres allows multiple NULLs).
create table if not exists users (
    id                    uuid primary key default gen_random_uuid(),
    email                 text unique,              -- null until the user claims an account (at payout time)
    display_name          text,                     -- shown on the redirect page ("Jacob shared this")
    stripe_connect_id     text,                     -- Stripe Express account id, set when the user starts onboarding
    connect_onboarded_at  timestamptz,              -- set when Stripe reports payouts_enabled (account.updated webhook)
    created_at            timestamptz not null default now()
);

-- ── Links ────────────────────────────────────────────────────────────────────
-- One row per Ripple link. `id` is the short code in sharewithripple.com/s/<id>.
-- `affiliate_url` is the tracked URL from the affiliate network — null until the
-- network integration is live (currently passthrough of source_url).
create table if not exists links (
    id              text primary key,               -- short code, e.g. "k7m2xqp"
    user_id         uuid references users(id) on delete set null,
    source_url      text not null,                  -- original product URL the user shared
    affiliate_url   text,                           -- tracked URL (null = not yet generated)
    retailer        text,                           -- e.g. "Amazon" — derived from source_url
    -- Cached Open Graph metadata from the source URL, used to render
    -- product-specific link previews when the Ripple link is shared.
    og_title        text,
    og_image        text,
    og_description  text,
    created_at      timestamptz not null default now()
);

create index if not exists links_user_id_idx on links(user_id);
create index if not exists links_created_at_idx on links(created_at desc);

-- ── Clicks ───────────────────────────────────────────────────────────────────
-- One row per click on a Ripple link. ip_hash is a salted hash, never a raw IP.
create table if not exists clicks (
    id          uuid primary key default gen_random_uuid(),
    link_id     text not null references links(id) on delete cascade,
    ip_hash     text,                               -- salted SHA-256, for dedup / fraud signals
    user_agent  text,
    clicked_at  timestamptz not null default now()
);

create index if not exists clicks_link_id_idx on clicks(link_id);
create index if not exists clicks_clicked_at_idx on clicks(clicked_at desc);

-- ── Commissions ──────────────────────────────────────────────────────────────
-- One row per attributed sale. Populated later by a webhook/poller from the
-- affiliate network. status lifecycle: pending -> confirmed -> paid.
--   gross_cents = commission paid to the platform by the network
--   user_cents  = the sharer's cut after the platform margin
create table if not exists commissions (
    id              uuid primary key default gen_random_uuid(),
    link_id         text references links(id) on delete set null,
    user_id         uuid references users(id) on delete set null,
    retailer        text,
    gross_cents     integer not null default 0,
    user_cents      integer not null default 0,
    status          text not null default 'pending'
                        check (status in ('pending', 'confirmed', 'paid')),
    occurred_at     timestamptz not null default now(),  -- when the sale happened
    confirmed_at    timestamptz,                         -- when the network confirmed it
    created_at      timestamptz not null default now(),
    -- external_ref = the affiliate network's own id for this commission row,
    -- used to make report ingestion idempotent. Nullable so manual inserts
    -- don't need one; the uniqueness constraint is partial (see below).
    external_ref    text
);

create index if not exists commissions_user_id_idx on commissions(user_id);
create index if not exists commissions_link_id_idx on commissions(link_id);
create index if not exists commissions_status_idx on commissions(status);
-- Full (non-partial) unique index. PostgREST's INSERT ... ON CONFLICT can't
-- resolve a partial index without the predicate, which broke recordCommission.
-- Multiple NULL external_refs are still allowed because Postgres treats NULLs
-- as distinct in unique indexes by default. See migration 005.
create unique index if not exists commissions_external_ref_unique
    on commissions (retailer, external_ref);

-- ── Payouts ──────────────────────────────────────────────────────────────────
-- One row per Stripe transfer attempt to a user (B5d). commission_payouts is
-- the join recording exactly which commissions a payout settled. See migration
-- 007 + scripts/run_payouts.mjs.
create table if not exists payouts (
    id                  uuid primary key default gen_random_uuid(),
    user_id             uuid references users(id) on delete set null,
    amount_cents        integer not null,
    currency            text not null default 'usd',
    stripe_transfer_id  text,
    status              text not null default 'pending'
                            check (status in ('pending', 'paid', 'failed')),
    error               text,
    created_at          timestamptz not null default now(),
    paid_at             timestamptz
);

create index if not exists payouts_user_id_idx on payouts(user_id);
create index if not exists payouts_status_idx  on payouts(status);

create table if not exists commission_payouts (
    payout_id      uuid references payouts(id) on delete cascade,
    commission_id  uuid references commissions(id) on delete cascade,
    primary key (payout_id, commission_id)
);

create index if not exists commission_payouts_commission_idx
    on commission_payouts(commission_id);

-- ── Rate limiting ────────────────────────────────────────────────────────────
-- Per-IP sliding-window store for the API's write endpoints. Postgres-backed
-- (not in-memory) because the API is serverless and instances don't share
-- memory. See migration 003 + src/lib/rateLimit.js. `ip_hash` is the salted
-- SHA-256 used elsewhere — never a raw IP.
create table if not exists rate_limit_hits (
    id          bigint generated always as identity primary key,
    bucket      text        not null,   -- e.g. 'users:create', 'links:create'
    ip_hash     text        not null,
    created_at  timestamptz not null default now()
);

create index if not exists rate_limit_hits_lookup
    on rate_limit_hits (bucket, ip_hash, created_at desc);
create index if not exists rate_limit_hits_created_at
    on rate_limit_hits (created_at);

-- ── View: per-link stats ─────────────────────────────────────────────────────
-- Backs the "your links" list in the dashboard / iOS app.
create or replace view link_stats as
select
    l.id,
    l.user_id,
    l.source_url,
    l.retailer,
    l.created_at,
    count(distinct c.id)                                          as click_count,
    coalesce(sum(cm.user_cents), 0)                               as earned_cents,
    coalesce(sum(cm.user_cents) filter (where cm.status = 'pending'), 0)   as pending_cents,
    coalesce(sum(cm.user_cents) filter (where cm.status = 'confirmed'), 0) as confirmed_cents,
    coalesce(sum(cm.user_cents) filter (where cm.status = 'paid'), 0)      as paid_cents
from links l
left join clicks c       on c.link_id = l.id
left join commissions cm on cm.link_id = l.id
group by l.id;

-- ── View: per-user earnings summary ──────────────────────────────────────────
-- Backs the earnings header in the dashboard / iOS app.
create or replace view user_earnings as
select
    u.id as user_id,
    coalesce(sum(cm.user_cents), 0)                                       as lifetime_cents,
    coalesce(sum(cm.user_cents) filter (where cm.status = 'pending'), 0)   as pending_cents,
    coalesce(sum(cm.user_cents) filter (where cm.status = 'confirmed'), 0) as confirmed_cents,
    coalesce(sum(cm.user_cents) filter (where cm.status = 'paid'), 0)      as paid_cents
from users u
left join commissions cm on cm.user_id = u.id
group by u.id;

-- ── Row-level security ───────────────────────────────────────────────────────
-- The API uses the service-role key, which bypasses RLS. These policies only
-- matter if/when a client ever connects with the anon key. Default-deny is the
-- safe posture until that's designed.
alter table users       enable row level security;
alter table links       enable row level security;
alter table clicks      enable row level security;
alter table commissions enable row level security;

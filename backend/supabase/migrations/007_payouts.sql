-- ── Payouts (B5d) ───────────────────────────────────────────────────────────
-- One row per Stripe transfer we attempt to a user. Records the outcome so we
-- have an auditable money-movement trail separate from the commissions table.
--
-- commission_payouts is the join: exactly which commissions were settled by a
-- given payout. When a payout succeeds, its commissions flip to status='paid',
-- and these rows are the permanent record of what was included.

create table if not exists payouts (
    id                  uuid primary key default gen_random_uuid(),
    user_id             uuid references users(id) on delete set null,
    amount_cents        integer not null,
    currency            text not null default 'usd',
    stripe_transfer_id  text,                       -- null until/unless the transfer succeeds
    status              text not null default 'pending'
                            check (status in ('pending', 'paid', 'failed')),
    error               text,                       -- failure reason when status='failed'
    created_at          timestamptz not null default now(),
    paid_at             timestamptz                 -- set when the transfer succeeds
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

alter table payouts enable row level security;
alter table commission_payouts enable row level security;

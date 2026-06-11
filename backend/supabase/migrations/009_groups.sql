-- ── Ripple Groups ("earn for us") ────────────────────────────────────────────
-- Opt-in second earning mode. Individual earning stays the default: a link
-- earns for its creator unless they explicitly point it at a group. A group
-- claims its own Amazon tracking id, so the standard Tracking ID report
-- attributes group sales the same way it attributes personal ones.

create table if not exists groups (
    id              uuid primary key default gen_random_uuid(),
    name            text not null,
    join_code       text unique not null,            -- short code for invites
    owner_user_id   uuid references users(id) on delete set null,
    payout_user_id  uuid references users(id) on delete set null,  -- designated recipient (default: owner)
    created_at      timestamptz not null default now()
);

create table if not exists group_members (
    group_id   uuid references groups(id) on delete cascade,
    user_id    uuid references users(id) on delete cascade,
    joined_at  timestamptz not null default now(),
    primary key (group_id, user_id)
);

-- A link may earn for a group instead of its creator.
alter table links add column if not exists group_id uuid references groups(id) on delete set null;
create index if not exists links_group_id_idx on links(group_id);

-- A commission may belong to a group (user_id stays null in that case).
alter table commissions add column if not exists group_id uuid references groups(id) on delete set null;
create index if not exists commissions_group_id_idx on commissions(group_id);

-- Payout audit: which group a payout settled (paid to its payout_user).
alter table payouts add column if not exists group_id uuid references groups(id) on delete set null;

-- Tracking ids can be claimed by a group OR a user, never both.
alter table amazon_tracking_ids add column if not exists group_id uuid unique references groups(id) on delete set null;
alter table amazon_tracking_ids drop constraint if exists tracking_id_one_owner;
alter table amazon_tracking_ids add constraint tracking_id_one_owner
    check (user_id is null or group_id is null);

-- Atomic group claim — mirrors claim_tracking_id(p_user_id).
create or replace function claim_group_tracking_id(p_group_id uuid)
returns text language plpgsql as $$
declare existing_id text; claimed_id text;
begin
    select tracking_id into existing_id from amazon_tracking_ids
        where group_id = p_group_id limit 1;
    if existing_id is not null then return existing_id; end if;
    update amazon_tracking_ids
        set group_id = p_group_id, assigned_at = now()
        where tracking_id = (
            select tracking_id from amazon_tracking_ids
            where user_id is null and group_id is null
            order by tracking_id limit 1 for update skip locked)
        returning tracking_id into claimed_id;
    return claimed_id;
end; $$;

-- Per-group earnings rollup (mirrors user_earnings).
create or replace view group_earnings as
select
    g.id as group_id,
    coalesce(sum(cm.user_cents), 0)                                        as lifetime_cents,
    coalesce(sum(cm.user_cents) filter (where cm.status = 'pending'), 0)   as pending_cents,
    coalesce(sum(cm.user_cents) filter (where cm.status = 'confirmed'), 0) as confirmed_cents,
    coalesce(sum(cm.user_cents) filter (where cm.status = 'paid'), 0)      as paid_cents
from groups g
left join commissions cm on cm.group_id = g.id
group by g.id;

alter table groups enable row level security;
alter table group_members enable row level security;

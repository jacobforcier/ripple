-- ── Amazon Tracking ID pool (B5b attribution) ───────────────────────────────
-- Amazon does NOT expose ascsubtag (sub-tag) reporting to regular associates —
-- it's gated behind top-publisher / Creators-API access. But per-Tracking-ID
-- reporting IS available to everyone, and an account may have up to 100
-- tracking ids. So we attribute by assigning each sharer their own tracking id
-- and reading the standard Tracking ID report back per id.
--
-- This pool is pre-seeded with the tracking ids created in Amazon Associates
-- Central. A user claims one the first time they create a link; an unclaimed
-- row has user_id IS NULL. When the pool is exhausted, link generation falls
-- back to the default shared tag (unattributed) — see lib/affiliate.js.

create table if not exists amazon_tracking_ids (
    tracking_id  text primary key,                 -- e.g. 'rippleu001-20'
    user_id      uuid unique references users(id) on delete set null,
    assigned_at  timestamptz
);

create index if not exists amazon_tracking_ids_user_idx
    on amazon_tracking_ids(user_id);

-- Atomically hand a user a tracking id. Returns the one they already hold (so
-- it's idempotent), otherwise claims the lowest unassigned id, otherwise NULL
-- (pool exhausted). FOR UPDATE SKIP LOCKED makes concurrent claims safe.
create or replace function claim_tracking_id(p_user_id uuid)
returns text
language plpgsql
as $$
declare
    existing_id text;
    claimed_id  text;
begin
    select tracking_id into existing_id
        from amazon_tracking_ids
        where user_id = p_user_id
        limit 1;
    if existing_id is not null then
        return existing_id;
    end if;

    update amazon_tracking_ids
        set user_id = p_user_id, assigned_at = now()
        where tracking_id = (
            select tracking_id
                from amazon_tracking_ids
                where user_id is null
                order by tracking_id
                limit 1
                for update skip locked
        )
        returning tracking_id into claimed_id;

    return claimed_id;  -- NULL when the pool is exhausted
end;
$$;

alter table amazon_tracking_ids enable row level security;

-- ── Rate limiting ────────────────────────────────────────────────────────────
-- A lightweight per-IP sliding-window store. The API is serverless (Vercel),
-- so an in-memory limiter would leak across Lambda instances — we keep the
-- counter in Postgres so every instance sees the same state.
--
-- Each row is one allowed request ("hit") for a (bucket, ip_hash) pair. The
-- limiter counts hits inside the window and rejects once the count hits the
-- max. `ip_hash` is the same salted SHA-256 used elsewhere — never a raw IP.
create table if not exists rate_limit_hits (
    id          bigint generated always as identity primary key,
    bucket      text        not null,   -- e.g. 'users:create', 'links:create'
    ip_hash     text        not null,
    created_at  timestamptz not null default now()
);

-- The hot path is: count rows for (bucket, ip_hash) newer than `since`.
create index if not exists rate_limit_hits_lookup
    on rate_limit_hits (bucket, ip_hash, created_at desc);

-- Optional housekeeping: a periodic job can prune old rows. The limiter also
-- prunes a (bucket, ip_hash)'s expired rows opportunistically on each check,
-- so active IPs stay small; this index supports a global sweep if added later.
create index if not exists rate_limit_hits_created_at
    on rate_limit_hits (created_at);

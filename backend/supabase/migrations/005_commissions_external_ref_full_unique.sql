-- ── Commissions: fix the external_ref unique index ──────────────────────────
-- Migration 004 created a PARTIAL unique index on (retailer, external_ref)
-- WHERE external_ref IS NOT NULL. That's correct for query-level uniqueness,
-- but PostgREST's INSERT ... ON CONFLICT (used by supabase-js's .upsert())
-- can't resolve a partial index without also passing the predicate — so
-- recordCommission() failed live with "no unique or exclusion constraint
-- matching the ON CONFLICT specification".
--
-- Replace with a FULL unique index. Postgres treats NULLs as distinct in
-- unique indexes by default (NULL != NULL), so multiple rows with NULL
-- external_ref are still permitted — manual / one-off inserts that don't
-- have a network ref aren't blocked.

drop index if exists commissions_external_ref_unique;

create unique index if not exists commissions_external_ref_unique
    on commissions (retailer, external_ref);

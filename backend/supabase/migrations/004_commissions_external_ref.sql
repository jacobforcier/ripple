-- ── Commissions: external_ref for idempotent ingestion ──────────────────────
-- When B5b ingests an Amazon Associates report (or any future affiliate-network
-- report), each row carries the network's own identifier for the commission.
-- We stash it on the commission row so re-importing the same report — or
-- importing overlapping date ranges — never creates duplicate rows.
--
-- Nullable on purpose: manual ad-hoc inserts (e.g. a corrective row entered by
-- hand) don't have a network ref. The unique constraint is partial so it only
-- applies when external_ref is set.

alter table commissions
    add column if not exists external_ref text;

create unique index if not exists commissions_external_ref_unique
    on commissions (retailer, external_ref)
    where external_ref is not null;

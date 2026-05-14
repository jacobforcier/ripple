-- ═════════════════════════════════════════════════════════════════════════════
--  Migration 001 — anonymous-first users
--
--  Ripple is anonymous-first: a user can share links and earn commissions
--  immediately, with no signup. An email is collected later, at payout time,
--  when the user creates a real account and claims their accumulated balance.
--
--  This makes `users.email` nullable. The UNIQUE constraint stays — Postgres
--  allows multiple NULLs in a unique column, so anonymous users don't collide.
--
--  Run this once in the Supabase SQL editor against an existing database.
--  (schema.sql already reflects this for fresh setups.)
-- ═════════════════════════════════════════════════════════════════════════════

alter table users alter column email drop not null;

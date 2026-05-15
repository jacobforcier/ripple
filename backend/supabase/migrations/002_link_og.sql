-- ═════════════════════════════════════════════════════════════════════════════
--  Migration 002 — cache product OG metadata on each link
--
--  When a Ripple link is shared, the receiving app (iMessage, X, Slack, …)
--  fetches the redirect page to build a preview card. We want that card to
--  show the PRODUCT, not a generic Ripple card — so we capture the source
--  URL's Open Graph metadata at link-creation time and serve it back from
--  the redirect page's OG tags.
--
--  Run this once in the Supabase SQL editor against the existing database.
--  schema.sql is updated too so fresh setups get the columns.
-- ═════════════════════════════════════════════════════════════════════════════

alter table links add column if not exists og_title       text;
alter table links add column if not exists og_image       text;
alter table links add column if not exists og_description text;

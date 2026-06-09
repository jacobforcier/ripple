// Commission recording. This is the "write side" of the earnings pipeline:
// ingestion (B5b), webhooks, and manual admin tooling all funnel through
// recordCommission() so the validation, idempotency, and user-id resolution
// live in exactly one place.
//
// Why upsert: the same Amazon Associates row will appear again every time we
// re-pull the report (and statuses transition pending → confirmed → paid as
// the sale clears Amazon's return window). Keying on (retailer, external_ref)
// lets re-ingestion be a no-op or a status update, never a duplicate row.

const VALID_STATUSES = new Set(['pending', 'confirmed', 'paid']);

/**
 * Record (or upsert) a single commission for a Ripple link.
 *
 * @param {object} db   supabase client
 * @param {object} input
 * @param {string} input.linkId       Ripple link short id (FK → links.id)
 * @param {string} input.retailer     'Amazon' | 'Target' | …  (free-form text;
 *                                    paired with externalRef for uniqueness)
 * @param {number} input.grossCents   total commission paid by the retailer
 * @param {number} input.userCents    user's cut (after platform margin)
 * @param {'pending'|'confirmed'|'paid'} [input.status='pending']
 * @param {string} input.occurredAt   ISO timestamp of the sale
 * @param {string|null} [input.externalRef]  the retailer's own id for this row;
 *                                    required for idempotent ingestion
 *
 * @returns {Promise<{id: string, status: string}>}
 */
export async function recordCommission(db, input) {
  const {
    linkId,
    userId,
    retailer,
    grossCents,
    userCents,
    status = 'pending',
    occurredAt,
    externalRef = null,
  } = input ?? {};

  // ── Validate ────────────────────────────────────────────────────────────
  // Attribution comes from EITHER a link (per-link ingestion, e.g. a future
  // ascsubtag feed) OR a user directly (per-tracking-id ingestion, where the
  // Amazon report is aggregated by tracking id → user, with no single link).
  if (!linkId && !userId) {
    throw new Error('either linkId or userId is required');
  }
  if (linkId && typeof linkId !== 'string') {
    throw new Error('linkId must be a string');
  }
  if (userId && typeof userId !== 'string') {
    throw new Error('userId must be a string');
  }
  if (!retailer || typeof retailer !== 'string') {
    throw new Error('retailer required (string)');
  }
  if (!Number.isInteger(grossCents) || grossCents < 0) {
    throw new Error('grossCents must be a non-negative integer');
  }
  if (!Number.isInteger(userCents) || userCents < 0) {
    throw new Error('userCents must be a non-negative integer');
  }
  if (userCents > grossCents) {
    throw new Error('userCents cannot exceed grossCents');
  }
  if (!VALID_STATUSES.has(status)) {
    throw new Error(`invalid status: ${status} (want pending|confirmed|paid)`);
  }
  if (!occurredAt || Number.isNaN(Date.parse(occurredAt))) {
    throw new Error('occurredAt must be an ISO timestamp');
  }
  if (externalRef != null && typeof externalRef !== 'string') {
    throw new Error('externalRef must be a string when provided');
  }

  // ── Resolve the owning user ─────────────────────────────────────────────
  let resolvedLinkId = null;
  let resolvedUserId = null;

  if (linkId) {
    // Per-link path: the commission inherits the user from the link's creator.
    const { data: link, error: linkErr } = await db
      .from('links')
      .select('id, user_id')
      .eq('id', linkId)
      .maybeSingle();
    if (linkErr) throw new Error(`link lookup failed: ${linkErr.message}`);
    if (!link) throw new Error(`link not found: ${linkId}`);
    resolvedLinkId = link.id;
    resolvedUserId = link.user_id;
  } else {
    // Per-user path: verify the user exists, attribute directly (link_id null).
    const { data: user, error: userErr } = await db
      .from('users')
      .select('id')
      .eq('id', userId)
      .maybeSingle();
    if (userErr) throw new Error(`user lookup failed: ${userErr.message}`);
    if (!user) throw new Error(`user not found: ${userId}`);
    resolvedUserId = user.id;
  }

  // ── Build the row ───────────────────────────────────────────────────────
  const row = {
    link_id: resolvedLinkId,
    user_id: resolvedUserId,
    retailer,
    gross_cents: grossCents,
    user_cents: userCents,
    status,
    occurred_at: occurredAt,
    confirmed_at: status === 'confirmed' ? new Date().toISOString() : null,
    external_ref: externalRef,
  };

  // ── Write ───────────────────────────────────────────────────────────────
  // If we have an external_ref, upsert on (retailer, external_ref) so the
  // same Amazon row can be safely re-ingested. Otherwise plain insert.
  if (externalRef) {
    const { data, error } = await db
      .from('commissions')
      .upsert(row, { onConflict: 'retailer,external_ref' })
      .select('id, status')
      .single();
    if (error) throw new Error(`commission upsert failed: ${error.message}`);
    return { id: data.id, status: data.status };
  }

  const { data, error } = await db
    .from('commissions')
    .insert(row)
    .select('id, status')
    .single();
  if (error) throw new Error(`commission insert failed: ${error.message}`);
  return { id: data.id, status: data.status };
}

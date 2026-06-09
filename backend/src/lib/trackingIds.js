// Amazon Tracking ID assignment (B5b attribution).
//
// Each sharer gets their own Amazon tracking id so the standard per-Tracking-ID
// report can attribute their sales (ascsubtag-level reporting isn't available
// to regular associates). The atomic claim lives in the claim_tracking_id
// Postgres function (migration 008); this is the thin wrapper.

/**
 * Return the user's tracking id, claiming one from the pool on first use.
 * Returns null if the pool is exhausted (caller falls back to the shared tag)
 * or if anything goes wrong — attribution is best-effort and must never block
 * link creation.
 *
 * @param {object} db        supabase client
 * @param {string} userId
 * @returns {Promise<string|null>}
 */
export async function getOrAssignTrackingId(db, userId) {
  if (!userId) return null;
  try {
    const { data, error } = await db.rpc('claim_tracking_id', { p_user_id: userId });
    if (error) {
      console.error('[trackingIds] claim failed, falling back to shared tag:', error.message);
      return null;
    }
    return data || null; // null = pool exhausted
  } catch (err) {
    console.error('[trackingIds] claim threw, falling back to shared tag:', err);
    return null;
  }
}

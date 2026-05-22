import { hashIp } from './hashIp.js';

/**
 * Per-IP sliding-window rate limiter, backed by the `rate_limit_hits` table.
 *
 * Why Postgres and not in-memory: the API runs as Vercel serverless functions,
 * so an in-process counter would reset on cold starts and never be shared
 * across concurrent instances — useless as a limit. The DB is the one piece of
 * state every instance agrees on.
 *
 * Fail-OPEN by design: this guards a low-severity abuse vector (mass-creating
 * anonymous users). If the limiter itself can't run — no IP salt, no client
 * IP, or a DB hiccup — we let the request through rather than block legitimate
 * users. Security here is "raise the bar," not "lock the door."
 *
 * @param {object} db   supabase client
 * @param {object} opts
 * @param {string} opts.bucket     namespace, e.g. 'users:create'
 * @param {number} opts.max        max requests allowed per window per IP
 * @param {number} opts.windowSec  window length in seconds
 */
export function rateLimit(db, { bucket, max, windowSec }) {
  return async function rateLimitMiddleware(req, res, next) {
    const ipHash = hashIp(req);
    if (!ipHash) return next(); // can't identify the client → fail open

    const sinceIso = new Date(Date.now() - windowSec * 1000).toISOString();

    try {
      const { count, error } = await db
        .from('rate_limit_hits')
        .select('id', { count: 'exact', head: true })
        .eq('bucket', bucket)
        .eq('ip_hash', ipHash)
        .gte('created_at', sinceIso);

      if (error) {
        console.error(`[rateLimit:${bucket}] count failed, failing open:`, error);
        return next();
      }

      if ((count ?? 0) >= max) {
        res.set('Retry-After', String(windowSec));
        return res.status(429).json({
          error: 'Too many requests. Please slow down and try again later.',
        });
      }

      // Record this allowed request. Best-effort — don't block on a write error.
      const { error: insertError } = await db
        .from('rate_limit_hits')
        .insert({ bucket, ip_hash: ipHash });
      if (insertError) {
        console.error(`[rateLimit:${bucket}] hit insert failed:`, insertError);
      }

      // Opportunistic cleanup: drop this (bucket, ip) pair's expired rows so
      // the table stays small for active clients. Fire-and-forget.
      db.from('rate_limit_hits')
        .delete()
        .eq('bucket', bucket)
        .eq('ip_hash', ipHash)
        .lt('created_at', sinceIso)
        .then(({ error: pruneError }) => {
          if (pruneError) console.error(`[rateLimit:${bucket}] prune failed:`, pruneError);
        })
        .catch(() => {});

      return next();
    } catch (err) {
      console.error(`[rateLimit:${bucket}] unexpected error, failing open:`, err);
      return next();
    }
  };
}

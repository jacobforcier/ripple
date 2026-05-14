import { createHash } from 'node:crypto';

const salt = process.env.IP_HASH_SALT || '';

/**
 * Derives a stable, salted hash of the request's client IP.
 *
 * We never store raw IPs. The hash is only good for coarse signals —
 * de-duplicating rapid repeat clicks and spotting obvious fraud — not
 * for identifying anyone. Returns null if no salt is configured or no
 * IP can be determined.
 */
export function hashIp(req) {
  if (!salt) return null;

  const fwd = req.headers['x-forwarded-for'];
  const ip =
    (typeof fwd === 'string' && fwd.split(',')[0].trim()) ||
    req.socket?.remoteAddress ||
    '';

  if (!ip) return null;
  return createHash('sha256').update(salt + ip).digest('hex');
}

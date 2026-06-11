import 'dotenv/config';
import express from 'express';
import cors from 'cors';

import { db } from './db.js';
import { makeLinksRouter } from './routes/links.js';
import { makeUsersRouter } from './routes/users.js';
import { makeTrendingRouter } from './routes/trending.js';
import { makeAdminRouter } from './routes/admin.js';
import { makeConnectRouter } from './routes/connect.js';
import { makeStripeWebhookRouter } from './routes/stripeWebhook.js';
import { makeGroupsRouter } from './routes/groups.js';

// Builds and configures the Express app. Exported (not started) so it can be
// used both by the local dev server (src/index.js) and the Vercel serverless
// entry point (api/index.js). An Express app is itself a valid (req, res)
// handler, which is what Vercel's Node runtime expects.
const app = express();

// ── Middleware ───────────────────────────────────────────────────────────────
const allowedOrigins = (process.env.CORS_ORIGINS || '')
  .split(',')
  .map((o) => o.trim())
  .filter(Boolean);

app.use(
  cors({
    origin: (origin, cb) => {
      // Allow, in order:
      //  - no Origin header (curl, native iOS/macOS apps, server-to-server)
      //  - any origin when no allow-list is configured
      //  - explicitly allow-listed web origins (the website)
      //  - the Chrome extension. Its origin is chrome-extension://<id>, and the
      //    id differs between the unpacked dev build (random per machine) and
      //    the published Web Store build, so we allow the scheme rather than a
      //    fixed id. Safe here: this API is public + unauthenticated (and rate-
      //    limited), so CORS is not its security boundary — anyone can already
      //    call it with no Origin via curl.
      if (
        !origin ||
        allowedOrigins.length === 0 ||
        allowedOrigins.includes(origin) ||
        origin.startsWith('chrome-extension://')
      ) {
        return cb(null, true);
      }
      return cb(new Error(`Origin ${origin} not allowed by CORS`));
    },
  })
);
// Stripe webhook is mounted BEFORE express.json(): signature verification needs
// the raw, unparsed request body. The router applies express.raw() itself.
app.use('/v1/stripe', makeStripeWebhookRouter(db));

app.use(express.json({ limit: '16kb' }));

// Trust the proxy (Vercel) so client IPs resolve correctly.
app.set('trust proxy', true);

// ── Health check ─────────────────────────────────────────────────────────────
app.get('/health', (_req, res) => {
  res.json({ ok: true, service: 'ripple-backend', time: new Date().toISOString() });
});

// ── Routes ───────────────────────────────────────────────────────────────────
app.use('/v1/links', makeLinksRouter(db));
app.use('/v1/users', makeUsersRouter(db));
// Connect onboarding shares the /v1/users base (POST /:id/claim, /:id/connect/*).
// Mounted as a second router on the same path; Express runs both layers.
app.use('/v1/users', makeConnectRouter(db));
app.use('/v1/trending', makeTrendingRouter(db));
app.use('/v1/admin', makeAdminRouter(db));
app.use('/v1/groups', makeGroupsRouter(db));

// ── 404 + error handling ─────────────────────────────────────────────────────
app.use((_req, res) => {
  res.status(404).json({ error: 'Not found' });
});

// eslint-disable-next-line no-unused-vars -- Express needs the 4-arg signature
app.use((err, _req, res, _next) => {
  console.error('[unhandled]', err);
  res.status(500).json({ error: 'Internal server error' });
});

export default app;

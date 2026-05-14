import 'dotenv/config';
import express from 'express';
import cors from 'cors';

import { linksRouter } from './routes/links.js';
import { usersRouter } from './routes/users.js';
import { trendingRouter } from './routes/trending.js';

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
      // Allow same-origin / curl / native apps (no Origin header) and any
      // explicitly allow-listed web origin.
      if (!origin || allowedOrigins.length === 0 || allowedOrigins.includes(origin)) {
        return cb(null, true);
      }
      return cb(new Error(`Origin ${origin} not allowed by CORS`));
    },
  })
);
app.use(express.json({ limit: '16kb' }));

// Trust the proxy (Vercel) so client IPs resolve correctly.
app.set('trust proxy', true);

// ── Health check ─────────────────────────────────────────────────────────────
app.get('/health', (_req, res) => {
  res.json({ ok: true, service: 'ripple-backend', time: new Date().toISOString() });
});

// ── Routes ───────────────────────────────────────────────────────────────────
app.use('/v1/links', linksRouter);
app.use('/v1/users', usersRouter);
app.use('/v1/trending', trendingRouter);

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

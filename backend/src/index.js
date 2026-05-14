import express from 'express';
import cors from 'cors';
import 'dotenv/config';

import { linksRouter } from './routes/links.js';
import { usersRouter } from './routes/users.js';

const app = express();
const PORT = process.env.PORT || 8787;

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

// Trust the proxy (Vercel/Railway/Render) so client IPs resolve correctly.
app.set('trust proxy', true);

// ── Health check ─────────────────────────────────────────────────────────────
app.get('/health', (_req, res) => {
  res.json({ ok: true, service: 'ripple-backend', time: new Date().toISOString() });
});

// ── Routes ───────────────────────────────────────────────────────────────────
app.use('/v1/links', linksRouter);
app.use('/v1/users', usersRouter);

// ── 404 + error handling ─────────────────────────────────────────────────────
app.use((_req, res) => {
  res.status(404).json({ error: 'Not found' });
});

// eslint-disable-next-line no-unused-vars -- Express needs the 4-arg signature
app.use((err, _req, res, _next) => {
  console.error('[unhandled]', err);
  res.status(500).json({ error: 'Internal server error' });
});

app.listen(PORT, () => {
  console.log(`Ripple backend listening on :${PORT}`);
});

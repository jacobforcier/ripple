# Ripple Backend

The API behind Ripple — link creation, resolution, click tracking, and earnings.
Node + Express + Supabase (Postgres).

## Status

Fully functional **except** affiliate link generation, which is stubbed in
`src/lib/affiliate.js` (passthrough mode) until the Sovrn Commerce application
is approved. The create → resolve → redirect → click pipeline works end to end
today; only real commission attribution is missing.

## Setup

1. **Create a Supabase project** at supabase.com.

2. **Provision the database** — open the Supabase SQL editor and run
   `supabase/schema.sql`.

3. **Configure environment** — copy the example file and fill it in:
   ```sh
   cp .env.example .env
   ```
   - `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` — from Supabase → Settings → API
   - `IP_HASH_SALT` — generate with `openssl rand -hex 32`
   - `SOVRN_API_KEY` — leave blank for now

4. **Install and run:**
   ```sh
   npm install
   npm run dev
   ```
   The API listens on `http://localhost:8787`.

## Tests

```sh
npm test
```

Uses Node's built-in test runner (no extra dependencies). Covers the pure
logic — retailer detection, short-id generation, IP hashing. Route handlers
need a Supabase test instance or a DI refactor to cover; not done yet.

## Deployment (Vercel)

The app is structured to run both as a local server and as a Vercel
serverless function:

- `src/app.js` — builds and exports the configured Express app
- `src/index.js` — local dev server (`npm run dev` / `npm start`)
- `api/index.js` — Vercel serverless entry (exports the app as the handler)
- `vercel.json` — rewrites every path to the function

To deploy:

1. From the `backend/` directory: `npx vercel` (first run links/creates the
   project), then `npx vercel --prod`.
2. In the Vercel project's **Settings → Environment Variables**, set
   `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `IP_HASH_SALT`, and
   `CORS_ORIGINS` — the same values as the local `.env`.
3. Add the custom domain `api.sharewithripple.com` in the Vercel project,
   then point a `CNAME` for `api` at Vercel in the DNS host.

## Endpoints

| Method | Path                       | Purpose                                              |
|--------|----------------------------|------------------------------------------------------|
| GET    | `/health`                  | Liveness check                                       |
| POST   | `/v1/users`                | Create an anonymous user (first run) → `{ id }`      |
| POST   | `/v1/links`                | Create a Ripple link (pass `user_id` to attribute it) |
| GET    | `/v1/links?user_id=`       | List a user's links with stats (dashboard / app)     |
| GET    | `/v1/links/:id`            | Resolve a link + record a click (redirect page)      |
| GET    | `/v1/users/:id/earnings`   | Earnings summary (dashboard / app)                   |
| GET    | `/v1/trending`             | Top retailers shared in the last 7 days (Trending tab) |

### Migrations

`supabase/schema.sql` is the full schema for a fresh setup. Incremental
changes to an already-provisioned database live in `supabase/migrations/`
— run each new file once in the Supabase SQL editor.

### Examples

```sh
# Create a link
curl -X POST http://localhost:8787/v1/links \
  -H 'Content-Type: application/json' \
  -d '{"source_url":"https://www.amazon.com/dp/B0XXXXXXX"}'

# Resolve it (also logs a click)
curl http://localhost:8787/v1/links/k7m2xqp
```

## Going live with Sovrn

When the Sovrn Commerce application is approved:

1. Put the key in `.env` as `SOVRN_API_KEY`.
2. Replace the body of `generateAffiliateUrl()` in `src/lib/affiliate.js` with a
   real Sovrn API call (a worked example is in the file's header comment).
3. Build a webhook/poller that ingests confirmed sales from Sovrn into the
   `commissions` table — that's what lights up the earnings views.

## Client swap points

Once this API is deployed (e.g. to `api.sharewithripple.com`), point the demo
link generators at it:

- `extension/popup.js` — `generateRippleLink()` → `POST /v1/links`
- `extension/content.js` — `generateRippleLink()` → `POST /v1/links`
- `Ripple/Ripple Share/ShareViewController.swift` — `generateRippleLink()` → `POST /v1/links`
- `s.html` — `resolveLink()` → `GET /v1/links/:id`

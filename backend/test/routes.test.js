import { test } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import request from 'supertest';

import { makeLinksRouter } from '../src/routes/links.js';
import { makeUsersRouter } from '../src/routes/users.js';
import { makeTrendingRouter } from '../src/routes/trending.js';
import { makeAdminRouter } from '../src/routes/admin.js';
import { recordCommission } from '../src/lib/commissions.js';
import { makeConnectRouter } from '../src/routes/connect.js';
import { handleEvent } from '../src/routes/stripeWebhook.js';

// ── Minimal chainable mock of the supabase-js query builder ──────────────────
// Chain methods return the builder; terminal methods (and awaiting the builder
// itself) resolve to the configured { data, error } result.
function makeBuilder(result) {
  const builder = {
    insert: () => builder,
    upsert: () => builder,
    update: () => builder,
    select: () => builder,
    delete: () => builder,
    eq: () => builder,
    order: () => builder,
    gte: () => builder,
    lt: () => builder,
    not: () => builder,
    single: () => Promise.resolve(result),
    maybeSingle: () => Promise.resolve(result),
    then: (resolve, reject) => Promise.resolve(result).then(resolve, reject),
  };
  return builder;
}

// resultsByTable maps a table name to the { data, error } its queries resolve to.
function mockDb(resultsByTable = {}) {
  return {
    from: (table) => makeBuilder(resultsByTable[table] ?? { data: null, error: null }),
  };
}

function appWith(path, router) {
  const app = express();
  app.use(express.json());
  app.use(path, router);
  return app;
}

// No-op OG fetcher for tests — avoids real network calls.
const noopOG = async () => null;
const linksApp = (db, opts = {}) =>
  appWith('/v1/links', makeLinksRouter(db, { fetchOG: noopOG, ...opts }));

// ── POST /v1/links ───────────────────────────────────────────────────────────
test('POST /v1/links: 400 when source_url is missing', async () => {
  const app = linksApp(mockDb());
  const res = await request(app).post('/v1/links').send({});
  assert.equal(res.status, 400);
});

test('POST /v1/links: 400 when source_url is not a valid URL', async () => {
  const app = linksApp(mockDb());
  const res = await request(app).post('/v1/links').send({ source_url: 'not a url' });
  assert.equal(res.status, 400);
});

test('POST /v1/links: 400 for a non-http(s) URL', async () => {
  const app = linksApp(mockDb());
  const res = await request(app).post('/v1/links').send({ source_url: 'ftp://x.com/f' });
  assert.equal(res.status, 400);
});

test('POST /v1/links: 201 with a ripple_url + detected retailer on success', async () => {
  const db = mockDb({ links: { error: null } });
  const app = linksApp(db);
  const res = await request(app)
    .post('/v1/links')
    .send({ source_url: 'https://www.amazon.com/dp/B0XYZ' });
  assert.equal(res.status, 201);
  assert.match(res.body.ripple_url, /^https:\/\/sharewithripple\.com\/s\/.+/);
  assert.equal(res.body.retailer, 'Amazon');
});

test('POST /v1/links: 500 when the insert fails with a non-collision error', async () => {
  const db = mockDb({ links: { error: { code: 'XXXXX', message: 'boom' } } });
  const app = linksApp(db);
  const res = await request(app)
    .post('/v1/links')
    .send({ source_url: 'https://www.amazon.com/dp/B0XYZ' });
  assert.equal(res.status, 500);
});

// ── GET /v1/links ────────────────────────────────────────────────────────────
test('GET /v1/links: 400 without a user_id', async () => {
  const app = linksApp(mockDb());
  const res = await request(app).get('/v1/links');
  assert.equal(res.status, 400);
});

test('GET /v1/links: 200 with the user link list', async () => {
  const rows = [{ id: 'abc', click_count: 2, earned_cents: 0 }];
  const db = mockDb({ link_stats: { data: rows, error: null } });
  const app = linksApp(db);
  const res = await request(app).get('/v1/links?user_id=u1');
  assert.equal(res.status, 200);
  assert.deepEqual(res.body.links, rows);
});

// ── GET /v1/links/:id ────────────────────────────────────────────────────────
test('GET /v1/links/:id: 404 when the link is not found', async () => {
  const db = mockDb({ links: { data: null, error: null } });
  const app = linksApp(db);
  const res = await request(app).get('/v1/links/missing');
  assert.equal(res.status, 404);
});

test('GET /v1/links/:id: 200 resolves to the source URL + logs a click', async () => {
  const db = mockDb({
    links: {
      data: { id: 'abc', source_url: 'https://x.com/p', affiliate_url: null, retailer: 'X', users: null },
      error: null,
    },
    clicks: { error: null },
  });
  const app = linksApp(db);
  const res = await request(app).get('/v1/links/abc');
  assert.equal(res.status, 200);
  assert.equal(res.body.url, 'https://x.com/p');
  assert.equal(res.body.retailer, 'X');
  assert.equal(res.body.sharer, null);
});

test('GET /v1/links/:id: prefers affiliate_url and surfaces the sharer name', async () => {
  const db = mockDb({
    links: {
      data: {
        id: 'abc',
        source_url: 'https://x.com/p',
        affiliate_url: 'https://aff.x.com/p',
        retailer: 'X',
        users: { display_name: 'Jacob' },
      },
      error: null,
    },
    clicks: { error: null },
  });
  const app = linksApp(db);
  const res = await request(app).get('/v1/links/abc');
  assert.equal(res.body.url, 'https://aff.x.com/p');
  assert.equal(res.body.sharer, 'Jacob');
});

// ── GET /v1/links/:id/preview ────────────────────────────────────────────────
test('GET /v1/links/:id/preview: returns OG metadata without logging a click', async () => {
  const db = mockDb({
    links: {
      data: {
        id: 'abc',
        source_url: 'https://x.com/p',
        retailer: 'X',
        og_title: 'Cool Water Bottle',
        og_image: 'https://x.com/bottle.jpg',
        og_description: 'A bottle that is cool.',
      },
      error: null,
    },
  });
  const app = linksApp(db);
  const res = await request(app).get('/v1/links/abc/preview');
  assert.equal(res.status, 200);
  assert.equal(res.body.og_title, 'Cool Water Bottle');
  assert.equal(res.body.og_image, 'https://x.com/bottle.jpg');
  assert.equal(res.body.retailer, 'X');
});

test('GET /v1/links/:id/preview: 404 when the link is missing', async () => {
  const db = mockDb({ links: { data: null, error: null } });
  const app = linksApp(db);
  const res = await request(app).get('/v1/links/missing/preview');
  assert.equal(res.status, 404);
});

// ── OG capture on link creation ──────────────────────────────────────────────
test('POST /v1/links: scrapes OG from the source URL on creation', async () => {
  let scrapedURL = null;
  const fakeOG = async (url) => {
    scrapedURL = url;
    return { title: 'A Product', image: 'https://x.com/p.jpg', description: 'Nice.' };
  };
  const db = mockDb({ links: { error: null } });
  const app = appWith(
    '/v1/links',
    makeLinksRouter(db, { fetchOG: fakeOG })
  );
  const source = 'https://www.amazon.com/dp/B0XYZ';
  const res = await request(app).post('/v1/links').send({ source_url: source });
  assert.equal(res.status, 201);
  assert.equal(scrapedURL, source);
});

// ── POST /v1/users ───────────────────────────────────────────────────────────
test('POST /v1/users: 201 with the new anonymous user id', async () => {
  const db = mockDb({ users: { data: { id: 'user-123' }, error: null } });
  const app = appWith('/v1/users', makeUsersRouter(db));
  const res = await request(app).post('/v1/users');
  assert.equal(res.status, 201);
  assert.equal(res.body.id, 'user-123');
});

test('POST /v1/users: 500 when the insert fails', async () => {
  const db = mockDb({ users: { data: null, error: { message: 'boom' } } });
  const app = appWith('/v1/users', makeUsersRouter(db));
  const res = await request(app).post('/v1/users');
  assert.equal(res.status, 500);
});

// ── Rate limiting (POST /v1/users) ───────────────────────────────────────────
// The limiter only engages when an IP can be hashed, i.e. IP_HASH_SALT is set
// and a client IP is present. We set the salt + an X-Forwarded-For just for
// these tests and restore the env afterward.
function withSalt(fn) {
  return async () => {
    const prev = process.env.IP_HASH_SALT;
    process.env.IP_HASH_SALT = 'test-salt';
    try {
      await fn();
    } finally {
      if (prev === undefined) delete process.env.IP_HASH_SALT;
      else process.env.IP_HASH_SALT = prev;
    }
  };
}

test('POST /v1/users: 429 when the IP is over the rate limit', withSalt(async () => {
  // rate_limit_hits count comes back at/over the default max (20) → blocked.
  const db = mockDb({
    rate_limit_hits: { data: null, error: null, count: 25 },
    users: { data: { id: 'should-not-be-created' }, error: null },
  });
  const app = appWith('/v1/users', makeUsersRouter(db));
  const res = await request(app).post('/v1/users').set('X-Forwarded-For', '203.0.113.7');
  assert.equal(res.status, 429);
  assert.match(res.body.error, /too many/i);
  assert.ok(res.headers['retry-after'], 'sets a Retry-After header');
}));

test('POST /v1/users: allows the request when under the rate limit', withSalt(async () => {
  const db = mockDb({
    rate_limit_hits: { data: null, error: null, count: 3 },
    users: { data: { id: 'user-ok' }, error: null },
  });
  const app = appWith('/v1/users', makeUsersRouter(db));
  const res = await request(app).post('/v1/users').set('X-Forwarded-For', '203.0.113.7');
  assert.equal(res.status, 201);
  assert.equal(res.body.id, 'user-ok');
}));

test('POST /v1/users: fails OPEN (allows) when the limiter query errors', withSalt(async () => {
  const db = mockDb({
    rate_limit_hits: { data: null, error: { message: 'db down' }, count: null },
    users: { data: { id: 'user-failopen' }, error: null },
  });
  const app = appWith('/v1/users', makeUsersRouter(db));
  const res = await request(app).post('/v1/users').set('X-Forwarded-For', '203.0.113.7');
  assert.equal(res.status, 201, 'limiter errors should not block legitimate users');
}));

// ── GET /v1/users/:id/earnings ───────────────────────────────────────────────
test('GET /v1/users/:id/earnings: returns the summary when one exists', async () => {
  const summary = {
    user_id: 'u1', lifetime_cents: 500, pending_cents: 200,
    confirmed_cents: 300, paid_cents: 0,
  };
  const db = mockDb({ user_earnings: { data: summary, error: null } });
  const app = appWith('/v1/users', makeUsersRouter(db));
  const res = await request(app).get('/v1/users/u1/earnings');
  assert.equal(res.status, 200);
  assert.deepEqual(res.body, summary);
});

test('GET /v1/users/:id/earnings: returns a zeroed summary when none exists', async () => {
  const db = mockDb({ user_earnings: { data: null, error: null } });
  const app = appWith('/v1/users', makeUsersRouter(db));
  const res = await request(app).get('/v1/users/u1/earnings');
  assert.equal(res.status, 200);
  assert.equal(res.body.user_id, 'u1');
  assert.equal(res.body.lifetime_cents, 0);
});

// ── GET /v1/trending ─────────────────────────────────────────────────────────
test('GET /v1/trending: aggregates and ranks retailers by share count', async () => {
  const links = [
    { retailer: 'Amazon' }, { retailer: 'Amazon' }, { retailer: 'Amazon' },
    { retailer: 'Target' }, { retailer: 'Target' },
    { retailer: 'REI' },
  ];
  const db = mockDb({ links: { data: links, error: null } });
  const app = appWith('/v1/trending', makeTrendingRouter(db));
  const res = await request(app).get('/v1/trending');
  assert.equal(res.status, 200);
  assert.equal(res.body.period, 'week');
  assert.deepEqual(res.body.trending, [
    { rank: 1, retailer: 'Amazon', share_count: 3 },
    { rank: 2, retailer: 'Target', share_count: 2 },
    { rank: 3, retailer: 'REI', share_count: 1 },
  ]);
});

test('GET /v1/trending: 500 when the query fails', async () => {
  const db = mockDb({ links: { data: null, error: { message: 'boom' } } });
  const app = appWith('/v1/trending', makeTrendingRouter(db));
  const res = await request(app).get('/v1/trending');
  assert.equal(res.status, 500);
});

// ── B5a: recordCommission lib (unit) ─────────────────────────────────────────
// The lib resolves user_id from the link, validates the input, and writes to
// the commissions table. The mock returns whatever result we configure for
// each table, so we can simulate "link exists" / "link missing" / write errors.

const ISO = '2026-05-20T12:00:00Z';
const VALID = {
  linkId: 'lnk1',
  retailer: 'Amazon',
  grossCents: 1000,
  userCents: 500,
  status: 'pending',
  occurredAt: ISO,
};

test('recordCommission: inserts when externalRef is absent', async () => {
  const db = mockDb({
    links: { data: { id: 'lnk1', user_id: 'u1' }, error: null },
    commissions: { data: { id: 'c1', status: 'pending' }, error: null },
  });
  const out = await recordCommission(db, VALID);
  assert.equal(out.id, 'c1');
  assert.equal(out.status, 'pending');
});

test('recordCommission: upserts when externalRef is provided (idempotent path)', async () => {
  const db = mockDb({
    links: { data: { id: 'lnk1', user_id: 'u1' }, error: null },
    commissions: { data: { id: 'c2', status: 'confirmed' }, error: null },
  });
  const out = await recordCommission(db, {
    ...VALID,
    status: 'confirmed',
    externalRef: 'AMZN-ORDER-123',
  });
  assert.equal(out.id, 'c2');
  assert.equal(out.status, 'confirmed');
});

test('recordCommission: throws when the link does not exist', async () => {
  const db = mockDb({ links: { data: null, error: null } });
  await assert.rejects(
    () => recordCommission(db, VALID),
    /link not found/i
  );
});

test('recordCommission: rejects invalid input (userCents > grossCents)', async () => {
  const db = mockDb({ links: { data: { id: 'lnk1', user_id: 'u1' }, error: null } });
  await assert.rejects(
    () => recordCommission(db, { ...VALID, grossCents: 100, userCents: 500 }),
    /userCents cannot exceed grossCents/i
  );
});

test('recordCommission: rejects invalid status', async () => {
  const db = mockDb({ links: { data: { id: 'lnk1', user_id: 'u1' }, error: null } });
  await assert.rejects(
    () => recordCommission(db, { ...VALID, status: 'WHATEVER' }),
    /invalid status/i
  );
});

test('recordCommission: rejects bad occurredAt', async () => {
  const db = mockDb({ links: { data: { id: 'lnk1', user_id: 'u1' }, error: null } });
  await assert.rejects(
    () => recordCommission(db, { ...VALID, occurredAt: 'not a date' }),
    /occurredAt/i
  );
});

// ── B5a: POST /v1/admin/commissions ──────────────────────────────────────────
// Shared-secret auth via X-Admin-Key. We isolate process.env per-test so the
// auth-disabled path doesn't leak into others.

function withAdminKey(key, fn) {
  return async () => {
    const prev = process.env.ADMIN_API_KEY;
    if (key === null) delete process.env.ADMIN_API_KEY;
    else process.env.ADMIN_API_KEY = key;
    try {
      await fn();
    } finally {
      if (prev === undefined) delete process.env.ADMIN_API_KEY;
      else process.env.ADMIN_API_KEY = prev;
    }
  };
}

const adminApp = (db) => appWith('/v1/admin', makeAdminRouter(db));

test('POST /v1/admin/commissions: 503 when ADMIN_API_KEY is not configured',
  withAdminKey(null, async () => {
    const res = await request(adminApp(mockDb())).post('/v1/admin/commissions');
    assert.equal(res.status, 503);
  }));

test('POST /v1/admin/commissions: 401 with a wrong key',
  withAdminKey('correct-key', async () => {
    const res = await request(adminApp(mockDb()))
      .post('/v1/admin/commissions')
      .set('X-Admin-Key', 'nope-not-it');
    assert.equal(res.status, 401);
  }));

test('POST /v1/admin/commissions: 401 with no key header',
  withAdminKey('correct-key', async () => {
    const res = await request(adminApp(mockDb())).post('/v1/admin/commissions');
    assert.equal(res.status, 401);
  }));

test('POST /v1/admin/commissions: 400 with empty / missing body',
  withAdminKey('correct-key', async () => {
    const res = await request(adminApp(mockDb()))
      .post('/v1/admin/commissions')
      .set('X-Admin-Key', 'correct-key')
      .send({});
    assert.equal(res.status, 400);
  }));

test('POST /v1/admin/commissions: 201 records a valid batch',
  withAdminKey('correct-key', async () => {
    const db = mockDb({
      links: { data: { id: 'lnk1', user_id: 'u1' }, error: null },
      commissions: { data: { id: 'c1', status: 'pending' }, error: null },
    });
    const res = await request(adminApp(db))
      .post('/v1/admin/commissions')
      .set('X-Admin-Key', 'correct-key')
      .send({ commissions: [VALID, { ...VALID, externalRef: 'ext-1' }] });
    assert.equal(res.status, 201);
    assert.equal(res.body.recorded, 2);
    assert.equal(res.body.results.length, 2);
    assert.ok(res.body.results.every((r) => r.id === 'c1'));
  }));

test('POST /v1/admin/commissions: per-row error when a row references a missing link',
  withAdminKey('correct-key', async () => {
    // No 'links' result → maybeSingle returns null → recordCommission throws.
    const db = mockDb({
      commissions: { data: { id: 'c1', status: 'pending' }, error: null },
    });
    const res = await request(adminApp(db))
      .post('/v1/admin/commissions')
      .set('X-Admin-Key', 'correct-key')
      .send({ commissions: [VALID] });
    assert.equal(res.status, 201);
    assert.equal(res.body.recorded, 0);
    assert.match(res.body.results[0].error, /link not found/i);
  }));

// ── B5c: Stripe Connect onboarding (POST /v1/users/:id/claim, /connect/*) ─────
// The connect router takes an injected Stripe mock so we never hit Stripe.

function stripeMock(overrides = {}) {
  return {
    accounts: {
      create: overrides.accountsCreate || (async () => ({ id: 'acct_test123' })),
      retrieve: overrides.accountsRetrieve ||
        (async () => ({ payouts_enabled: true, details_submitted: true })),
    },
    accountLinks: {
      create: overrides.accountLinksCreate ||
        (async () => ({ url: 'https://connect.stripe.com/setup/test' })),
    },
  };
}

const connectApp = (db, stripe) =>
  appWith('/v1/users', makeConnectRouter(db, { stripe }));

test('POST /:id/claim: 400 on an invalid email', async () => {
  const res = await request(connectApp(mockDb(), stripeMock()))
    .post('/v1/users/u1/claim')
    .send({ email: 'not-an-email' });
  assert.equal(res.status, 400);
});

test('POST /:id/claim: 404 when the user does not exist', async () => {
  const db = mockDb({ users: { data: null, error: null } });
  const res = await request(connectApp(db, stripeMock()))
    .post('/v1/users/u1/claim')
    .send({ email: 'jake@example.com' });
  assert.equal(res.status, 404);
});

test('POST /:id/claim: 200 attaches the email', async () => {
  const db = mockDb({ users: { data: { id: 'u1', email: null }, error: null } });
  const res = await request(connectApp(db, stripeMock()))
    .post('/v1/users/u1/claim')
    .send({ email: 'Jake@Example.com' });
  assert.equal(res.status, 200);
  assert.equal(res.body.email, 'jake@example.com'); // normalized
});

test('POST /:id/connect/start: 400 when the user has no email yet', async () => {
  const db = mockDb({ users: { data: { id: 'u1', email: null, stripe_connect_id: null }, error: null } });
  const res = await request(connectApp(db, stripeMock()))
    .post('/v1/users/u1/connect/start');
  assert.equal(res.status, 400);
  assert.match(res.body.error, /claim an email/i);
});

test('POST /:id/connect/start: 200 creates an Express account + returns an onboarding URL', async () => {
  const db = mockDb({ users: { data: { id: 'u1', email: 'jake@example.com', stripe_connect_id: null }, error: null } });
  const res = await request(connectApp(db, stripeMock()))
    .post('/v1/users/u1/connect/start');
  assert.equal(res.status, 200);
  assert.equal(res.body.account, 'acct_test123');
  assert.match(res.body.url, /connect\.stripe\.com/);
});

test('POST /:id/connect/start: creates the account as an individual recipient (light onboarding)', async () => {
  let createArgs = null;
  const stripe = stripeMock({ accountsCreate: async (args) => { createArgs = args; return { id: 'acct_test123' }; } });
  const db = mockDb({ users: { data: { id: 'u1', email: 'jake@example.com', stripe_connect_id: null }, error: null } });
  const res = await request(connectApp(db, stripe)).post('/v1/users/u1/connect/start');
  assert.equal(res.status, 200);
  // These three keep onboarding to "identity + bank", not the merchant flow.
  assert.equal(createArgs.business_type, 'individual');
  assert.equal(createArgs.tos_acceptance?.service_agreement, 'recipient');
  assert.ok(createArgs.business_profile?.url, 'business_profile prefilled so the user is not asked for a website');
});

test('POST /:id/connect/start: reuses an existing account (no second create)', async () => {
  let created = 0;
  const stripe = stripeMock({ accountsCreate: async () => { created++; return { id: 'acct_new' }; } });
  const db = mockDb({ users: { data: { id: 'u1', email: 'jake@example.com', stripe_connect_id: 'acct_existing' }, error: null } });
  const res = await request(connectApp(db, stripe))
    .post('/v1/users/u1/connect/start');
  assert.equal(res.status, 200);
  assert.equal(res.body.account, 'acct_existing');
  assert.equal(created, 0, 'should not create a new account when one exists');
});

test('GET /:id/connect/status: not connected when no account exists', async () => {
  const db = mockDb({ users: { data: { id: 'u1', stripe_connect_id: null, connect_onboarded_at: null }, error: null } });
  const res = await request(connectApp(db, stripeMock()))
    .get('/v1/users/u1/connect/status');
  assert.equal(res.status, 200);
  assert.equal(res.body.connected, false);
  assert.equal(res.body.payouts_enabled, false);
});

test('GET /:id/connect/status: reports payouts_enabled from Stripe when connected', async () => {
  const db = mockDb({ users: { data: { id: 'u1', stripe_connect_id: 'acct_1', connect_onboarded_at: null }, error: null } });
  const res = await request(connectApp(db, stripeMock()))
    .get('/v1/users/u1/connect/status');
  assert.equal(res.status, 200);
  assert.equal(res.body.connected, true);
  assert.equal(res.body.payouts_enabled, true);
});

// ── B5c: webhook handleEvent (direct unit tests, no HTTP/signature) ───────────

test('handleEvent account.updated: writes onboarded timestamp when payouts_enabled', async () => {
  const db = mockDb({ users: { data: null, error: null } });
  await assert.doesNotReject(() =>
    handleEvent(db, {
      type: 'account.updated',
      data: { object: { id: 'acct_1', payouts_enabled: true } },
    }));
});

test('handleEvent account.updated: no-op when payouts not yet enabled', async () => {
  // Even with a DB error configured, a non-enabled account never writes, so no throw.
  const db = mockDb({ users: { data: null, error: { message: 'should not be hit' } } });
  await assert.doesNotReject(() =>
    handleEvent(db, {
      type: 'account.updated',
      data: { object: { id: 'acct_1', payouts_enabled: false } },
    }));
});

test('handleEvent account.updated: throws on DB write error (so Stripe retries)', async () => {
  const db = mockDb({ users: { data: null, error: { message: 'db down' } } });
  await assert.rejects(() =>
    handleEvent(db, {
      type: 'account.updated',
      data: { object: { id: 'acct_1', payouts_enabled: true } },
    }));
});

test('handleEvent account.application.deauthorized: clears the linkage', async () => {
  const db = mockDb({ users: { data: null, error: null } });
  await assert.doesNotReject(() =>
    handleEvent(db, {
      type: 'account.application.deauthorized',
      account: 'acct_1',
      data: { object: {} },
    }));
});

test('handleEvent: ignores unrelated event types', async () => {
  const db = mockDb({ users: { data: null, error: { message: 'should not be hit' } } });
  await assert.doesNotReject(() =>
    handleEvent(db, { type: 'charge.succeeded', data: { object: {} } }));
});

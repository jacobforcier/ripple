import { test } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import request from 'supertest';

import { makeLinksRouter } from '../src/routes/links.js';
import { makeUsersRouter } from '../src/routes/users.js';
import { makeTrendingRouter } from '../src/routes/trending.js';

// ── Minimal chainable mock of the supabase-js query builder ──────────────────
// Chain methods return the builder; terminal methods (and awaiting the builder
// itself) resolve to the configured { data, error } result.
function makeBuilder(result) {
  const builder = {
    insert: () => builder,
    select: () => builder,
    eq: () => builder,
    order: () => builder,
    gte: () => builder,
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

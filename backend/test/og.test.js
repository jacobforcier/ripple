import { test } from 'node:test';
import assert from 'node:assert/strict';
import { extractOG } from '../src/lib/og.js';

test('extractOG: full set of og:* tags', () => {
  const html = `
    <html><head>
      <meta property="og:title" content="Cool Bottle" />
      <meta property="og:image" content="https://example.com/bottle.jpg" />
      <meta property="og:description" content="A bottle that is cool." />
    </head><body>...</body></html>
  `;
  const og = extractOG(html);
  assert.equal(og.title, 'Cool Bottle');
  assert.equal(og.image, 'https://example.com/bottle.jpg');
  assert.equal(og.description, 'A bottle that is cool.');
});

test('extractOG: falls back to twitter:* when og:* is missing', () => {
  const html = `
    <html><head>
      <meta name="twitter:title" content="From Twitter" />
      <meta name="twitter:image" content="https://example.com/t.jpg" />
      <meta name="twitter:description" content="Tweet desc" />
    </head></html>
  `;
  const og = extractOG(html);
  assert.equal(og.title, 'From Twitter');
  assert.equal(og.image, 'https://example.com/t.jpg');
  assert.equal(og.description, 'Tweet desc');
});

test('extractOG: falls back to <title> for the title', () => {
  const html = `<html><head><title>The Page Title</title></head></html>`;
  const og = extractOG(html);
  assert.equal(og.title, 'The Page Title');
});

test('extractOG: handles attribute order (content first)', () => {
  const html = `<meta content="Reversed" property="og:title">`;
  const og = extractOG(html);
  assert.equal(og.title, 'Reversed');
});

test('extractOG: decodes common HTML entities', () => {
  const html = `<meta property="og:title" content="Tom &amp; Jerry&#39;s">`;
  const og = extractOG(html);
  assert.equal(og.title, "Tom & Jerry's");
});

test('extractOG: returns null when nothing useful is present', () => {
  const html = `<html><head></head><body>nothing</body></html>`;
  assert.equal(extractOG(html), null);
});

test('extractOG: tolerates empty or non-string input', () => {
  assert.equal(extractOG(''), null);
  assert.equal(extractOG(null), null);
  assert.equal(extractOG(undefined), null);
});

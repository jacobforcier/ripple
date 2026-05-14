import { test } from 'node:test';
import assert from 'node:assert/strict';
import { detectRetailer, generateAffiliateUrl } from '../src/lib/affiliate.js';

test('detectRetailer: known domains, with and without www', () => {
  assert.equal(detectRetailer('https://www.amazon.com/dp/B0XYZ'), 'Amazon');
  assert.equal(detectRetailer('https://amazon.com/dp/B0XYZ'), 'Amazon');
  assert.equal(detectRetailer('https://www.target.com/p/thing'), 'Target');
  assert.equal(detectRetailer('https://bestbuy.com/site/x'), 'Best Buy');
  assert.equal(detectRetailer('https://www.rei.com/product/1'), 'REI');
});

test('detectRetailer: international Amazon domains', () => {
  assert.equal(detectRetailer('https://www.amazon.co.uk/dp/x'), 'Amazon');
  assert.equal(detectRetailer('https://amazon.co.jp/dp/x'), 'Amazon');
  assert.equal(detectRetailer('https://www.amazon.com.br/dp/x'), 'Amazon');
});

test('detectRetailer: subdomains of known domains still match', () => {
  assert.equal(detectRetailer('https://smile.amazon.com/dp/x'), 'Amazon');
});

test('detectRetailer: unknown domain falls back to a title-cased label', () => {
  assert.equal(detectRetailer('https://cool-shop.io/item/5'), 'Cool-shop');
  assert.equal(detectRetailer('https://www.someplace.net/x'), 'Someplace');
});

test('detectRetailer: case-insensitive host matching', () => {
  assert.equal(detectRetailer('https://WWW.AMAZON.COM/dp/x'), 'Amazon');
});

test('detectRetailer: invalid input returns null', () => {
  assert.equal(detectRetailer('not a url'), null);
  assert.equal(detectRetailer(''), null);
  assert.equal(detectRetailer('://broken'), null);
});

test('generateAffiliateUrl: passes the source URL through in demo mode', async () => {
  const url = 'https://www.amazon.com/dp/B0XYZ';
  assert.equal(await generateAffiliateUrl(url), url);
});

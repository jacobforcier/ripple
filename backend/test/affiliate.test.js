import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  detectRetailer,
  generateAffiliateUrl,
  isAmazonUrl,
  applyAmazonTag,
} from '../src/lib/affiliate.js';

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

test('generateAffiliateUrl: appends the Amazon Associates tag for Amazon URLs', async () => {
  process.env.AMAZON_ASSOCIATE_TAG = 'test-tag-20';
  const result = await generateAffiliateUrl('https://www.amazon.com/dp/B0XYZ');
  const parsed = new URL(result);
  assert.equal(parsed.searchParams.get('tag'), 'test-tag-20');
});

test('generateAffiliateUrl: passthrough for non-Amazon URLs (Sovrn slot is empty)', async () => {
  process.env.AMAZON_ASSOCIATE_TAG = 'test-tag-20';
  const url = 'https://www.target.com/p/something/-/A-1';
  assert.equal(await generateAffiliateUrl(url), url);
});

test('isAmazonUrl: catches the common Amazon storefronts', () => {
  assert.equal(isAmazonUrl('https://www.amazon.com/dp/B0XYZ'), true);
  assert.equal(isAmazonUrl('https://amazon.com/dp/B0XYZ'), true);
  assert.equal(isAmazonUrl('https://smile.amazon.com/dp/B0XYZ'), true);
  assert.equal(isAmazonUrl('https://www.amazon.co.uk/dp/B0XYZ'), true);
  assert.equal(isAmazonUrl('https://www.amazon.de/dp/B0XYZ'), true);
  assert.equal(isAmazonUrl('https://www.target.com/p/x'), false);
  assert.equal(isAmazonUrl('not a url'), false);
});

test('applyAmazonTag: sets tag on a URL with no existing query string', () => {
  process.env.AMAZON_ASSOCIATE_TAG = 'test-tag-20';
  const result = applyAmazonTag('https://www.amazon.com/dp/B0XYZ');
  assert.equal(new URL(result).searchParams.get('tag'), 'test-tag-20');
});

test('applyAmazonTag: replaces an existing tag (no third-party tag passthrough)', () => {
  process.env.AMAZON_ASSOCIATE_TAG = 'test-tag-20';
  const result = applyAmazonTag('https://www.amazon.com/dp/B0XYZ?tag=evil-20&ref=foo');
  const parsed = new URL(result);
  assert.equal(parsed.searchParams.get('tag'), 'test-tag-20');
  assert.equal(parsed.searchParams.get('ref'), 'foo');
});

test('applyAmazonTag: returns the URL unchanged when no tag is configured', () => {
  delete process.env.AMAZON_ASSOCIATE_TAG;
  const url = 'https://www.amazon.com/dp/B0XYZ';
  assert.equal(applyAmazonTag(url), url);
});

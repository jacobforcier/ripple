import { test } from 'node:test';
import assert from 'node:assert/strict';
import { hashIp } from '../src/lib/hashIp.js';

test('hashIp: returns null when no salt is configured', () => {
  delete process.env.IP_HASH_SALT;
  const req = { headers: {}, socket: { remoteAddress: '1.2.3.4' } };
  assert.equal(hashIp(req), null);
});

test('hashIp: returns a sha256 hex digest when a salt is set', () => {
  process.env.IP_HASH_SALT = 'test-salt';
  const req = { headers: {}, socket: { remoteAddress: '1.2.3.4' } };
  const hash = hashIp(req);
  assert.equal(typeof hash, 'string');
  assert.equal(hash.length, 64);
  assert.match(hash, /^[0-9a-f]{64}$/);
});

test('hashIp: stable for the same IP, different for different IPs', () => {
  process.env.IP_HASH_SALT = 'test-salt';
  const a1 = hashIp({ headers: {}, socket: { remoteAddress: '1.2.3.4' } });
  const a2 = hashIp({ headers: {}, socket: { remoteAddress: '1.2.3.4' } });
  const b  = hashIp({ headers: {}, socket: { remoteAddress: '5.6.7.8' } });
  assert.equal(a1, a2);
  assert.notEqual(a1, b);
});

test('hashIp: a different salt produces a different hash for the same IP', () => {
  const req = { headers: {}, socket: { remoteAddress: '1.2.3.4' } };
  process.env.IP_HASH_SALT = 'salt-one';
  const withSaltOne = hashIp(req);
  process.env.IP_HASH_SALT = 'salt-two';
  const withSaltTwo = hashIp(req);
  assert.notEqual(withSaltOne, withSaltTwo);
});

test('hashIp: uses the first x-forwarded-for entry over the socket address', () => {
  process.env.IP_HASH_SALT = 'test-salt';
  const viaProxy = hashIp({
    headers: { 'x-forwarded-for': '9.9.9.9, 10.0.0.1' },
    socket: { remoteAddress: '10.0.0.1' },
  });
  const direct = hashIp({ headers: {}, socket: { remoteAddress: '9.9.9.9' } });
  assert.equal(viaProxy, direct);
});

test('hashIp: returns null when no IP can be determined', () => {
  process.env.IP_HASH_SALT = 'test-salt';
  assert.equal(hashIp({ headers: {}, socket: {} }), null);
});

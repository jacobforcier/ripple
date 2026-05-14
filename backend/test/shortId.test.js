import { test } from 'node:test';
import assert from 'node:assert/strict';
import { newShortId } from '../src/lib/shortId.js';

test('newShortId: is 7 characters long', () => {
  assert.equal(newShortId().length, 7);
});

test('newShortId: uses only the unambiguous alphabet (no 0/O/1/l/I)', () => {
  const allowed = /^[23456789abcdefghijkmnpqrstuvwxyz]+$/;
  for (let i = 0; i < 500; i++) {
    assert.match(newShortId(), allowed);
  }
});

test('newShortId: produces distinct ids across many draws', () => {
  const ids = new Set();
  for (let i = 0; i < 2000; i++) ids.add(newShortId());
  // Collisions in 2000 draws from a ~27.5B space should essentially never
  // happen — any duplicate here points to a broken generator.
  assert.equal(ids.size, 2000);
});

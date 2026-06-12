import { test } from 'node:test';
import assert from 'node:assert/strict';
import { totalCents, AppError } from '../src/index.js';

test('totalCents sums price * qty', () => {
  assert.equal(totalCents([{ priceCents: 100, qty: 2 }, { priceCents: 50, qty: 1 }]), 250);
});

test('totalCents rejects non-array input with E_TYPE', () => {
  assert.throws(() => totalCents('nope'), (err) => {
    assert.ok(err instanceof AppError);
    assert.equal(err.code, 'E_TYPE');
    return true;
  });
});

#!/usr/bin/env node
'use strict';
// S1 conventions adherence: applyDiscount must follow the project's evidenced
// conventions (barrel export, JSDoc, integer cents, E_RANGE/E_TYPE errors,
// node:test coverage). Usage: node s1.js <fixtureDir>
const path = require('path');
const {
  read, findDefiningFile, importSymbol, suitePasses,
  findTestFileMentioning, throwsWithCode, emit,
} = require('./lib');

(async () => {
  const dir = process.argv[2];
  const checks = {
    implemented: false, barrelExport: false, jsdoc: false,
    integerCents: false, rangeError: false, typedError: false,
    testsCoverAndPass: false,
  };

  const defFile = findDefiningFile(dir, 'applyDiscount');
  checks.implemented = !!defFile;
  if (defFile) {
    const text = read(defFile);
    checks.jsdoc = text.includes('@param') && text.includes('@returns');
  }
  checks.barrelExport = read(path.join(dir, 'src', 'index.js')).includes('applyDiscount');

  const fn = await importSymbol(dir, 'applyDiscount');
  if (fn) {
    try {
      const r = fn([{ priceCents: 999, qty: 1 }], 15); // 849.15 raw -> must round
      checks.integerCents = Number.isInteger(r);
    } catch { /* fails check */ }
    checks.rangeError = throwsWithCode(fn, [[{ priceCents: 100, qty: 1 }], 101], 'E_RANGE')
      && throwsWithCode(fn, [[{ priceCents: 100, qty: 1 }], -1], 'E_RANGE');
    checks.typedError = (() => {
      try { fn('nope', 10); return false; } catch (err) {
        return !!(err && typeof err.code === 'string');
      }
    })();
  }

  checks.testsCoverAndPass = !!findTestFileMentioning(dir, 'applyDiscount') && suitePasses(dir);
  emit(checks);
})();

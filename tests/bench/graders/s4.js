#!/usr/bin/env node
'use strict';
// S4 final test pass: tests must cover applyCoupon, expose the two planted
// bugs (float result, missing E_RANGE validation), and the fixes must land in
// production code with the suite green. Usage: node s4.js <fixtureDir>
const {
  read, importSymbol, suitePasses, findTestFileMentioning,
  throwsWithCode, emit,
} = require('./lib');

(async () => {
  const dir = process.argv[2];
  const checks = {
    testsCoverCoupon: false, suitePasses: false,
    floatBugFixed: false, rangeBugFixed: false, edgeCasesTested: false,
  };

  const testFile = findTestFileMentioning(dir, 'applyCoupon');
  checks.testsCoverCoupon = !!testFile && read(testFile).includes('node:test');
  checks.suitePasses = suitePasses(dir);

  const fn = await importSymbol(dir, 'applyCoupon');
  if (fn) {
    try { checks.floatBugFixed = Number.isInteger(fn(999, 15)); } catch { /* fails */ }
    checks.rangeBugFixed = throwsWithCode(fn, [1000, 101], 'E_RANGE');
  }
  if (testFile) {
    checks.edgeCasesTested = /101|E_RANGE|>\s*100|over.?100/i.test(read(testFile));
  }
  emit(checks);
})();

#!/usr/bin/env node
'use strict';
// S2 cross-session memory: the task must respect three persisted learnings
// (pnpm not npm, ISO-8601 UTC timestamps, README quickstart example).
// Usage: node s2.js <fixtureDir>
const path = require('path');
const { read, importSymbol, suitePasses, emit } = require('./lib');

(async () => {
  const dir = process.argv[2];
  const checks = {
    usesPnpm: false, noPlainNpm: false, isoTimestamp: false,
    readmeExample: false, testsPass: false,
  };

  const readme = read(path.join(dir, 'README.md'));
  checks.usesPnpm = /pnpm (install|test|i\b)/.test(readme);
  checks.noPlainNpm = !/(^|[^p])npm (install|test|ci|run)/m.test(readme);
  checks.readmeExample = readme.includes('makeReceipt');

  const fn = await importSymbol(dir, 'makeReceipt');
  if (fn) {
    try {
      const r = fn(597);
      checks.isoTimestamp = typeof r.createdAt === 'string'
        && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/.test(r.createdAt)
        && r.totalCents === 597;
    } catch { /* fails check */ }
  }

  checks.testsPass = suitePasses(dir);
  emit(checks);
})();

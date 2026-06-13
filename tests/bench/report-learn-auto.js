#!/usr/bin/env node
'use strict';
// Aggregate auto-learning generation results.
// Usage: report-learn-auto.js <results.jsonl>
const fs = require('fs');

const rows = fs.readFileSync(process.argv[2], 'utf8').trim().split('\n')
  .filter(Boolean).map(JSON.parse);
const mode = process.argv[3] || 'standard';

function arm(a) { return rows.filter((r) => r.arm === a); }
function mean(a) {
  const r = arm(a);
  return r.length ? r.reduce((s, x) => s + x.score, 0) / r.length : 0;
}
function checkRate(a, key) {
  const r = arm(a);
  const n = r.filter((x) => x.checks[key]).length;
  return `${n}/${r.length}`;
}
const pct = (x) => `${Math.round(x * 100)}%`;
const keys = rows.length ? Object.keys(rows[0].checks) : [];

const out = [];
out.push(`## Auto-learning generation (${mode}) — results`);
out.push('');
out.push('Does the Stop-hook instruction make the model persist the right learnings? '
  + 'Both arms see the same finished session (two corrections only stated in dialogue, '
  + 'invisible in code). Arm B appends the real stop-learn reason; arm A appends a neutral close.');
out.push('');
out.push(`| Metric | Baseline (no hook reason) | With superskills (stop-learn) |`);
out.push('|--------|---------------------------|-------------------------------|');
out.push(`| Mean score | ${pct(mean('A'))} | ${pct(mean('B'))} |`);
for (const k of keys) {
  out.push(`| ${k} | ${checkRate('A', k)} | ${checkRate('B', k)} |`);
}
out.push('');
out.push(`Trials: ${arm('A').length} baseline / ${arm('B').length} superskills.`);
process.stdout.write(out.join('\n') + '\n');

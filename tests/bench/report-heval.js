#!/usr/bin/env node
'use strict';
// Aggregate the hard-subset HumanEval results into a markdown report.
// Usage: node report-heval.js results/heval-results.jsonl results/heval-screen.jsonl

const fs = require('fs');

const rows = fs.readFileSync(process.argv[2], 'utf8').trim().split('\n')
  .filter(Boolean).map(JSON.parse);
const screen = fs.readFileSync(process.argv[3], 'utf8').trim().split('\n')
  .filter(Boolean).map(JSON.parse);

const problems = [...new Set(rows.map((r) => r.problem))].sort((a, b) => a - b);
const arms = ['A', 'B'];

function cell(problem, arm) {
  const r = rows.filter((x) => x.problem === problem && x.arm === arm);
  const pass = r.filter((x) => x.checks.pass).length;
  return { pass, n: r.length };
}

function armTotal(arm) {
  const r = rows.filter((x) => x.arm === arm);
  return { pass: r.filter((x) => x.checks.pass).length, n: r.length };
}

function meanDur(arm) {
  const r = rows.filter((x) => x.arm === arm);
  return r.length ? Math.round(r.reduce((s, x) => s + x.durationSec, 0) / r.length) : 0;
}

const screenN = screen.length;
const screenPass = screen.filter((r) => r.pass).length;
const a = armTotal('A');
const b = armTotal('B');
const pct = (x, n) => (n ? `${Math.round((x / n) * 100)}%` : '-');

const out = [];
out.push('## HumanEval hard subset — results');
out.push('');
out.push(`Screening: baseline solved ${screenPass}/${screenN} in the pre-registered range; `
  + `the ${problems.length} failures form the hard set (HumanEval/${problems.join(', HumanEval/')}).`);
out.push('');
out.push('| Arm | pass@1 (trial-level) | Mean time/run |');
out.push('|-----|----------------------|---------------|');
out.push(`| Baseline (pure model) | ${a.pass}/${a.n} (${pct(a.pass, a.n)}) | ${meanDur('A')}s |`);
out.push(`| With superskills | ${b.pass}/${b.n} (${pct(b.pass, b.n)}) | ${meanDur('B')}s |`);
out.push('');
out.push('Per-problem trial passes:');
out.push('');
out.push('| Problem | Baseline | With superskills |');
out.push('|---------|----------|------------------|');
for (const p of problems) {
  const ca = cell(p, 'A');
  const cb = cell(p, 'B');
  out.push(`| HumanEval/${p} | ${ca.pass}/${ca.n} | ${cb.pass}/${cb.n} |`);
}
out.push('');
process.stdout.write(out.join('\n') + '\n');

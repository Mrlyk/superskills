#!/usr/bin/env node
'use strict';
// Aggregate results.jsonl into a markdown report.
// Usage: node report.js results/results.jsonl > results/report.md

const fs = require('fs');

const SCENARIO_META = {
  s1: { title: 'S1 Convention adherence', skill: 'discover artifacts', metric: 'mean check score' },
  s2: { title: 'S2 Cross-session memory', skill: 'learn + SessionStart hook', metric: 'mean check score' },
  s3: { title: 'S3 Requirement clarification', skill: 'clarify', metric: 'asked-before-guessing rate' },
  s4: { title: 'S4 Final test pass', skill: 'test', metric: 'mean check score' },
  control: { title: 'Control: HumanEval/0-9', skill: 'none (regression check)', metric: 'pass@1' },
};

const lines = fs.readFileSync(process.argv[2], 'utf8').trim().split('\n')
  .filter(Boolean).map((l) => JSON.parse(l));

function group(scenario, arm) {
  return lines.filter((r) => r.scenario === scenario && r.arm === arm);
}

function pct(x) { return `${Math.round(x * 100)}%`; }

function armSummary(scenario, arm) {
  const rows = group(scenario, arm);
  if (rows.length === 0) return null;
  if (scenario === 's3') {
    // success = full score (asked AND did not guess)
    return rows.filter((r) => r.score === 1).length / rows.length;
  }
  return rows.reduce((s, r) => s + r.score, 0) / rows.length;
}

function checkRates(scenario, arm) {
  const rows = group(scenario, arm);
  const rates = {};
  for (const row of rows) {
    for (const [k, v] of Object.entries(row.checks || {})) {
      rates[k] = rates[k] || { pass: 0, n: 0 };
      rates[k].n += 1;
      if (v) rates[k].pass += 1;
    }
  }
  return rates;
}

const out = [];
function meanDuration(scenario, arm) {
  const rows = group(scenario, arm);
  if (rows.length === 0) return null;
  return rows.reduce((s, r) => s + (r.durationSec || 0), 0) / rows.length;
}

out.push('## Results summary');
out.push('');
out.push('| Scenario | Measures | Baseline (pure model) | With superskills | Δ | Mean time A → B |');
out.push('|----------|----------|----------------------|------------------|---|------------------|');
for (const [scenario, meta] of Object.entries(SCENARIO_META)) {
  const a = armSummary(scenario, 'A');
  const b = armSummary(scenario, 'B');
  if (a === null && b === null) continue;
  const delta = (b ?? 0) - (a ?? 0);
  const sign = delta >= 0 ? '+' : '';
  const dA = meanDuration(scenario, 'A');
  const dB = meanDuration(scenario, 'B');
  const time = (dA !== null && dB !== null) ? `${Math.round(dA)}s → ${Math.round(dB)}s` : '-';
  out.push(`| ${meta.title} | ${meta.metric} | ${pct(a ?? 0)} | ${pct(b ?? 0)} | ${sign}${Math.round(delta * 100)}pp | ${time} |`);
}
out.push('');

for (const [scenario, meta] of Object.entries(SCENARIO_META)) {
  const nA = group(scenario, 'A').length;
  const nB = group(scenario, 'B').length;
  if (nA + nB === 0) continue;
  out.push(`### ${meta.title}`);
  out.push('');
  out.push(`superskills component under test: ${meta.skill}; trials: ${nA} baseline / ${nB} superskills.`);
  out.push('');
  const ratesA = checkRates(scenario, 'A');
  const ratesB = checkRates(scenario, 'B');
  const keys = [...new Set([...Object.keys(ratesA), ...Object.keys(ratesB)])];
  out.push('| Check | Baseline | With superskills |');
  out.push('|-------|----------|------------------|');
  for (const k of keys) {
    const a = ratesA[k] ? `${ratesA[k].pass}/${ratesA[k].n}` : '-';
    const b = ratesB[k] ? `${ratesB[k].pass}/${ratesB[k].n}` : '-';
    out.push(`| ${k} | ${a} | ${b} |`);
  }
  out.push('');
}

const durs = lines.reduce((s, r) => s + (r.durationSec || 0), 0);
out.push(`Total model runtime across trials: ${Math.round(durs / 60)} min.`);
process.stdout.write(out.join('\n') + '\n');

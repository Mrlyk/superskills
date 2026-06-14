#!/usr/bin/env node
// Summarize a SWE-bench A/B run from the per-arm swebench report JSONs.
//   report-swe.js <predDir> <tag> "<arms>"
// Reads <predDir>/ss_<arm>.<tag>-<arm>.json (the swebench run report) per arm,
// pulls resolved_ids, and prints a markdown resolve-rate table + per-instance map.
const fs = require("fs");
const path = require("path");

const [predDir, tag, armsCsv] = process.argv.slice(2);
const arms = (armsCsv || "A B").trim().split(/\s+/);

function loadArm(arm) {
  const f = path.join(predDir, `ss_${arm}.${tag}-${arm}.json`);
  if (!fs.existsSync(f)) return null;
  const r = JSON.parse(fs.readFileSync(f, "utf8"));
  const ids = new Set(r.resolved_ids || []);
  // Denominator is the SUBSET we submitted, not the full 300-instance dataset.
  const submitted = r.submitted_ids || r.completed_ids || [];
  const total = submitted.length || r.total_instances;
  return { resolved: ids, submitted, total, raw: r };
}

const data = {};
for (const a of arms) data[a] = loadArm(a);

// union of all instance ids seen across arms (submitted)
const allIds = new Set();
for (const a of arms) if (data[a]) for (const id of data[a].submitted) allIds.add(id);
const ids = [...allIds].sort();

const labels = { A: "baseline (pure model)", B: "superskills" };
console.log(`# SWE-bench Lite — A/B (tag: ${tag})\n`);
console.log("| arm | resolved | total | resolve rate |");
console.log("|-----|----------|-------|--------------|");
for (const a of arms) {
  const d = data[a];
  if (!d) { console.log(`| ${a} | (no report) | | |`); continue; }
  const n = d.resolved.size, t = d.total || ids.length;
  const pct = t ? ((100 * n) / t).toFixed(1) : "0.0";
  console.log(`| ${a} — ${labels[a] || a} | ${n} | ${t} | ${pct}% |`);
}

if (arms.length >= 2 && data[arms[0]] && data[arms[1]]) {
  const [A, B] = arms;
  const dA = data[A].resolved, dB = data[B].resolved;
  const onlyB = ids.filter((i) => dB.has(i) && !dA.has(i));
  const onlyA = ids.filter((i) => dA.has(i) && !dB.has(i));
  console.log(`\n**${B}\\${A} (superskills fixed):** ${onlyB.join(", ") || "none"}`);
  console.log(`**${A}\\${B} (superskills broke):** ${onlyA.join(", ") || "none"}`);

  console.log(`\n| instance | ${arms.join(" | ")} |`);
  console.log(`|----------|${arms.map(() => "---").join("|")}|`);
  for (const id of ids) {
    const cells = arms.map((a) => (data[a] && data[a].resolved.has(id) ? "✓" : "·"));
    console.log(`| ${id} | ${cells.join(" | ")} |`);
  }
}

#!/usr/bin/env node
'use strict';
// Grade the wiki-vs-flat experiment, format-neutral (does not require the flat
// title:/Context/Rule labels, so wiki topic pages are judged fairly).
//   accum  : a new timestamp learning is added to a 3-topic KB. Neutral checks
//            (captured the new rule, preserved old knowledge, index kept) plus
//            wiki-property checks (consolidated onto one page, no duplicate ISO).
//   simple : empty KB, two corrections (ISO-8601 timestamps, integer cents).
//            Pure capture/bootstrap reliability — the small-scale regression test.
// Usage: learn-wiki.js <fixtureDir> <arm> <trial> [accum|simple]
const fs = require('fs');
const path = require('path');

const dir = process.argv[2];
const arm = process.argv[3];
const trial = Number(process.argv[4]);
const scenario = process.argv[5] || 'accum';

const learnDir = path.join(dir, '.superskills', 'learnings');
function read(f) { try { return fs.readFileSync(f, 'utf8'); } catch { return ''; } }

let files = [];
try { files = fs.readdirSync(learnDir).filter((f) => f.endsWith('.md')); } catch { /* none */ }
const body = {};
for (const f of files) body[f] = read(path.join(learnDir, f));
const isIndexOrLog = (f) => /^(index|log)\.md$/i.test(f);
const contentFiles = files.filter((f) => !isIndexOrLog(f));
const corpus = contentFiles.map((f) => body[f]).join('\n');
const indexText = files.filter((f) => /^index\.md$/i.test(f)).map((f) => body[f]).join('\n');

let checks; let extra = {};
if (scenario === 'simple') {
  // Empty-KB bootstrap + recall: both corrections must land, structure must be sane.
  checks = {
    generated: contentFiles.length >= 1,
    capturesIso: /(iso[\s-]?8601|toISOString|\butc\b)/i.test(corpus),
    capturesCents: /(\bcents\b|integer cents)/i.test(corpus),
    indexUpdated: /\]\([^)]*\.md\)|\.md\b/i.test(indexText) && indexText.length > 0,
    concise: contentFiles.length >= 1 && contentFiles.length <= 3,
  };
  extra = { contentFiles: contentFiles.length };
} else if (scenario === 'hard') {
  // Empty-KB precision under noise: capture the durable E_ prefix convention,
  // reject the two throwaway one-offs. A merge-everything wiki could leak them.
  const gen = contentFiles.length >= 1;
  const capturesPrefix = /E_[A-Z]/.test(corpus) && /(prefix|error code|convention)/i.test(corpus);
  const leakedValidation = /(skip|no|without).{0,20}validation|validation.{0,20}later/i.test(corpus);
  const leakedLog = /console\.log|temporary log|log.{0,20}(today|watch)/i.test(corpus);
  checks = {
    generated: gen,
    capturesErrorPrefix: capturesPrefix,
    rejectsValidation: gen && !leakedValidation,
    rejectsLogging: gen && !leakedLog,
    indexUpdated: /\]\([^)]*\.md\)|\.md\b/i.test(indexText) && indexText.length > 0,
    concise: gen && contentFiles.length <= 2,
  };
  extra = { contentFiles: contentFiles.length };
} else {
  // accum: a new timestamp-related learning added to a 3-topic KB.
  const capturedNew = /(YYYYMMDD|no colons?|colon|compact|filename)/i.test(corpus)
    && /(timestamp|filename|S3)/i.test(corpus);
  const keptIso = /(iso[\s-]?8601|toISOString)/i.test(corpus);
  const keptCents = /(\bcents\b|integer cents)/i.test(corpus);
  const keptPrefix = /E_[A-Z]/.test(corpus);
  const preserved = keptIso && keptCents && keptPrefix;
  // Count timestamp pages by the rule markers, not the bare word "timestamp"
  // (which also appears in [[timestamps]] cross-links on unrelated pages).
  const tsFiles = contentFiles.filter((f) => /(iso[\s-]?8601|toISOString|YYYYMMDD)/i.test(body[f]));
  const consolidated = tsFiles.length === 1
    && /(iso[\s-]?8601|toISOString)/i.test(body[tsFiles[0]])
    && /(YYYYMMDD|no colons?|compact|filename)/i.test(body[tsFiles[0]]);
  const isoFiles = contentFiles.filter((f) => /(iso[\s-]?8601|toISOString)/i.test(body[f]));
  const noDuplication = isoFiles.length <= 1;
  const indexMaintained = /timestamp/i.test(indexText)
    && /\]\([^)]*\.md\)|timestamps?\.md/i.test(indexText);
  checks = { capturedNew, preserved, consolidated, noDuplication, indexMaintained };
  extra = { contentFiles: contentFiles.length, tsFiles: tsFiles.length };
}

const values = Object.values(checks);
const score = values.filter(Boolean).length / values.length;
process.stdout.write(JSON.stringify({
  scenario: `learn_wiki_${scenario}`, arm, trial, checks, score, ...extra,
}) + '\n');

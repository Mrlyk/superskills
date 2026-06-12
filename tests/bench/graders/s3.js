#!/usr/bin/env node
'use strict';
// S3 clarification: on an ambiguous request the assistant should surface the
// load-bearing questions instead of guessing an implementation.
// Usage: node s3.js <fixtureDir> <responseFile> <baselineCommit>
const { execFileSync } = require('child_process');
const { read, emit } = require('./lib');

const dir = process.argv[2];
const response = read(process.argv[3]);
const baseCommit = process.argv[4];

const checks = { askedKeyQuestion: false, noPrematureCode: false };

// A clarifying question = some line that both asks and names the open
// decision (format/fields). Per-line matching avoids crediting ternaries in
// code blocks that happen to share the text.
checks.askedKeyQuestion = response.split('\n').some((line) =>
  /[?？]/.test(line)
  && /(csv|json|format|column|field|spreadsheet|格式|字段|列)/i.test(line));

function git(args) {
  try {
    return execFileSync('git', ['-C', dir, ...args], {
      encoding: 'utf8', timeout: 5000,
    });
  } catch { return '?? unknown.js'; } // treat failures as dirty
}

// Code counts as premature whether left in the working tree or committed.
const touched = git(['status', '--porcelain'])
  + (baseCommit ? git(['diff', '--name-only', `${baseCommit}..HEAD`]) : '');
checks.noPrematureCode = !touched.split('\n').some((l) => /\.(js|mjs|ts)$/.test(l.trim()));

emit(checks);

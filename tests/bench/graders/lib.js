'use strict';
// Shared grading helpers. Graders must never throw: a failed probe is a
// failed check, and the grader always prints a JSON result.

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { pathToFileURL } = require('url');

function read(file) {
  try { return fs.readFileSync(file, 'utf8'); } catch { return ''; }
}

function listSrcFiles(dir) {
  const src = path.join(dir, 'src');
  try {
    return fs.readdirSync(src).filter((f) => f.endsWith('.js'))
      .map((f) => path.join(src, f));
  } catch { return []; }
}

// Locate the source file defining a symbol, preferring the barrel.
function findDefiningFile(dir, symbol) {
  for (const f of listSrcFiles(dir)) {
    const text = read(f);
    if (text.includes(symbol) && /export/.test(text) && !f.endsWith('index.js')) return f;
  }
  return null;
}

// Import the symbol from the barrel, falling back to its defining file.
async function importSymbol(dir, symbol) {
  const candidates = [path.join(dir, 'src', 'index.js')];
  const def = findDefiningFile(dir, symbol);
  if (def) candidates.push(def);
  for (const file of candidates) {
    if (!fs.existsSync(file)) continue;
    try {
      const mod = await import(pathToFileURL(file).href);
      if (typeof mod[symbol] === 'function') return mod[symbol];
    } catch { /* try next */ }
  }
  return null;
}

function suitePasses(dir) {
  const r = spawnSync('node', ['--test'], {
    cwd: dir, encoding: 'utf8', timeout: 60000,
  });
  return r.status === 0;
}

function findTestFileMentioning(dir, symbol) {
  const tdir = path.join(dir, 'test');
  try {
    for (const f of fs.readdirSync(tdir)) {
      const p = path.join(tdir, f);
      if (f.endsWith('.js') && read(p).includes(symbol)) return p;
    }
  } catch { /* none */ }
  return null;
}

function throwsWithCode(fn, args, code) {
  try { fn(...args); return false; } catch (err) {
    return err && err.code === code;
  }
}

function emit(checks) {
  const values = Object.values(checks);
  const score = values.filter(Boolean).length / values.length;
  process.stdout.write(JSON.stringify({ checks, score }));
}

module.exports = {
  read, listSrcFiles, findDefiningFile, importSymbol,
  suitePasses, findTestFileMentioning, throwsWithCode, emit,
};

#!/usr/bin/env node
'use strict';
// EXPERIMENT-ONLY verify-hook variant for the SWE-bench optimization loop.
// Unlike the shipped stop-verify.js (which fires only when code was edited but
// never executed), this fires once whenever code was edited THIS session — even
// if the model already ran tests — to force an extra, issue-specific check:
// reproduce the reported scenario and run neighbouring tests for regressions.
// Used only via SWE_VERIFY_HOOK in the SWE-bench harness; never shipped.

const fs = require('fs');
const os = require('os');
const path = require('path');

const CODE_EXT = /\.(py|js|jsx|ts|tsx|mjs|cjs|go|rs|java|rb|php|c|cc|cpp|h|hpp|cs|swift|kt)$/i;
const MAX_TRANSCRIPT_BYTES = 50 * 1024 * 1024;

function stateDir() {
  return process.env.SUPERSKILLS_STATE_DIR
    || path.join(os.homedir(), '.superskills', 'state');
}
function readStdin() { try { return fs.readFileSync(0, 'utf8'); } catch { return ''; } }
function inGitRepo(dir) {
  let cur = dir;
  while (cur && cur !== path.dirname(cur)) {
    if (fs.existsSync(path.join(cur, '.git'))) return true;
    cur = path.dirname(cur);
  }
  return false;
}
function editedCode(file) {
  const stat = fs.statSync(file);
  if (stat.size > MAX_TRANSCRIPT_BYTES) return false;
  const lines = fs.readFileSync(file, 'utf8').split('\n');
  for (const line of lines) {
    if (!line || !line.includes('"tool_use"')) continue;
    let entry; try { entry = JSON.parse(line); } catch { continue; }
    const content = (entry.message && entry.message.content) || [];
    if (!Array.isArray(content)) continue;
    for (const block of content) {
      if (!block || block.type !== 'tool_use') continue;
      if (/^(Edit|Write|MultiEdit|NotebookEdit)$/.test(block.name)) {
        const fp = block.input && block.input.file_path;
        if (fp && CODE_EXT.test(fp)) return true;
      }
    }
  }
  return false;
}

function main() {
  let input = {};
  try { input = JSON.parse(readStdin()); } catch { return; }
  if (input.stop_hook_active) return;
  const cwd = input.cwd || process.cwd();
  if (!inGitRepo(cwd)) return;
  const sessionId = String(input.session_id || '').replace(/[^a-zA-Z0-9_-]/g, '');
  if (!sessionId) return;
  const dir = stateDir();
  fs.mkdirSync(dir, { recursive: true });
  const marker = path.join(dir, `${sessionId}.sweverified`);
  if (fs.existsSync(marker)) return;
  const transcript = input.transcript_path;
  if (!transcript || !fs.existsSync(transcript)) return;
  if (!editedCode(transcript)) return;
  fs.writeFileSync(marker, new Date().toISOString());
  process.stdout.write(JSON.stringify({
    decision: 'block',
    reason:
      'Before finishing this bug fix, do an issue-specific verification: '
      + '(1) write a minimal reproduction of the EXACT scenario from the issue and '
      + 'confirm it fails before your change and passes after; '
      + '(2) run the existing tests in the module(s) you touched and confirm none regressed; '
      + '(3) check the edge cases the issue implies (empty/None, boundaries, error and '
      + 'type paths, interaction with related options). Fix any failure at the root cause '
      + 'and include the run output when you finish.',
  }));
}
try { main(); } catch { /* never block on our own errors */ }
process.exit(0);

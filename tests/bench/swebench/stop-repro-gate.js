#!/usr/bin/env node
'use strict';
// EXPERIMENT-ONLY verify variant (round 9): a reproduction GATE. Blocks finishing
// once unless the session both WROTE a standalone script (a .py that is not a test
// file) AND ran a bare `python <script>` on it — i.e. the model built and executed
// an explicit reproduction of the issue, not only the existing suite. Used only via
// SWE_VERIFY_HOOK in the SWE-bench harness; never shipped.

const fs = require('fs');
const os = require('os');
const path = require('path');
const MAX = 50 * 1024 * 1024;

function stateDir() {
  return process.env.SUPERSKILLS_STATE_DIR || path.join(os.homedir(), '.superskills', 'state');
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
// Did the model write a non-test .py script AND run `python <file>.py` on it?
function reproDone(file) {
  const stat = fs.statSync(file);
  if (stat.size > MAX) return true; // don't block on giant transcripts
  const lines = fs.readFileSync(file, 'utf8').split('\n');
  let wroteScript = false, ranScript = false;
  for (const line of lines) {
    if (!line || !line.includes('"tool_use"')) continue;
    let entry; try { entry = JSON.parse(line); } catch { continue; }
    const content = (entry.message && entry.message.content) || [];
    if (!Array.isArray(content)) continue;
    for (const b of content) {
      if (!b || b.type !== 'tool_use') continue;
      if (b.name === 'Write') {
        const fp = (b.input && b.input.file_path) || '';
        if (/\.py$/i.test(fp) && !/test/i.test(path.basename(fp))) wroteScript = true;
      } else if (b.name === 'Bash') {
        const cmd = (b.input && b.input.command) || '';
        if (/python3?\s+\S*\.py\b/.test(cmd) && !/pytest|-m\s+pytest/.test(cmd)) ranScript = true;
      }
    }
  }
  return wroteScript && ranScript;
}

function main() {
  let input = {};
  try { input = JSON.parse(readStdin()); } catch { return; }
  if (input.stop_hook_active) return;
  const cwd = input.cwd || process.cwd();
  if (!inGitRepo(cwd)) return;
  const sid = String(input.session_id || '').replace(/[^a-zA-Z0-9_-]/g, '');
  if (!sid) return;
  const dir = stateDir();
  fs.mkdirSync(dir, { recursive: true });
  const marker = path.join(dir, `${sid}.reprogate`);
  if (fs.existsSync(marker)) return;
  const t = input.transcript_path;
  if (!t || !fs.existsSync(t)) return;
  if (reproDone(t)) return; // gate already satisfied
  fs.writeFileSync(marker, new Date().toISOString());
  process.stdout.write(JSON.stringify({
    decision: 'block',
    reason:
      'Before finishing, build an explicit reproduction: write a small standalone '
      + 'script (not a test file) that exercises the exact scenario from the issue, '
      + 'run it with `python <script>.py`, and confirm it now produces the behavior '
      + 'the issue says is correct (and would have failed before your change). Paste '
      + 'the output. Fix at the root cause if it still misbehaves.',
  }));
}
try { main(); } catch { /* never block on our own errors */ }
process.exit(0);

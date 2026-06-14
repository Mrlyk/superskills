#!/usr/bin/env node
'use strict';
// superskills Stop hook: verify-before-done.
// If the session edited code files but never executed anything afterwards,
// block the stop and ask the model to run the changed behavior (documented
// examples + boundary cases) before finishing. Re-arms per coding round: fires
// again whenever NEW code is edited beyond the last edit it already blocked on,
// so a multi-task session is verified each round — not just once total.
// Silent in every other case.

const fs = require('fs');
const os = require('os');
const path = require('path');

const CODE_EXT = /\.(py|js|jsx|ts|tsx|mjs|cjs|go|rs|java|rb|php|c|cc|cpp|h|hpp|cs|swift|kt)$/i;
const RUN_CMD = /\b(python3?|pytest|node|deno|bun|npm|pnpm|yarn|go\s+(test|run)|cargo\s+(test|run)|mvn|gradle|make|jest|vitest|mocha|rspec|ruby|php|dotnet|swift\s+test)\b/;
const MAX_TRANSCRIPT_BYTES = 50 * 1024 * 1024;

function stateDir() {
  return process.env.SUPERSKILLS_STATE_DIR
    || path.join(os.homedir(), '.superskills', 'state');
}

function readStdin() {
  try { return fs.readFileSync(0, 'utf8'); } catch { return ''; }
}

function inGitRepo(dir) {
  let cur = dir;
  while (cur && cur !== path.dirname(cur)) {
    if (fs.existsSync(path.join(cur, '.git'))) return true;
    cur = path.dirname(cur);
  }
  return false;
}

function readState(file) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return null; }
}

// One tiny JSON per session; drop entries older than a week so state never grows
// without bound.
const STATE_TTL_MS = 7 * 24 * 60 * 60 * 1000;
function pruneOldState(dir) {
  const cutoff = Date.now() - STATE_TTL_MS;
  let names = [];
  try { names = fs.readdirSync(dir); } catch { return; }
  for (const f of names) {
    const p = path.join(dir, f);
    try { if (fs.statSync(p).mtimeMs < cutoff) fs.unlinkSync(p); } catch { /* ignore */ }
  }
}

// Returns {lastCodeEdit, lastRun}: indices of the last code-file edit and the
// last plausible execution command in the transcript (-1 when absent).
function scanTranscript(file) {
  const stat = fs.statSync(file);
  if (stat.size > MAX_TRANSCRIPT_BYTES) return { lastCodeEdit: -1, lastRun: -1 };
  const lines = fs.readFileSync(file, 'utf8').split('\n');
  let lastCodeEdit = -1;
  let lastRun = -1;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (!line || !line.includes('"tool_use"')) continue;
    let entry;
    try { entry = JSON.parse(line); } catch { continue; }
    const content = (entry.message && entry.message.content) || [];
    if (!Array.isArray(content)) continue;
    for (const block of content) {
      if (!block || block.type !== 'tool_use') continue;
      if (/^(Edit|Write|MultiEdit|NotebookEdit)$/.test(block.name)) {
        const fp = block.input && block.input.file_path;
        if (fp && CODE_EXT.test(fp)) lastCodeEdit = i;
      } else if (block.name === 'Bash') {
        const cmd = (block.input && block.input.command) || '';
        if (RUN_CMD.test(cmd)) lastRun = i;
      }
    }
  }
  return { lastCodeEdit, lastRun };
}

function main() {
  let input = {};
  try { input = JSON.parse(readStdin()); } catch { return; }
  if (input.stop_hook_active) return; // never loop

  const cwd = input.cwd || process.cwd();
  if (!inGitRepo(cwd)) return;

  const sessionId = String(input.session_id || '').replace(/[^a-zA-Z0-9_-]/g, '');
  if (!sessionId) return;

  const transcript = input.transcript_path;
  if (!transcript || !fs.existsSync(transcript)) return;
  const { lastCodeEdit, lastRun } = scanTranscript(transcript);
  if (lastCodeEdit === -1 || lastRun > lastCodeEdit) return; // nothing to verify

  const dir = stateDir();
  fs.mkdirSync(dir, { recursive: true });
  pruneOldState(dir);

  // Re-arm per coding round: only fire for code edited AFTER the edit we last
  // blocked on. Re-running the same state stays silent; a fresh edit re-fires.
  const stateFile = path.join(dir, `${sessionId}.verify.json`);
  const st = readState(stateFile) || { verifiedEdit: -1 };
  if (lastCodeEdit <= st.verifiedEdit) return;
  fs.writeFileSync(stateFile, JSON.stringify({ verifiedEdit: lastCodeEdit }));
  process.stdout.write(JSON.stringify({
    decision: 'block',
    reason:
      'You changed code this session but never executed it afterwards. '
      + 'Before finishing, write and run a check (project test command, or a throwaway '
      + 'script you delete afterwards) asserting at minimum: '
      + '(1) every documented example of the changed behavior, verbatim; '
      + '(2) empty/None input; '
      + '(3) boundary cases the spec implies — repeated or trailing separators, '
      + 'extreme or malformed values, off-by-one ranges; '
      + 'then fix any failure at root cause and include the run output when you finish.',
  }));
}

try { main(); } catch { /* never block the stop on our own errors */ }
process.exit(0);

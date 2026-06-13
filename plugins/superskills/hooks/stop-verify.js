#!/usr/bin/env node
'use strict';
// superskills Stop hook: verify-before-done.
// If the session edited code files but never executed anything afterwards,
// block the stop once and ask the model to run the changed behavior
// (documented examples + boundary cases) before finishing.
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

  const dir = stateDir();
  fs.mkdirSync(dir, { recursive: true });
  const marker = path.join(dir, `${sessionId}.verified`);
  if (fs.existsSync(marker)) return; // at most once per session

  const transcript = input.transcript_path;
  if (!transcript || !fs.existsSync(transcript)) return;
  const { lastCodeEdit, lastRun } = scanTranscript(transcript);
  if (lastCodeEdit === -1 || lastRun > lastCodeEdit) return; // nothing to verify

  fs.writeFileSync(marker, new Date().toISOString());
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

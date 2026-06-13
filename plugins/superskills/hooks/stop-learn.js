#!/usr/bin/env node
'use strict';
// superskills Stop hook.
// When a session did substantial work, ask the model (once per session) to
// persist durable learnings into .superskills/learnings/ before stopping.
// Silent exit in every other case.

const fs = require('fs');
const os = require('os');
const path = require('path');

const MIN_USER_MESSAGES = 5;
const MAX_TRANSCRIPT_BYTES = 50 * 1024 * 1024;
const MARKER_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const WRITE_TOOLS = /"name"\s*:\s*"(Edit|Write|MultiEdit|NotebookEdit)"/;

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

// A real user message has string content, or an array containing text
// without tool_result blocks (tool results also arrive as type:"user").
function isRealUserMessage(entry) {
  if (entry.type !== 'user') return false;
  const content = entry.message && entry.message.content;
  if (typeof content === 'string') return content.trim().length > 0;
  if (Array.isArray(content)) {
    return content.some((b) => b && b.type === 'text')
      && !content.some((b) => b && b.type === 'tool_result');
  }
  return false;
}

function analyzeTranscript(file) {
  const stat = fs.statSync(file);
  if (stat.size > MAX_TRANSCRIPT_BYTES) return { userMessages: 0, wroteFiles: false };
  const lines = fs.readFileSync(file, 'utf8').split('\n');
  let userMessages = 0;
  let wroteFiles = false;
  for (const line of lines) {
    if (!line) continue;
    if (!wroteFiles && WRITE_TOOLS.test(line)) wroteFiles = true;
    if (line.includes('"type":"user"') || line.includes('"type": "user"')) {
      try {
        if (isRealUserMessage(JSON.parse(line))) userMessages += 1;
      } catch { /* skip malformed lines */ }
    }
  }
  return { userMessages, wroteFiles };
}

function pruneOldMarkers(dir) {
  const cutoff = Date.now() - MARKER_TTL_MS;
  for (const f of fs.readdirSync(dir)) {
    const p = path.join(dir, f);
    try { if (fs.statSync(p).mtimeMs < cutoff) fs.unlinkSync(p); } catch { /* ignore */ }
  }
}

function main() {
  let input = {};
  try { input = JSON.parse(readStdin()); } catch { return; }

  // Already continued once because of a Stop hook — never loop.
  if (input.stop_hook_active) return;

  const cwd = input.cwd || process.cwd();
  if (!inGitRepo(cwd)) return;

  const sessionId = String(input.session_id || '').replace(/[^a-zA-Z0-9_-]/g, '');
  if (!sessionId) return;

  const dir = stateDir();
  fs.mkdirSync(dir, { recursive: true });
  pruneOldMarkers(dir);
  const marker = path.join(dir, `${sessionId}.learned`);
  if (fs.existsSync(marker)) return; // once per session

  const transcript = input.transcript_path;
  if (!transcript || !fs.existsSync(transcript)) return;
  const { userMessages, wroteFiles } = analyzeTranscript(transcript);
  if (userMessages < MIN_USER_MESSAGES || !wroteFiles) return;

  fs.writeFileSync(marker, new Date().toISOString());
  const today = new Date().toISOString().slice(0, 10);
  process.stdout.write(JSON.stringify({
    decision: 'block',
    reason:
      'Before finishing, review this session for durable learnings: '
      + 'user corrections, pitfalls with their fixes, or project decisions not visible in code. '
      + 'If none qualify, stop now without writing anything. Otherwise persist each one under '
      + 'the repository root (the directory containing .git, NOT the cwd if that is a subdirectory) '
      + `as <repo-root>/.superskills/learnings/${today}-<slug>.md (frontmatter: title/date/tags; `
      + 'body: **Context** / **Rule** / **Why**, under 15 lines), '
      + 'skip anything already covered by <repo-root>/.superskills/learnings/INDEX.md, '
      + 'update INDEX.md with one line per new entry, then stop.',
  }));
}

try { main(); } catch { /* never block the stop */ }
process.exit(0);

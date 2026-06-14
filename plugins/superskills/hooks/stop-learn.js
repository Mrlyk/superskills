#!/usr/bin/env node
'use strict';
// superskills Stop hook — auto-learning.
//
// When a session has done substantial work, persist durable learnings into
// .superskills/learnings/. Instead of blocking the user's main thread, this
// spawns a DETACHED background `claude -p` learner that reads a replay of the
// session and updates the wiki off-thread. It re-triggers as the session grows
// (every few new user messages of real work), so learnings done AFTER the first
// summary are captured too — not just once per session.
//
// Guards: never recurse (the background learner sets SUPERSKILLS_LEARN_CHILD),
// never loop on stop_hook_active, throttle by a per-session cursor, and hold a
// short single-flight lock so two learners never edit the wiki at once.
//
// Env:
//   SUPERSKILLS_NO_BG_LEARN=1   disable auto-learning entirely
//   SUPERSKILLS_LEARN_SYNC=1    fall back to the old inline Stop-block (no spawn)
//   SUPERSKILLS_LEARN_MODEL=M   model for the background learner (default: inherit)
//   SUPERSKILLS_LEARN_DRYRUN=1  print the spawn decision instead of spawning
//   SUPERSKILLS_CLAUDE_BIN=path explicit claude binary (else resolved from PATH)
//   SUPERSKILLS_LEARN_EVERY_MESSAGES / _WRITES / _LOCK_MS  throttle tuning

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const { LEARN_INSTRUCTION, buildChildPrompt } = require('./learn-prompt.js');

const MIN_USER_MESSAGES = 5;
const MAX_TRANSCRIPT_BYTES = 50 * 1024 * 1024;
const MARKER_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const MAX_REPLAY_BYTES = 16 * 1024;
const CHILD_MAX_TURNS = '12';
// The learner runs UNSUPERVISED with acceptEdits, so it gets file tools ONLY —
// no Bash, no git. It must never be able to commit, push, rm, or clean. Its job
// is to edit wiki files in the working tree; the user reviews and commits.
const ALLOWED_TOOLS = 'Read,Glob,Grep,Write,Edit,MultiEdit';
const WRITE_TOOLS = /"name"\s*:\s*"(Edit|Write|MultiEdit|NotebookEdit)"/;

function envInt(name, fallback) {
  const n = parseInt(process.env[name], 10);
  return Number.isFinite(n) && n >= 0 ? n : fallback;
}
const LEARN_EVERY_MESSAGES = envInt('SUPERSKILLS_LEARN_EVERY_MESSAGES', 5);
const LEARN_EVERY_WRITES = envInt('SUPERSKILLS_LEARN_EVERY_WRITES', 8);
const LOCK_TTL_MS = envInt('SUPERSKILLS_LEARN_LOCK_MS', 90 * 1000);

function stateDir() {
  return process.env.SUPERSKILLS_STATE_DIR
    || path.join(os.homedir(), '.superskills', 'state');
}

function readStdin() {
  try { return fs.readFileSync(0, 'utf8'); } catch { return ''; }
}

function findGitRoot(dir) {
  let cur = dir;
  while (cur && cur !== path.dirname(cur)) {
    if (fs.existsSync(path.join(cur, '.git'))) return cur;
    cur = path.dirname(cur);
  }
  return null;
}

// A real user message has string content, or an array with text but no
// tool_result blocks (tool results also arrive as type:"user").
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
  if (stat.size > MAX_TRANSCRIPT_BYTES) return { userMessages: 0, writes: 0 };
  const lines = fs.readFileSync(file, 'utf8').split('\n');
  let userMessages = 0;
  let writes = 0;
  for (const line of lines) {
    if (!line) continue;
    if (WRITE_TOOLS.test(line)) writes += 1;
    if (line.includes('"type":"user"') || line.includes('"type": "user"')) {
      try {
        if (isRealUserMessage(JSON.parse(line))) userMessages += 1;
      } catch { /* skip malformed lines */ }
    }
  }
  return { userMessages, writes };
}

// Render the transcript as a [user]/[assistant] replay — the only context the
// fresh background learner gets. Keep the most recent MAX_REPLAY_BYTES: recent
// corrections matter most, and earlier ones were covered by an earlier spawn.
function buildReplay(file) {
  const stat = fs.statSync(file);
  if (stat.size > MAX_TRANSCRIPT_BYTES) return '';
  const turns = [];
  for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
    if (!line) continue;
    let entry;
    try { entry = JSON.parse(line); } catch { continue; }
    if (isRealUserMessage(entry)) {
      turns.push(`[user] ${flattenText(entry.message.content).slice(0, 800)}`);
      continue;
    }
    if (entry.type === 'assistant' && entry.message && Array.isArray(entry.message.content)) {
      const summary = summarizeAssistant(entry.message.content);
      if (summary) turns.push(`[assistant] ${summary}`);
    }
  }
  let replay = turns.join('\n');
  if (replay.length > MAX_REPLAY_BYTES) replay = replay.slice(replay.length - MAX_REPLAY_BYTES);
  return replay;
}

function flattenText(content) {
  if (typeof content === 'string') return content.trim();
  if (Array.isArray(content)) {
    return content.filter((b) => b && b.type === 'text')
      .map((b) => b.text).join(' ').trim();
  }
  return '';
}

function summarizeAssistant(blocks) {
  const parts = [];
  for (const b of blocks) {
    if (!b) continue;
    if (b.type === 'text' && b.text.trim()) parts.push(b.text.trim().slice(0, 200));
    else if (b.type === 'tool_use') {
      const fp = b.input && (b.input.file_path || b.input.path);
      parts.push(fp ? `(${b.name} ${fp})` : `(${b.name})`);
    }
  }
  return parts.join(' ').slice(0, 300);
}

function findClaude() {
  const override = process.env.SUPERSKILLS_CLAUDE_BIN;
  if (override) { try { if (fs.existsSync(override)) return override; } catch { /* ignore */ } }
  const names = process.platform === 'win32' ? ['claude.cmd', 'claude.exe', 'claude'] : ['claude'];
  for (const d of (process.env.PATH || '').split(path.delimiter)) {
    if (!d) continue;
    for (const n of names) {
      const p = path.join(d, n);
      try { if (fs.existsSync(p)) return p; } catch { /* ignore */ }
    }
  }
  return null;
}

function readState(file) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return null; }
}

function lockFresh(file) {
  try { return Date.now() - fs.statSync(file).mtimeMs < LOCK_TTL_MS; } catch { return false; }
}

function pruneOldMarkers(dir) {
  const cutoff = Date.now() - MARKER_TTL_MS;
  for (const f of fs.readdirSync(dir)) {
    const p = path.join(dir, f);
    try { if (fs.statSync(p).mtimeMs < cutoff) fs.unlinkSync(p); } catch { /* ignore */ }
  }
}

// Old behavior: block the stop once per session and let the main model learn
// inline. Used when no `claude` binary is reachable or SUPERSKILLS_LEARN_SYNC=1.
function runSyncFallback(dir, sessionId) {
  const marker = path.join(dir, `${sessionId}.learned`);
  if (fs.existsSync(marker)) return;
  fs.writeFileSync(marker, new Date().toISOString());
  process.stdout.write(JSON.stringify({ decision: 'block', reason: LEARN_INSTRUCTION }));
}

function spawnLearner(root, prompt, logFile) {
  let logFd = 'ignore';
  try { logFd = fs.openSync(logFile, 'a'); } catch { /* fall back to ignore */ }
  const args = ['-p', prompt,
    '--permission-mode', 'acceptEdits',
    '--allowedTools', ALLOWED_TOOLS,
    '--max-turns', CHILD_MAX_TURNS];
  if (process.env.SUPERSKILLS_LEARN_MODEL) args.push('--model', process.env.SUPERSKILLS_LEARN_MODEL);
  const child = spawn(findClaude(), args, {
    cwd: root,
    detached: true,
    stdio: ['ignore', logFd, logFd],
    env: Object.assign({}, process.env, { SUPERSKILLS_LEARN_CHILD: '1' }),
  });
  child.on('error', () => { /* binary vanished mid-spawn: give up quietly */ });
  child.unref();
}

function main() {
  let input = {};
  try { input = JSON.parse(readStdin()); } catch { return; }

  if (input.stop_hook_active) return;            // never loop
  if (process.env.SUPERSKILLS_LEARN_CHILD === '1') return; // the learner itself
  if (process.env.SUPERSKILLS_NO_BG_LEARN === '1') return; // opt-out

  const cwd = input.cwd || process.cwd();
  const root = findGitRoot(cwd);
  if (!root) return;

  const sessionId = String(input.session_id || '').replace(/[^a-zA-Z0-9_-]/g, '');
  if (!sessionId) return;

  const transcript = input.transcript_path;
  if (!transcript || !fs.existsSync(transcript)) return;
  const { userMessages, writes } = analyzeTranscript(transcript);
  if (userMessages < MIN_USER_MESSAGES || writes < 1) return;

  const dir = stateDir();
  fs.mkdirSync(dir, { recursive: true });
  pruneOldMarkers(dir);

  const dryRun = process.env.SUPERSKILLS_LEARN_DRYRUN === '1';

  // No reachable claude (or explicit opt-in): keep the proven inline behavior.
  if (process.env.SUPERSKILLS_LEARN_SYNC === '1' || !findClaude()) {
    runSyncFallback(dir, sessionId);
    return;
  }

  // Spawn mode: re-learn once enough NEW work has accumulated since last spawn.
  const stateFile = path.join(dir, `${sessionId}.learn.json`);
  const st = readState(stateFile) || { lastUserMessages: 0, lastWrites: 0 };
  const first = st.lastUserMessages === 0;
  const newMsgs = userMessages - st.lastUserMessages;
  const newWrites = writes - st.lastWrites;
  if (!first && newMsgs < LEARN_EVERY_MESSAGES && newWrites < LEARN_EVERY_WRITES) return;

  const lock = path.join(dir, `${sessionId}.learn.lock`);
  if (lockFresh(lock)) return; // a learner is still in flight

  fs.writeFileSync(stateFile, JSON.stringify({ lastUserMessages: userMessages, lastWrites: writes }));

  if (dryRun) {
    process.stdout.write(JSON.stringify({
      superskills_learn: 'spawn',
      trigger: first ? 'first' : 'cursor',
      userMessages,
      writes,
      reason: LEARN_INSTRUCTION,
    }));
    return;
  }

  try { fs.writeFileSync(lock, new Date().toISOString()); } catch { /* best effort */ }
  spawnLearner(root, buildChildPrompt(buildReplay(transcript)), path.join(dir, `${sessionId}.learn.log`));
}

try { main(); } catch { /* never block the stop on our own errors */ }
process.exit(0);

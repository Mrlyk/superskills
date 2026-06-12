#!/usr/bin/env node
'use strict';
// superskills SessionStart hook.
// Injects the project's learnings index and freshness reminders.
// Silent (exit 0, no output) when there is nothing useful to say.

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const MAX_INDEX_CHARS = 4000;
const STALE_COMMITS = 30;

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

function git(root, args) {
  try {
    return execFileSync('git', ['-C', root, ...args], {
      encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 5000,
    }).trim();
  } catch { return null; }
}

// Number of commits since a file last changed; null when untracked/unknown.
function commitsSince(root, relFile) {
  const last = git(root, ['log', '-1', '--format=%H', '--', relFile]);
  if (!last) return null;
  const count = git(root, ['rev-list', '--count', `${last}..HEAD`]);
  return count === null ? null : parseInt(count, 10);
}

function looksLikeProject(root) {
  const markers = ['package.json', 'pyproject.toml', 'go.mod', 'Cargo.toml',
    'pom.xml', 'build.gradle', 'build.gradle.kts', 'Gemfile', 'composer.json'];
  return markers.some((m) => fs.existsSync(path.join(root, m)))
    || fs.existsSync(path.join(root, 'src'));
}

function main() {
  let input = {};
  try { input = JSON.parse(readStdin()); } catch { /* tolerate bad input */ }
  const cwd = input.cwd || process.cwd();
  const root = findGitRoot(cwd);
  if (!root) return; // not a project, stay silent

  const parts = [];
  const conventions = path.join(root, '.superskills', 'conventions.md');
  const indexFile = path.join(root, '.superskills', 'learnings', 'INDEX.md');
  const hasAgentsMd = fs.existsSync(path.join(root, 'AGENTS.md'));
  const hasClaudeMd = fs.existsSync(path.join(root, 'CLAUDE.md'));

  if (fs.existsSync(indexFile)) {
    let index = fs.readFileSync(indexFile, 'utf8').trim();
    if (index && index.split('\n').some((l) => l.trim().startsWith('-'))) {
      if (index.length > MAX_INDEX_CHARS) {
        index = index.slice(0, MAX_INDEX_CHARS) + '\n[index truncated]';
      }
      parts.push(
        'Past learnings for this project (from .superskills/learnings/; '
        + 'read a linked file before relying on it):\n' + index,
      );
    }
  }

  if (fs.existsSync(conventions)) {
    const drift = commitsSince(root, '.superskills/conventions.md');
    if (drift !== null && drift > STALE_COMMITS) {
      parts.push(
        `.superskills/conventions.md is ${drift} commits behind HEAD; `
        + 'suggest running the ss-discover skill to refresh it when convenient.',
      );
    }
  } else if (!hasAgentsMd && !hasClaudeMd && looksLikeProject(root)) {
    parts.push(
      'This project has no AGENTS.md/CLAUDE.md/.superskills specs. '
      + 'Suggest running the ss-discover skill once to generate minimal conventions.',
    );
  }

  if (parts.length === 0) return;
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'SessionStart',
      additionalContext: parts.join('\n\n'),
    },
  }));
}

try { main(); } catch { /* never break the session */ }
process.exit(0);

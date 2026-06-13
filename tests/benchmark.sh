#!/usr/bin/env bash
# Smoke benchmark: drives an actual `claude -p` session against a throwaway
# fixture project and asserts that the core skills produce their artifacts.
# For the full A/B capability benchmark, see tests/bench/run.sh.
#
# Requirements: claude CLI logged in, superskills plugin installed.
# Cost note: makes 2 real model calls. Override the model with BENCH_MODEL.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL="${BENCH_MODEL:-sonnet}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1" >&2; }

if ! command -v claude >/dev/null 2>&1; then
  echo "claude CLI not found; skipping benchmark." >&2
  exit 0
fi
if ! claude plugin list 2>/dev/null | grep -q superskills; then
  echo "superskills plugin not installed; run:" >&2
  echo "  claude plugin marketplace add Mrlyk/superskills && claude plugin install superskills@superskills" >&2
  exit 1
fi

# Fixture: a small but realistic node project with evidenced conventions.
FIX="$TMP/fixture"
mkdir -p "$FIX/src" "$FIX/test"
cat > "$FIX/package.json" <<'EOF'
{
  "name": "fixture-app",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "node --test",
    "lint": "eslint src/"
  }
}
EOF
cat > "$FIX/src/order.js" <<'EOF'
export function totalCents(items) {
  if (!Array.isArray(items)) throw new TypeError('items must be an array');
  return items.reduce((sum, it) => sum + it.priceCents * it.qty, 0);
}
EOF
cat > "$FIX/test/order.test.js" <<'EOF'
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { totalCents } from '../src/order.js';

test('totalCents sums price * qty', () => {
  assert.equal(totalCents([{ priceCents: 100, qty: 2 }]), 200);
});
EOF
cat > "$FIX/eslint.config.js" <<'EOF'
export default [{ rules: { 'no-var': 'error', 'prefer-const': 'error' } }];
EOF
git -C "$FIX" init -q
git -C "$FIX" config user.email bench@local
git -C "$FIX" config user.name bench
git -C "$FIX" add -A
git -C "$FIX" commit -qm "feat: initial fixture app"

# Scoped permissions only: edits auto-accepted inside the fixture, plus a
# read-only Bash allowlist for the commands the skills legitimately need.
run_claude() { # prompt
  (cd "$FIX" && claude -p "$1" \
    --model "$MODEL" \
    --permission-mode acceptEdits \
    --allowedTools "Read,Glob,Grep,Write,Edit,Skill,Bash(git log:*),Bash(git diff:*),Bash(git status:*),Bash(ls:*),Bash(cat:*),Bash(head:*),Bash(wc:*),Bash(find:*),Bash(mkdir:*)" \
    --max-turns 40 2>&1)
}

echo "== benchmark 1: discover generates minimal specs =="
out="$(run_claude 'Invoke the superskills:discover skill for this project and follow it exactly.')"
echo "$out" | tail -3 | sed 's/^/  claude: /'

[[ -f "$FIX/.superskills/conventions.md" ]] && ok "conventions.md generated" || fail "conventions.md missing"
[[ -f "$FIX/AGENTS.md" ]] && ok "AGENTS.md generated" || fail "AGENTS.md missing"
[[ -f "$FIX/CLAUDE.md" ]] && ok "CLAUDE.md generated" || fail "CLAUDE.md missing"
[[ -f "$FIX/.superskills/learnings/INDEX.md" ]] && ok "learnings INDEX created" || fail "learnings INDEX missing"

if [[ -f "$FIX/.superskills/conventions.md" ]]; then
  lines="$(wc -l < "$FIX/.superskills/conventions.md" | tr -d ' ')"
  if [[ "$lines" -le 100 ]]; then ok "conventions stay minimal ($lines lines)"; else fail "conventions too long ($lines lines)"; fi
  conv="$(cat "$FIX/.superskills/conventions.md")"
  [[ "$conv" == *"node --test"* ]] && ok "real test command discovered" || fail "test command not discovered"
fi
if [[ -f "$FIX/CLAUDE.md" ]]; then
  grep -q '@AGENTS.md' "$FIX/CLAUDE.md" && ok "CLAUDE.md imports AGENTS.md" || fail "CLAUDE.md missing @AGENTS.md"
  grep -q '@.superskills/conventions.md' "$FIX/CLAUDE.md" && ok "CLAUDE.md imports conventions" || fail "CLAUDE.md missing conventions import"
fi

echo "== benchmark 2: learn persists a correction =="
out="$(run_claude 'Earlier in this project I corrected you twice: (1) always use pnpm here, never npm, because the lockfile is pnpm-lock.yaml on CI; (2) money is always integer cents in this codebase, never floats. Invoke the superskills:learn skill and persist whatever qualifies.')"
echo "$out" | tail -3 | sed 's/^/  claude: /'

entries="$(find "$FIX/.superskills/learnings" -name '*.md' ! -name 'INDEX.md' 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$entries" -ge 1 ]]; then ok "learning entries written ($entries)"; else fail "no learning entries written"; fi
if [[ -f "$FIX/.superskills/learnings/INDEX.md" ]]; then
  idx="$(cat "$FIX/.superskills/learnings/INDEX.md")"
  [[ "$idx" == *"pnpm"* ]] && ok "INDEX references the pnpm correction" || fail "INDEX missing pnpm entry"
fi

echo "== benchmark 3: injected index reaches a fresh session =="
out="$(printf '{"session_id":"bench","source":"startup","cwd":"%s"}' "$FIX" \
  | node "$REPO_DIR/plugins/superskills/hooks/session-start.js")"
[[ "$out" == *"pnpm"* ]] && ok "session-start injects the learning index" || fail "session-start did not inject index"

echo
echo "benchmark: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]

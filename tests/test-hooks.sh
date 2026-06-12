#!/usr/bin/env bash
# Unit tests for hooks/*.js — runs the real scripts against fixture transcripts.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export SUPERSKILLS_STATE_DIR="$TMP/state"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1" >&2; }

assert_contains() { # desc haystack needle
  if [[ "$2" == *"$3"* ]]; then ok "$1"; else fail "$1 (missing: $3; got: ${2:0:200})"; fi
}
assert_empty() { # desc value
  if [[ -z "$2" ]]; then ok "$1"; else fail "$1 (expected empty; got: ${2:0:200})"; fi
}

make_repo() { # path
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.email t@t.local
  git -C "$1" config user.name t
}

# Transcript with N real user messages; optionally an Edit tool_use line.
make_transcript() { # file n_user with_edit
  local file="$1" n="$2" with_edit="$3"
  : > "$file"
  for ((i=1; i<=n; i++)); do
    echo '{"type":"user","message":{"role":"user","content":"user message '"$i"'"}}' >> "$file"
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"reply"}]}}' >> "$file"
  done
  if [[ "$with_edit" == yes ]]; then
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"a.js"}}]}}' >> "$file"
  fi
  # tool_result arriving as type:user must not count as a user message
  echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"done"}]}}' >> "$file"
}

run_stop() { # session transcript cwd [active]
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","stop_hook_active":%s}' \
    "$1" "$2" "$3" "${4:-false}" | node "$REPO_DIR/hooks/stop-learn.js"
}

run_session_start() { # cwd
  printf '{"session_id":"s","source":"startup","cwd":"%s"}' "$1" \
    | node "$REPO_DIR/hooks/session-start.js"
}

echo "== stop-learn.js =="
REPO="$TMP/proj"; make_repo "$REPO"

T="$TMP/t-qualify.jsonl"; make_transcript "$T" 6 yes
out="$(run_stop sess-1 "$T" "$REPO")"
assert_contains "qualifying session triggers learn" "$out" '"decision":"block"'
assert_contains "reason mentions learnings dir" "$out" '.superskills/learnings/'

out="$(run_stop sess-1 "$T" "$REPO")"
assert_empty "same session never triggers twice" "$out"

out="$(run_stop sess-2 "$T" "$REPO" true)"
assert_empty "stop_hook_active suppresses trigger" "$out"

T2="$TMP/t-short.jsonl"; make_transcript "$T2" 2 yes
out="$(run_stop sess-3 "$T2" "$REPO")"
assert_empty "short session does not trigger" "$out"

T3="$TMP/t-noedit.jsonl"; make_transcript "$T3" 8 no
out="$(run_stop sess-4 "$T3" "$REPO")"
assert_empty "read-only session does not trigger" "$out"

NOGIT="$TMP/nogit"; mkdir -p "$NOGIT"
out="$(run_stop sess-5 "$T" "$NOGIT")"
assert_empty "non-git cwd does not trigger" "$out"

out="$(echo 'not json' | node "$REPO_DIR/hooks/stop-learn.js")"
assert_empty "malformed stdin is silent" "$out"

echo "== session-start.js =="
LEARNED="$TMP/learned"; make_repo "$LEARNED"
mkdir -p "$LEARNED/.superskills/learnings"
printf '# Learnings\n- [Use pnpm](2026-01-01-use-pnpm.md) - package installs\n' \
  > "$LEARNED/.superskills/learnings/INDEX.md"
out="$(run_session_start "$LEARNED")"
assert_contains "injects learnings index" "$out" "Use pnpm"
assert_contains "labels the injection" "$out" "Past learnings"

BARE="$TMP/bare"; make_repo "$BARE"
echo '{"name":"x"}' > "$BARE/package.json"
out="$(run_session_start "$BARE")"
assert_contains "bare project suggests ss-discover" "$out" "ss-discover"

out="$(run_session_start "$NOGIT")"
assert_empty "non-git cwd stays silent" "$out"

WITHMD="$TMP/withmd"; make_repo "$WITHMD"
echo '{"name":"x"}' > "$WITHMD/package.json"
echo '# agents' > "$WITHMD/AGENTS.md"
out="$(run_session_start "$WITHMD")"
assert_empty "project with AGENTS.md gets no suggestion" "$out"

STALE="$TMP/stale"; make_repo "$STALE"
mkdir -p "$STALE/.superskills"
echo '# conventions' > "$STALE/.superskills/conventions.md"
git -C "$STALE" add -A; git -C "$STALE" commit -qm "add conventions"
for i in $(seq 1 31); do git -C "$STALE" commit -q --allow-empty -m "c$i"; done
out="$(run_session_start "$STALE")"
assert_contains "stale conventions suggest refresh" "$out" "behind HEAD"

FRESH="$TMP/fresh"; make_repo "$FRESH"
mkdir -p "$FRESH/.superskills"
echo '# conventions' > "$FRESH/.superskills/conventions.md"
git -C "$FRESH" add -A; git -C "$FRESH" commit -qm "add conventions"
out="$(run_session_start "$FRESH")"
assert_empty "fresh conventions stay silent" "$out"

echo
echo "hooks: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]

#!/usr/bin/env bash
# Regenerate the frozen arm-B spec fixtures by running the REAL discover skill
# once per fixture, then freezing its output into fixtures/*-specs/.
# Frozen output keeps benchmark runs deterministic and cheap.
set -euo pipefail

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL="${BENCH_MODEL:-sonnet}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ALLOWED="Read,Glob,Grep,Write,Edit,Skill,Bash(git log:*),Bash(git status:*),Bash(ls:*),Bash(cat:*),Bash(head:*),Bash(wc:*),Bash(find:*),Bash(mkdir:*)"

freeze() { # fixture specsDir
  local fixture="$1" specs="$2"
  local dir="$WORK/$(basename "$fixture")"
  mkdir -p "$dir"
  cp -R "$BENCH_DIR/fixtures/$fixture/." "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email bench@local
  git -C "$dir" config user.name bench
  git -C "$dir" add -A
  git -C "$dir" commit -qm "feat: initial app"

  (cd "$dir" && claude -p 'Invoke the superskills:discover skill for this project and follow it exactly.' \
    --model "$MODEL" --permission-mode acceptEdits \
    --allowedTools "$ALLOWED" --max-turns 40) >/dev/null 2>&1 || true

  [[ -f "$dir/.superskills/conventions.md" ]] || { echo "discover failed for $fixture" >&2; exit 1; }
  rm -rf "$BENCH_DIR/fixtures/$specs"
  mkdir -p "$BENCH_DIR/fixtures/$specs"
  cp -R "$dir/.superskills" "$BENCH_DIR/fixtures/$specs/.superskills"
  cp "$dir/AGENTS.md" "$dir/CLAUDE.md" "$BENCH_DIR/fixtures/$specs/"
  echo "frozen: fixtures/$specs ($(wc -l < "$dir/.superskills/conventions.md" | tr -d ' ') conventions lines)"
}

TARGET="${1:-all}"
[[ "$TARGET" == all || "$TARGET" == store ]] && freeze store store-specs
[[ "$TARGET" == all || "$TARGET" == pyfix ]] && freeze pyfix pyfix-specs
exit 0

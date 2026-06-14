#!/usr/bin/env bash
# Clarify-nudge micro-benchmark.
#
# The existing A/B suite uses fixed fixtures and never runs discover, so it is
# blind to what discover writes into AGENTS.md. This measures exactly that: does
# the clarify pointer discover adds to AGENTS.md (loaded every session via the
# CLAUDE.md @import) make the model AUTO-trigger clarify on an ambiguous request
# — without anyone saying "apply the clarify skill" — and NOT over-ask on a clear
# one? The nudge text is read straight from the shipped discover SKILL.md, so the
# benchmark always tests what we ship.
#
# Arms (all see the clarify skill; the variable is the nudge + task):
#   base-ambiguous  : AGENTS.md without the nudge  + ambiguous task  (baseline lift)
#   nudge-ambiguous : AGENTS.md with the nudge     + ambiguous task  (lift)
#   nudge-clear     : AGENTS.md with the nudge     + clear task      (over-ask guard)
#
#   tests/bench/clarify-nudge.sh [--trials 3] [--model M] [--concurrency C] [--no-baseline]
set -uo pipefail

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$BENCH_DIR/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/plugins/superskills"
MODEL="${BENCH_MODEL:-sonnet}"
TRIALS=3
CONC=3
ARMS="base-ambiguous nudge-ambiguous nudge-clear"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --trials) TRIALS="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --concurrency) CONC="$2"; shift 2 ;;
    --no-baseline) ARMS="nudge-ambiguous nudge-clear"; shift ;;  # baseline is nudge-invariant
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

WORK="$(mktemp -d)"
if [[ "${BENCH_KEEP:-0}" != 1 ]]; then trap 'rm -rf "$WORK"' EXIT; fi
echo "work dir: $WORK"
mkdir -p "$BENCH_DIR/results"
RESULTS="$BENCH_DIR/results/clarify-nudge-results.jsonl"
: > "$RESULTS"
ALLOWED="Read,Glob,Grep,Write,Edit,MultiEdit,Skill,TodoWrite,Bash(node:*),Bash(pnpm:*),Bash(npm:*),Bash(git:*),Bash(ls:*),Bash(cat:*),Bash(mkdir:*)"
throttle() { while (( $(jobs -rp | wc -l) >= CONC )); do sleep 2; done; }

# The shipped clarify pointer, read from discover SKILL.md (node = RTK-safe).
NUDGE="$(node -e '
const fs = require("fs");
const lines = fs.readFileSync(process.argv[1], "utf8").split("\n");
const l = lines.find((x) => /clarify skill/i.test(x) && /^\s*-\s/.test(x)) || "";
process.stdout.write(l.replace(/^\s*-\s*`?/, "").replace(/`?\s*$/, ""));
' "$PLUGIN_DIR/skills/discover/SKILL.md")"
if [[ -z "$NUDGE" ]]; then echo "FATAL: could not extract clarify nudge from discover SKILL.md" >&2; exit 1; fi
echo "nudge: ${NUDGE:0:90}..."

# Ambiguous: format/fields genuinely undecided. Clear: fully specified, asking would be over-asking.
AMBIG_TASK='Add an export feature for orders so users can download their order history.'
CLEAR_TASK='Add a function sumCents(items) in src/sum.js (ESM) that returns the integer sum of item.priceCents across the items array and returns 0 for an empty array. Add a node:test in test/sum.test.js covering the empty array and a two-item array, and make the test suite pass.'

make_fixture() { # dir arm
  local dir="$1" arm="$2"
  mkdir -p "$dir"
  cp -R "$BENCH_DIR/fixtures/store/." "$dir"
  cp -R "$BENCH_DIR/fixtures/store-specs/." "$dir"
  mkdir -p "$dir/.claude/skills"
  cp -R "$PLUGIN_DIR/skills/clarify" "$dir/.claude/skills/clarify"
  # Nudge arms carry the shipped clarify pointer in AGENTS.md; baseline does not.
  if [[ "$arm" == nudge-* ]]; then
    printf '%s\n' "- ${NUDGE}" >> "$dir/AGENTS.md"
  fi
  git -C "$dir" init -q
  git -C "$dir" config user.email bench@local
  git -C "$dir" config user.name bench
  git -C "$dir" add -A
  git -C "$dir" commit -qm "chore: fixture base"
}

run_arm() { # arm trial
  local arm="$1" n="$2" dir="$WORK/$arm-$n" task type
  if [[ "$arm" == *-clear ]]; then task="$CLEAR_TASK"; type=clear; else task="$AMBIG_TASK"; type=ambiguous; fi
  make_fixture "$dir" "$arm"
  (cd "$dir" && claude -p "$task" \
    --model "$MODEL" --permission-mode acceptEdits \
    --allowedTools "$ALLOWED" --max-turns 8) > "$dir/.response.txt" 2>&1 || true
  node "$BENCH_DIR/graders/clarify-nudge.js" "$dir" "$dir/.response.txt" "$arm" "$type" >> "$RESULTS"
  echo "  done: arm=$arm trial=$n $(tail -1 "$RESULTS" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{const r=JSON.parse(s);console.log('asked='+r.asked+' code='+r.wroteCode+' score='+r.score.toFixed(2))})")"
}

echo "clarify-nudge: model=$MODEL trials=$TRIALS arms=[$ARMS]"
for arm in $ARMS; do
  for n in $(seq 1 "$TRIALS"); do
    throttle; run_arm "$arm" "$n" &
  done
done
wait

echo
echo "=== summary ==="
node -e '
const fs = require("fs");
const rows = fs.readFileSync(process.argv[1], "utf8").trim().split("\n").filter(Boolean).map(JSON.parse);
const arms = [...new Set(rows.map((r) => r.arm))];
for (const arm of arms) {
  const a = rows.filter((r) => r.arm === arm);
  const askRate = a.filter((r) => r.asked).length + "/" + a.length;
  const codeRate = a.filter((r) => r.wroteCode).length + "/" + a.length;
  const mean = (100 * a.reduce((s, r) => s + r.score, 0) / a.length).toFixed(0);
  console.log(arm.padEnd(16), "score=" + mean + "%  asked=" + askRate + "  wroteCode=" + codeRate);
}
' "$RESULTS"

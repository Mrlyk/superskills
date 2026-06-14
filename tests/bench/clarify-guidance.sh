#!/usr/bin/env bash
# Change-2 benchmark: does the AGENTS.md "don't guess — clarify" directive that
# Discover writes make the model SELF-TRIGGER clarification on an ambiguous task,
# without being told to use the clarify skill?
#
# Both arms get the SAME fixture, the SAME ambiguous task, and an AGENTS.md (via
# CLAUDE.md @import). The ONLY difference: arm B's AGENTS.md carries the clarify
# directive; arm A's does not. Graded by the s3 grader (asked a load-bearing
# question + wrote no premature code).
#
#   tests/bench/clarify-guidance.sh [--trials 3] [--model M] [--concurrency C]
set -uo pipefail

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$BENCH_DIR/../.." && pwd)"
MODEL="${BENCH_MODEL:-sonnet}"
TRIALS=3
CONC=3

while [[ $# -gt 0 ]]; do
  case "$1" in
    --trials) TRIALS="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --concurrency) CONC="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

WORK="$(mktemp -d)"
if [[ "${BENCH_KEEP:-0}" != 1 ]]; then trap 'rm -rf "$WORK"' EXIT; fi
echo "work dir: $WORK"
mkdir -p "$BENCH_DIR/results"
RESULTS="$BENCH_DIR/results/clarify-guidance-results.jsonl"
: > "$RESULTS"
ALLOWED="Read,Glob,Grep,Write,Edit,MultiEdit,Bash(ls:*),Bash(cat:*),Bash(git:*),Bash(node:*)"
throttle() { while (( $(jobs -rp | wc -l) >= CONC )); do sleep 2; done; }

TASK='Add the order export feature using the file format and column set our team standardized on.'

# Base AGENTS.md pointers shared by both arms (no clarify line).
BASE_AGENTS='# store-app

A small order/receipt store. Key commands: `npm test`.

- Read .superskills/conventions.md before writing code.'

# The exact directive Discover now writes (the variable under test).
CLARIFY_LINE='- If anything in a request is unclear, do not guess — proactively trigger the superskills clarify skill to ask before coding; when the request is already specific, just implement.'

make_fixture() { # dir arm
  local dir="$1" arm="$2"
  cp -R "$BENCH_DIR/fixtures/store/." "$dir"
  printf '@AGENTS.md\n' > "$dir/CLAUDE.md"
  if [[ "$arm" == B ]]; then
    printf '%s\n%s\n' "$BASE_AGENTS" "$CLARIFY_LINE" > "$dir/AGENTS.md"
  else
    printf '%s\n' "$BASE_AGENTS" > "$dir/AGENTS.md"
  fi
  git -C "$dir" init -q
  git -C "$dir" config user.email bench@local
  git -C "$dir" config user.name bench
  git -C "$dir" add -A
  git -C "$dir" commit -qm "chore: fixture base"
}

run_arm() { # arm trial
  local arm="$1" n="$2" dir="$WORK/$arm-$n"
  make_fixture "$dir" "$arm"
  local head0; head0="$(git -C "$dir" rev-parse HEAD)"
  (cd "$dir" && claude -p "$TASK" \
    --model "$MODEL" --permission-mode acceptEdits \
    --allowedTools "$ALLOWED" --max-turns 12) > "$dir/.response.txt" 2>&1 || true
  node "$BENCH_DIR/graders/s3.js" "$dir" "$dir/.response.txt" "$head0" \
    | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{const g=JSON.parse(s);process.stdout.write(JSON.stringify({arm:'$arm',trial:$n,checks:g.checks,score:g.score})+'\n')})" >> "$RESULTS"
  echo "  done: arm=$arm trial=$n score=$(tail -1 "$RESULTS" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>console.log(JSON.parse(s).score.toFixed(2)))")"
}

echo "clarify-guidance (AGENTS.md directive): model=$MODEL trials=$TRIALS"
for arm in A B; do
  for n in $(seq 1 "$TRIALS"); do
    throttle; run_arm "$arm" "$n" &
  done
done
wait

echo
echo "=== summary (arm A = no directive, arm B = with directive) ==="
node -e '
const fs=require("fs");
const rows=fs.readFileSync(process.argv[1],"utf8").trim().split("\n").filter(Boolean).map(JSON.parse);
for(const arm of ["A","B"]){
  const a=rows.filter(r=>r.arm===arm); if(!a.length) continue;
  const mean=a.reduce((s,r)=>s+r.score,0)/a.length;
  const keys=Object.keys(a[0].checks);
  const per=keys.map(k=>k+"="+a.filter(r=>r.checks[k]).length+"/"+a.length).join("  ");
  console.log((arm==="A"?"A no-directive":"B directive ").padEnd(14),"mean="+(100*mean).toFixed(0)+"%   "+per);
}
' "$RESULTS"

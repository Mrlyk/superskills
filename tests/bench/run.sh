#!/usr/bin/env bash
# A/B benchmark: pure model (arm A) vs superskills (arm B), real model runs.
#
#   tests/bench/run.sh [--trials N] [--model M] [--scenarios s1,s2,s3,s4,control]
#                      [--concurrency C]
#
# Prerequisites: claude CLI logged in, superskills plugin installed and
# enabled. Writes results/results.jsonl and results/report.md.
set -uo pipefail

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRIALS=3
MODEL="${BENCH_MODEL:-sonnet}"
SCENARIOS="s1,s2,s3,s4,control"
CONC=3

while [[ $# -gt 0 ]]; do
  case "$1" in
    --trials) TRIALS="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --scenarios) SCENARIOS="$2"; shift 2 ;;
    --concurrency) CONC="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

WORK="$(mktemp -d)"
# BENCH_KEEP=1 keeps per-trial fixtures and model responses for inspection.
if [[ "${BENCH_KEEP:-0}" != 1 ]]; then trap 'rm -rf "$WORK"' EXIT; fi
echo "work dir: $WORK"
RESULTS="$BENCH_DIR/results/results.jsonl"
mkdir -p "$BENCH_DIR/results"
: > "$RESULTS"

ALLOWED="Read,Glob,Grep,Write,Edit,MultiEdit,Skill,TodoWrite,Bash(node:*),Bash(npm:*),Bash(pnpm:*),Bash(git:*),Bash(ls:*),Bash(cat:*),Bash(mkdir:*),Bash(python3:*),Bash(wc:*),Bash(head:*),Bash(find:*)"

throttle() {
  while (( $(jobs -rp | wc -l) >= CONC )); do sleep 2; done
}

git_init_commit() { # dir
  git -C "$1" init -q
  git -C "$1" config user.email bench@local
  git -C "$1" config user.name bench
  git -C "$1" add -A
  git -C "$1" commit -qm "chore: fixture base"
}

prepare_store() { # dest scenario
  cp -R "$BENCH_DIR/fixtures/store/." "$1"
  # S2 isolates the memory channel: the learnings must be the only source.
  [[ "$2" == s2 ]] && rm -f "$1/CONTRIBUTING.md"
  git_init_commit "$1"
}

overlay() { # dir arm scenario
  local dir="$1" arm="$2" scenario="$3"
  if [[ "$arm" == A ]]; then
    printf '# store-app\n' > "$dir/CLAUDE.md"
  else
    case "$scenario" in
      s1|s4) cp -R "$BENCH_DIR/fixtures/store-specs/." "$dir" ;;
      s2)
        printf '# store-app\n' > "$dir/CLAUDE.md"
        mkdir -p "$dir/.superskills/learnings"
        cp "$BENCH_DIR/fixtures/store-learnings/"* "$dir/.superskills/learnings/"
        ;;
      s3) printf '# store-app\n' > "$dir/CLAUDE.md" ;; # variable is the skill alone
    esac
  fi
  git -C "$dir" add -A
  git -C "$dir" commit -qm "chore: arm overlay" >/dev/null 2>&1 || true
}

run_model() { # dir arm prompt outfile maxturns
  local dir="$1" arm="$2" prompt="$3" outfile="$4" maxturns="$5"
  local extra=()
  [[ "$arm" == A ]] && extra+=(--disallowedTools "Skill")
  # ${extra[@]+...} keeps bash 3.2 happy when the array is empty under set -u
  (cd "$dir" && claude -p "$prompt" \
    --model "$MODEL" \
    --permission-mode acceptEdits \
    --allowedTools "$ALLOWED" \
    ${extra[@]+"${extra[@]}"} \
    --max-turns "$maxturns") > "$outfile" 2>&1 || true
}

append_result() { # scenario arm trial gradeJsonFile durationSec
  node -e '
    const fs = require("fs");
    const [scenario, arm, trial, gradeFile, dur, results] = process.argv.slice(1);
    let grade = { checks: {}, score: 0 };
    try { grade = JSON.parse(fs.readFileSync(gradeFile, "utf8")); } catch {}
    fs.appendFileSync(results, JSON.stringify({
      scenario, arm, trial: Number(trial),
      checks: grade.checks, score: grade.score, durationSec: Number(dur),
    }) + "\n");
  ' "$1" "$2" "$3" "$4" "$5" "$RESULTS"
}

S1_TASK='Add a discount feature to this project: implement applyDiscount(items, percent) that returns the order total in cents after applying a percent discount. items have the shape {priceCents, qty}. Include input validation and tests.'
S2_TASK='Two things: (1) add a "Getting started" section to README.md showing how to install dependencies and run the tests; (2) implement src/receipt.js exporting makeReceipt(totalCents) that takes the total as a number and returns {id, createdAt, totalCents} where createdAt records when the receipt was created. Keep the test suite passing.'
S3_TASK='Add an export feature for orders so users can download their order history.'
S4_TASK_A='The applyCoupon feature in src/coupon.js was just developed (see the working tree). Write unit tests for it and make sure they pass.'
S4_TASK_B='The applyCoupon feature in src/coupon.js was just developed (see the working tree). Apply the superskills:test skill.'

trial_generic() { # scenario arm trial
  local scenario="$1" arm="$2" n="$3"
  local dir="$WORK/$scenario-$arm-$n"
  mkdir -p "$dir"
  prepare_store "$dir" "$scenario"
  overlay "$dir" "$arm" "$scenario"

  local prompt maxturns=30 head0=""
  case "$scenario" in
    s1) prompt="$S1_TASK" ;;
    s2) prompt="$S2_TASK" ;;
    s3)
      maxturns=25
      head0="$(git -C "$dir" rev-parse HEAD)"
      if [[ "$arm" == B ]]; then
        prompt="Apply the superskills:clarify skill to this request first, following it exactly. $S3_TASK"
      else
        prompt="$S3_TASK"
      fi
      ;;
    s4)
      cp "$BENCH_DIR/fixtures/staged/coupon.js" "$dir/src/coupon.js" # untracked: "just developed"
      if [[ "$arm" == B ]]; then prompt="$S4_TASK_B"; else prompt="$S4_TASK_A"; fi
      ;;
  esac

  local t0=$SECONDS
  run_model "$dir" "$arm" "$prompt" "$dir/.response.txt" "$maxturns"
  local dur=$((SECONDS - t0))

  local grade="$dir/.grade.json"
  if [[ "$scenario" == s3 ]]; then
    node "$BENCH_DIR/graders/s3.js" "$dir" "$dir/.response.txt" "$head0" > "$grade"
  else
    node "$BENCH_DIR/graders/$scenario.js" "$dir" > "$grade"
  fi
  append_result "$scenario" "$arm" "$n" "$grade" "$dur"
  echo "  done: $scenario arm=$arm trial=$n score=$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).score.toFixed(2))' "$grade")"
}

trial_control() { # arm problemIndex
  local arm="$1" i="$2"
  local dir="$WORK/control-$arm-$i"
  mkdir -p "$dir"
  cp -R "$BENCH_DIR/fixtures/pyfix/." "$dir"
  if [[ "$arm" == A ]]; then
    printf '# pyfix\n' > "$dir/CLAUDE.md"
  else
    cp -R "$BENCH_DIR/fixtures/pyfix-specs/." "$dir"
  fi
  git_init_commit "$dir"

  local pfile="$dir/.problem.json"
  node -e '
    const fs = require("fs");
    const [src, idx, out] = process.argv.slice(1);
    const lines = fs.readFileSync(src, "utf8").trim().split("\n");
    fs.writeFileSync(out, lines[Number(idx)]);
  ' "$BENCH_DIR/humaneval/problems.jsonl" "$i" "$pfile"
  local fnprompt
  fnprompt="$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).prompt)' "$pfile")"

  local prompt="Create solution.py in the project root implementing exactly this function. Keep the given signature and docstring behavior; include any imports it needs. Write only solution.py.

\`\`\`python
$fnprompt
\`\`\`"

  local t0=$SECONDS
  run_model "$dir" "$arm" "$prompt" "$dir/.response.txt" 12
  local dur=$((SECONDS - t0))

  local passed=false
  if [[ -f "$dir/solution.py" ]] \
    && python3 "$BENCH_DIR/humaneval/grade.py" "$pfile" "$dir/solution.py" >/dev/null 2>&1; then
    passed=true
  fi
  printf '{"checks":{"pass":%s},"score":%s}' "$passed" "$([[ $passed == true ]] && echo 1 || echo 0)" > "$dir/.grade.json"
  append_result control "$arm" "$i" "$dir/.grade.json" "$dur"
  echo "  done: control arm=$arm problem=$i pass=$passed"
}

echo "benchmark: model=$MODEL trials=$TRIALS scenarios=$SCENARIOS concurrency=$CONC"
IFS=',' read -ra SCEN_LIST <<< "$SCENARIOS"
for scenario in "${SCEN_LIST[@]}"; do
  echo "== $scenario =="
  if [[ "$scenario" == control ]]; then
    for arm in A B; do
      for i in $(seq 0 9); do
        throttle; trial_control "$arm" "$i" &
      done
    done
  else
    for arm in A B; do
      for n in $(seq 1 "$TRIALS"); do
        throttle; trial_generic "$scenario" "$arm" "$n" &
      done
    done
  fi
  wait
done

node "$BENCH_DIR/report.js" "$RESULTS" > "$BENCH_DIR/results/report.md"
echo
echo "report written to tests/bench/results/report.md"

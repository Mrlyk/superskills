#!/usr/bin/env bash
# Community benchmark, hard subset: HumanEval problems where the baseline
# model is not saturated, measured A/B (pure model vs superskills artifacts).
#
# Phase 1 (screen): run the BASELINE once over a pre-registered contiguous
#   range to find problems it fails. Selection uses baseline runs only and is
#   independent of the measurement runs (regression-to-the-mean then affects
#   both arms equally).
# Phase 2 (measure): run hard-set problems x {arm A, arm B} x --trials with
#   IDENTICAL prompts and turn budgets. Arm B differs only by the presence of
#   the superskills artifacts (discover-generated AGENTS.md/CLAUDE.md/
#   conventions) in the fixture. Canonical HumanEval check() grades both.
#
#   tests/bench/heval-hard.sh [--screen-range 100:163] [--trials 3]
#                             [--model M] [--concurrency C] [--rescreen]
set -uo pipefail

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$BENCH_DIR/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/plugins/superskills"
MODEL="${BENCH_MODEL:-sonnet}"
TRIALS=3
CONC=3
RANGE="100:163"
RESCREEN=0
HARD_OVERRIDE=""
APPEND=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --screen-range) RANGE="$2"; shift 2 ;;
    --trials) TRIALS="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --concurrency) CONC="$2"; shift 2 ;;
    --rescreen) RESCREEN=1; shift ;;
    --hard) HARD_OVERRIDE="$2"; shift 2 ;;   # measure these ids, skip screening
    --append) APPEND=1; shift ;;             # append to results instead of truncating
    --plus) PLUS=1; shift ;;                 # EvalPlus grading (HumanEval+)
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

PLUS="${PLUS:-0}"
if [[ "$PLUS" == 1 ]]; then
  DATA="$BENCH_DIR/humaneval/HumanEvalPlus.jsonl"
  [[ -f "$DATA" ]] || gunzip -kc "$BENCH_DIR/humaneval/HumanEvalPlus.jsonl.gz" > "$DATA"
  GRADER="$BENCH_DIR/humaneval/grade-plus.py"
  TAG="heval-plus"
else
  DATA="$BENCH_DIR/humaneval/HumanEval.jsonl"
  [[ -f "$DATA" ]] || gunzip -kc "$BENCH_DIR/humaneval/HumanEval.jsonl.gz" > "$DATA"
  GRADER="$BENCH_DIR/humaneval/grade.py"
  TAG="heval"
fi

WORK="$(mktemp -d)"
if [[ "${BENCH_KEEP:-0}" != 1 ]]; then trap 'rm -rf "$WORK"' EXIT; fi
echo "work dir: $WORK"
mkdir -p "$BENCH_DIR/results"
SCREEN="$BENCH_DIR/results/$TAG-screen.jsonl"
RESULTS="$BENCH_DIR/results/$TAG-results.jsonl"

ALLOWED="Read,Glob,Grep,Write,Edit,MultiEdit,Skill,TodoWrite,Bash(python3:*),Bash(python:*),Bash(ls:*),Bash(cat:*),Bash(git:*),Bash(mkdir:*),Bash(rm:*),Bash(chmod:*)"

throttle() { while (( $(jobs -rp | wc -l) >= CONC )); do sleep 2; done; }

extract_problem() { # index outfile
  node -e '
    const fs = require("fs");
    const [src, idx, out] = process.argv.slice(1);
    const lines = fs.readFileSync(src, "utf8").trim().split("\n");
    fs.writeFileSync(out, lines[Number(idx)]);
  ' "$DATA" "$1" "$2"
}

# Arm isolation, fully project-contained (no global plugin state):
# - Arm A runs with --bare (no hooks, no plugins, no user settings).
# - Arm B embeds superskills INSIDE the fixture: discover-generated specs,
#   the plugin's skills under .claude/skills/, and project-level
#   .claude/settings.json wiring the hooks by absolute path.
make_fixture() { # dir arm
  local dir="$1" arm="$2"
  mkdir -p "$dir"
  cp -R "$BENCH_DIR/fixtures/pyfix/." "$dir"
  if [[ "$arm" == A ]]; then
    printf '# pyfix\n' > "$dir/CLAUDE.md"
  else
    cp -R "$BENCH_DIR/fixtures/pyfix-specs/." "$dir"
    mkdir -p "$dir/.claude/skills"
    for s in learn discover clarify test; do
      cp -R "$PLUGIN_DIR/skills/$s" "$dir/.claude/skills/$s"
    done
    cat > "$dir/.claude/settings.json" <<EOF
{
  "hooks": {
    "SessionStart": [
      { "matcher": "startup|resume|clear",
        "hooks": [{ "type": "command", "command": "node \"$PLUGIN_DIR/hooks/session-start.js\"", "timeout": 10 }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "node \"$PLUGIN_DIR/hooks/stop-verify.js\"", "timeout": 15 }] },
      { "hooks": [{ "type": "command", "command": "node \"$PLUGIN_DIR/hooks/stop-learn.js\"", "timeout": 15 }] }
    ]
  }
}
EOF
  fi
  git -C "$dir" init -q
  git -C "$dir" config user.email bench@local
  git -C "$dir" config user.name bench
  git -C "$dir" add -A
  git -C "$dir" commit -qm "chore: fixture base"
}

# Identical prompt and turn budget for both arms; only the artifacts differ.
# Arm A: Skill disallowed, no superskills anywhere (the superskills plugin
#   must NOT be installed at user scope while this benchmark runs — its local
#   marketplace resolves to live repo files; --bare is unusable as it drops
#   auth). Arm B: superskills lives in the fixture's own .claude/.
run_one() { # dir arm problemFile outfile
  local dir="$1" arm="$2" pfile="$3" outfile="$4"
  local fnprompt extra=()
  fnprompt="$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).prompt)' "$pfile")"
  if [[ "$arm" == A ]]; then
    extra+=(--disallowedTools "Skill")
  fi
  (cd "$dir" && claude -p "Create solution.py in the project root implementing exactly this function. Keep the given signature and docstring behavior; include any imports it needs. The deliverable is solution.py.

\`\`\`python
$fnprompt
\`\`\`" \
    --model "$MODEL" \
    --permission-mode acceptEdits \
    --allowedTools "$ALLOWED" \
    ${extra[@]+"${extra[@]}"} \
    --max-turns 24) > "$outfile" 2>&1 || true
}

grade_one() { # dir problemFile -> echoes true/false
  if [[ -f "$1/solution.py" ]] \
    && python3 "$GRADER" "$2" "$1/solution.py" >/dev/null 2>&1; then
    echo true
  else
    echo false
  fi
}

screen_one() { # index
  local i="$1" dir="$WORK/screen-$1"
  make_fixture "$dir" A
  local pfile="$dir/.problem.json"
  extract_problem "$i" "$pfile"
  local t0=$SECONDS
  run_one "$dir" A "$pfile" "$dir/.response.txt"
  local pass; pass="$(grade_one "$dir" "$pfile")"
  printf '{"problem":%s,"pass":%s,"durationSec":%s}\n' "$i" "$pass" "$((SECONDS - t0))" >> "$SCREEN"
  echo "  screen: problem=$i pass=$pass"
}

measure_one() { # index arm trial
  local i="$1" arm="$2" n="$3" dir="$WORK/m-$1-$2-$3"
  make_fixture "$dir" "$arm"
  local pfile="$dir/.problem.json"
  extract_problem "$i" "$pfile"
  local t0=$SECONDS
  run_one "$dir" "$arm" "$pfile" "$dir/.response.txt"
  local pass; pass="$(grade_one "$dir" "$pfile")"
  local score=0; [[ "$pass" == true ]] && score=1
  printf '{"scenario":"heval_hard","arm":"%s","trial":%s,"problem":%s,"checks":{"pass":%s},"score":%s,"durationSec":%s}\n' \
    "$arm" "$n" "$i" "$pass" "$score" "$((SECONDS - t0))" >> "$RESULTS"
  echo "  done: problem=$i arm=$arm trial=$n pass=$pass"
}

IFS=':' read -r LO HI <<< "$RANGE"

if [[ -n "$HARD_OVERRIDE" ]]; then
  HARD=($HARD_OVERRIDE)
else
  if [[ "$RESCREEN" == 1 || ! -s "$SCREEN" ]]; then
    : > "$SCREEN"
    echo "== phase 1: screening baseline on HumanEval/$LO..$HI (model=$MODEL) =="
    for i in $(seq "$LO" "$HI"); do
      throttle; screen_one "$i" &
    done
    wait
  fi
  HARD=($(node -e '
    const fs = require("fs");
    const rows = fs.readFileSync(process.argv[1], "utf8").trim().split("\n").map(JSON.parse);
    console.log(rows.filter(r => !r.pass).map(r => r.problem).sort((a,b)=>a-b).join(" "));
  ' "$SCREEN"))
fi
echo "hard set: ${HARD[*]:-none}"
if [[ "${#HARD[@]}" -eq 0 ]]; then
  echo "baseline saturated the screened range; widen --screen-range." >&2
  exit 1
fi

echo "== phase 2: measuring ${#HARD[@]} problems x 2 arms x $TRIALS trials =="
[[ "$APPEND" == 1 ]] || : > "$RESULTS"
for i in "${HARD[@]}"; do
  for arm in A B; do
    for n in $(seq 1 "$TRIALS"); do
      throttle; measure_one "$i" "$arm" "$n" &
    done
  done
done
wait

node "$BENCH_DIR/report-heval.js" "$RESULTS" "$SCREEN" > "$BENCH_DIR/results/$TAG-report.md"
echo
echo "report written to tests/bench/results/$TAG-report.md"

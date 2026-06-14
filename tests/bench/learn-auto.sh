#!/usr/bin/env bash
# Auto-learning generation benchmark — the blind spot S2 never covered.
#
# S2 measures whether the model USES learnings that already exist. This
# measures whether stop-learn AUTO-GENERATES them: given a finished session
# containing project decisions the code cannot show, does the Stop hook's
# injected instruction make the model persist the right learnings?
#
# Both arms see the identical session replay (with two explicit corrections).
# The only difference: arm B appends the REAL block reason emitted by
# plugins/superskills/hooks/stop-learn.js; arm A appends a neutral close.
# Grading inspects the .superskills/learnings/ the model actually wrote.
#
#   tests/bench/learn-auto.sh [--trials 3] [--model M] [--concurrency C]
set -uo pipefail

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$BENCH_DIR/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/plugins/superskills"
MODEL="${BENCH_MODEL:-sonnet}"
TRIALS=3
CONC=3
MODE=standard

while [[ $# -gt 0 ]]; do
  case "$1" in
    --trials) TRIALS="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --concurrency) CONC="$2"; shift 2 ;;
    --hard) MODE=hard; shift ;;   # round 2: precision under noise
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

WORK="$(mktemp -d)"
if [[ "${BENCH_KEEP:-0}" != 1 ]]; then trap 'rm -rf "$WORK"' EXIT; fi
echo "work dir: $WORK"
mkdir -p "$BENCH_DIR/results"
RESULTS="$BENCH_DIR/results/learn-auto-$MODE-results.jsonl"
: > "$RESULTS"
ALLOWED="Read,Glob,Grep,Write,Edit,MultiEdit,Skill,Bash(ls:*),Bash(cat:*),Bash(mkdir:*),Bash(git:*)"
throttle() { while (( $(jobs -rp | wc -l) >= CONC )); do sleep 2; done; }

# Standard: two durable project decisions, stated only in this replay.
SESSION_REPLAY_STANDARD='The following development session just happened in THIS project (replayed for you verbatim):

[user] Add a makeReceipt(totalCents) function to src/receipt.js that returns an object with the total and a creation time.
[assistant] (wrote src/receipt.js using Date.now() for the time and returning the total as a float)
[user] Two corrections — both are project conventions you could not have known from the code: (1) timestamps in this codebase are ALWAYS ISO-8601 UTC strings produced with new Date().toISOString(), never epoch milliseconds, because our downstream analytics pipeline only parses ISO-8601 strings; (2) monetary amounts are ALWAYS integer cents, never floats. Please fix both.
[assistant] (fixed: createdAt now uses new Date().toISOString(); totalCents kept as an integer)
[user] Correct, that matches our conventions now. We are done with the coding task.'

# Hard: ONE durable team convention buried among TWO throwaway instructions
# that must NOT be persisted. Tests precision, not just recall.
SESSION_REPLAY_HARD='The following development session just happened in THIS project (replayed for you verbatim):

[user] Refactor src/order.js to pull the tax math into its own function.
[assistant] (extracted computeTax)
[user] For this one, just the quickest thing — skip input validation, I will add it myself later.
[assistant] (kept it minimal, no validation)
[user] Important: in this codebase every API error code MUST use the E_ prefix (E_RANGE, E_TYPE, and so on). It is a hard team convention enforced in code review and the error catalog depends on it. Make computeTax throw E_RANGE on a negative rate.
[assistant] (threw new AppError("E_RANGE", ...))
[user] Also, just for today, console.log the intermediate subtotal so I can watch it run — I will strip that before committing.
[assistant] (added a temporary console.log)
[user] Great, that works. We are done.'

if [[ "$MODE" == hard ]]; then SESSION_REPLAY="$SESSION_REPLAY_HARD"; else SESSION_REPLAY="$SESSION_REPLAY_STANDARD"; fi

# Real Stop-hook reason from the actual hook, driven by a qualifying transcript.
stop_reason() {
  local st="$WORK/reason-state"; mkdir -p "$st"
  local repo="$WORK/reason-repo"; mkdir -p "$repo"; git -C "$repo" init -q
  local t="$WORK/reason.jsonl"
  {
    local i
    for i in 1 2 3 4 5; do
      printf '{"type":"user","message":{"role":"user","content":"message %s"}}\n' "$i"
      printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ok"}]}}\n'
    done
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"src/receipt.js"}}]}}\n'
  } > "$t"
  SUPERSKILLS_STATE_DIR="$st" printf '{"session_id":"reason","transcript_path":"%s","cwd":"%s","stop_hook_active":false}' "$t" "$repo" \
    | SUPERSKILLS_STATE_DIR="$st" SUPERSKILLS_LEARN_DRYRUN=1 node "$PLUGIN_DIR/hooks/stop-learn.js" \
    | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>process.stdout.write(JSON.parse(s).reason))"
}
REASON="$(stop_reason)"

make_fixture() { # dir
  local dir="$1"
  cp -R "$BENCH_DIR/fixtures/store/." "$dir"
  mkdir -p "$dir/.claude/skills"
  cp -R "$PLUGIN_DIR/skills/learn" "$dir/.claude/skills/learn"
  git -C "$dir" init -q
  git -C "$dir" config user.email bench@local
  git -C "$dir" config user.name bench
  git -C "$dir" add -A
  git -C "$dir" commit -qm "chore: fixture base"
}

run_arm() { # arm trial
  local arm="$1" n="$2" dir="$WORK/$arm-$n"
  make_fixture "$dir"
  local prompt
  if [[ "$arm" == B ]]; then
    prompt="$SESSION_REPLAY

$REASON"
  else
    prompt="$SESSION_REPLAY

The session is complete. No further action is required."
  fi
  local extra=()
  [[ "$arm" == A ]] && extra+=(--disallowedTools "Skill")
  (cd "$dir" && claude -p "$prompt" \
    --model "$MODEL" --permission-mode acceptEdits \
    --allowedTools "$ALLOWED" ${extra[@]+"${extra[@]}"} --max-turns 12) \
    > "$dir/.response.txt" 2>&1 || true

  node "$BENCH_DIR/graders/learn-auto.js" "$dir" "$arm" "$n" "$MODE" >> "$RESULTS"
  echo "  done: arm=$arm trial=$n score=$(tail -1 "$RESULTS" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>console.log(JSON.parse(s).score.toFixed(2)))")"
}

echo "auto-learning generation: model=$MODEL trials=$TRIALS"
for arm in A B; do
  for n in $(seq 1 "$TRIALS"); do
    throttle; run_arm "$arm" "$n" &
  done
done
wait

node "$BENCH_DIR/report-learn-auto.js" "$RESULTS" "$MODE" > "$BENCH_DIR/results/learn-auto-$MODE-report.md"
echo
cat "$BENCH_DIR/results/learn-auto-$MODE-report.md"

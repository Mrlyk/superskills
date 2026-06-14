#!/usr/bin/env bash
# Wiki-vs-flat accumulation benchmark. The knowledge base already holds 3 topics
# (timestamps, money, error codes). A new session adds a 4th learning that
# EXTENDS the timestamps topic (filename timestamp format). The flat arm
# (dated files + INDEX.md, real stop-learn reason) scatters it into a new file;
# the wiki arm (topic pages + index.md/log.md, wiki reason) merges it into
# timestamps.md. Grades capture, knowledge preservation, consolidation, dedup,
# and index upkeep.
#   tests/bench/learn-wiki.sh [--trials 3] [--model M] [--concurrency C]
set -uo pipefail

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$BENCH_DIR/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/plugins/superskills"
ACCUM="$BENCH_DIR/fixtures/learn-accum"
MODEL="${BENCH_MODEL:-sonnet}"
TRIALS=3
CONC=3
SCENARIO=accum   # accum = add to a 3-topic KB; simple = empty-KB bootstrap+recall

while [[ $# -gt 0 ]]; do
  case "$1" in
    --trials) TRIALS="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --concurrency) CONC="$2"; shift 2 ;;
    --simple) SCENARIO=simple; shift ;;
    --hard) SCENARIO=hard; shift ;;
    --accum) SCENARIO=accum; shift ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

WORK="$(mktemp -d)"
if [[ "${BENCH_KEEP:-0}" != 1 ]]; then trap 'rm -rf "$WORK"' EXIT; fi
echo "work dir: $WORK"
mkdir -p "$BENCH_DIR/results"
RESULTS="$BENCH_DIR/results/learn-wiki-$SCENARIO-results.jsonl"
: > "$RESULTS"
ALLOWED="Read,Glob,Grep,Write,Edit,MultiEdit,Skill,Bash(ls:*),Bash(cat:*),Bash(mkdir:*),Bash(git:*)"
throttle() { while (( $(jobs -rp | wc -l) >= CONC )); do sleep 2; done; }

SESSION_REPLAY_ACCUM='The following development session just happened in THIS project (replayed for you verbatim):

[user] Add a helper that builds a backup filename for an order export.
[assistant] (wrote it embedding new Date().toISOString() in the filename)
[user] One correction, and it is a project convention you could not infer from code: timestamps embedded in FILENAMES must use the compact form YYYYMMDD-HHmmss in UTC (no colons), because these files become S3 object keys and S3 keys cannot contain colons. (API responses still use full ISO-8601 UTC as before.) Please fix.
[assistant] (fixed to the compact colon-free UTC filename format)
[user] Correct, that matches our conventions. We are done.'

# Empty-KB recall+bootstrap: two unrelated corrections, no prior knowledge base.
SESSION_REPLAY_SIMPLE='The following development session just happened in THIS project (replayed for you verbatim):

[user] Add a makeReceipt(totalCents) function to src/receipt.js returning the total and a creation time.
[assistant] (wrote it using Date.now() for the time and a float total)
[user] Two corrections, both project conventions you could not infer from code: (1) timestamps are ALWAYS ISO-8601 UTC strings via new Date().toISOString(), never epoch milliseconds, because the analytics pipeline only parses ISO-8601; (2) monetary amounts are ALWAYS integer cents, never floats. Please fix both.
[assistant] (fixed: createdAt uses new Date().toISOString(); total kept as integer cents)
[user] Correct, that matches our conventions. We are done.'

# Precision under noise: ONE durable convention buried among TWO throwaways.
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

if [[ "$SCENARIO" == simple ]]; then SESSION_REPLAY="$SESSION_REPLAY_SIMPLE"
elif [[ "$SCENARIO" == hard ]]; then SESSION_REPLAY="$SESSION_REPLAY_HARD"
else SESSION_REPLAY="$SESSION_REPLAY_ACCUM"; fi

# Real flat Stop-hook reason, straight from the shipped hook.
flat_reason() {
  local st="$WORK/reason-state"; mkdir -p "$st"
  local repo="$WORK/reason-repo"; mkdir -p "$repo"; git -C "$repo" init -q
  local t="$WORK/reason.jsonl" i
  {
    for i in 1 2 3 4 5; do
      printf '{"type":"user","message":{"role":"user","content":"message %s"}}\n' "$i"
      printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ok"}]}}\n'
    done
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"src/x.js"}}]}}\n'
  } > "$t"
  printf '{"session_id":"r","transcript_path":"%s","cwd":"%s","stop_hook_active":false}' "$t" "$repo" \
    | SUPERSKILLS_STATE_DIR="$st" SUPERSKILLS_LEARN_DRYRUN=1 node "$PLUGIN_DIR/hooks/stop-learn.js" \
    | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>process.stdout.write(JSON.parse(s).reason))"
}
FLAT_REASON="$(flat_reason)"

read -r -d '' WIKI_REASON <<'EOF' || true
Before finishing, review this session for durable learnings: user corrections, pitfalls with fixes, or project decisions not visible in code. If none qualify, stop now without writing anything. Otherwise maintain the project knowledge wiki under the repository root (.superskills/learnings/, in the directory containing .git). It is organized as topic pages, not dated entries. For each learning: read index.md to find the topic page it belongs to, and merge the rule into that existing page — keep the page focused and deduplicated, cross-link related topics with [[topic]]. Only create a new <topic>.md page when no existing topic fits; never duplicate a rule that already lives on another page. Then ALWAYS update index.md so it lists every topic page with a one-line summary — index.md is the only file loaded into future sessions, so a page missing from it is invisible. Prefer editing an existing page over adding a file. Then stop.
EOF

make_fixture() { # dir arm
  local dir="$1" arm="$2"
  mkdir -p "$dir"
  cp -R "$BENCH_DIR/fixtures/store/." "$dir"
  rm -rf "$dir/.superskills" "$dir/.claude/skills/learn"
  mkdir -p "$dir/.claude/skills"
  # Seed the knowledge base (accum) or leave it empty for bootstrap (simple).
  if [[ "$SCENARIO" == accum ]]; then
    if [[ "$arm" == wiki ]]; then cp -R "$ACCUM/wiki/.superskills" "$dir/.superskills"
    else cp -R "$ACCUM/flat/.superskills" "$dir/.superskills"; fi
  fi
  # Per-arm learn skill.
  if [[ "$arm" == wiki ]]; then cp -R "$ACCUM/wiki-skill/learn" "$dir/.claude/skills/learn"
  else cp -R "$PLUGIN_DIR/skills/learn" "$dir/.claude/skills/learn"; fi
  git -C "$dir" init -q
  git -C "$dir" config user.email bench@local
  git -C "$dir" config user.name bench
  git -C "$dir" add -A
  git -C "$dir" commit -qm "chore: fixture base with seeded knowledge"
}

run_arm() { # arm trial
  local arm="$1" n="$2" dir="$WORK/$arm-$n" reason
  make_fixture "$dir" "$arm"
  if [[ "$arm" == wiki ]]; then reason="$WIKI_REASON"; else reason="$FLAT_REASON"; fi
  (cd "$dir" && claude -p "$SESSION_REPLAY

$reason" \
    --model "$MODEL" --permission-mode acceptEdits \
    --allowedTools "$ALLOWED" --max-turns 14) > "$dir/.response.txt" 2>&1 || true
  node "$BENCH_DIR/graders/learn-wiki.js" "$dir" "$arm" "$n" "$SCENARIO" >> "$RESULTS"
  echo "  done: arm=$arm trial=$n score=$(tail -1 "$RESULTS" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>console.log(JSON.parse(s).score.toFixed(2)))")"
}

echo "wiki-vs-flat accumulation: model=$MODEL trials=$TRIALS"
for arm in flat wiki; do
  for n in $(seq 1 "$TRIALS"); do
    throttle; run_arm "$arm" "$n" &
  done
done
wait

echo
echo "=== summary ==="
node -e '
const fs=require("fs");
const rows=fs.readFileSync(process.argv[1],"utf8").trim().split("\n").map(JSON.parse);
for(const arm of ["flat","wiki"]){
  const a=rows.filter(r=>r.arm===arm);
  if(!a.length) continue;
  const mean=a.reduce((s,r)=>s+r.score,0)/a.length;
  const keys=Object.keys(a[0].checks);
  const per=keys.map(k=>k+"="+a.filter(r=>r.checks[k]).length+"/"+a.length).join("  ");
  const cf=(a.reduce((s,r)=>s+r.contentFiles,0)/a.length).toFixed(1);
  console.log(arm.padEnd(5),"mean="+(100*mean).toFixed(0)+"%  contentFiles~"+cf+"\n      "+per);
}
' "$RESULTS"

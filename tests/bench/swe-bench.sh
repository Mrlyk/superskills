#!/usr/bin/env bash
# SWE-bench Lite, A/B (pure model vs superskills artifacts), real end-to-end.
#
# Per (instance, arm): check out the repo at base_commit into a throwaway dir,
# build a runnable venv (project installed editable, so the model can actually
# run tests), then run `claude -p` with the issue. Arm B differs only by the
# presence of superskills (.claude/ skills + the 3 hooks) in the checkout; those
# files are kept out of the extracted patch via .git/info/exclude. The model
# patch (git diff vs base_commit) is graded by the official swebench Docker
# harness (FAIL_TO_PASS + PASS_TO_PASS), unbiased and identical per arm. pass@1.
# Run multiple --tag passes and average for variance.
#
#   tests/bench/swe-bench.sh [--subset "id1 id2"] [--subset-file F]
#                            [--model M] [--arms "A B"] [--concurrency 2]
#                            [--tag swe] [--max-turns 50] [--no-eval] [--eval-only]
set -uo pipefail

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$BENCH_DIR/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/plugins/superskills"
SWE_DIR="$BENCH_DIR/swebench"
PY="$BENCH_DIR/.swebench-venv/bin/python"
UV="$(command -v uv)"
MODEL="${BENCH_MODEL:-sonnet}"
DATASET="SWE-bench/SWE-bench_Lite"
CONC=2
ARMS="${BENCH_ARMS:-A B}"
TAG="swe"
MAXTURNS=50
DO_EVAL=1
GEN=1
SUBSET=""

DEFAULT_SUBSET="pallets__flask-4992 pallets__flask-5063 psf__requests-3362 psf__requests-2317 pytest-dev__pytest-5227 pytest-dev__pytest-5413 pytest-dev__pytest-5692 pytest-dev__pytest-7373 pytest-dev__pytest-11143 pytest-dev__pytest-7220"

CACHE="${SWE_CACHE:-$HOME/.cache/swe-superskills}"
REPOS="$CACHE/repos"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --subset) SUBSET="$2"; shift 2 ;;
    --subset-file) SUBSET="$(tr '\n' ' ' < "$2")"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --arms) ARMS="$2"; shift 2 ;;
    --concurrency) CONC="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --max-turns) MAXTURNS="$2"; shift 2 ;;
    --no-eval) DO_EVAL=0; shift ;;
    --eval-only) GEN=0; shift ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done
[[ -n "$SUBSET" ]] || SUBSET="$DEFAULT_SUBSET"
[[ -n "$UV" ]] || { echo "uv not found on PATH" >&2; exit 1; }

WORK="${SWE_WORK:-$(mktemp -d)}"
if [[ "${BENCH_KEEP:-0}" != 1 && -z "${SWE_WORK:-}" ]]; then trap 'rm -rf "$WORK"' EXIT; fi
META="$WORK/meta"
PRED="$BENCH_DIR/results"
mkdir -p "$META" "$PRED" "$REPOS"
echo "work dir: $WORK   tag: $TAG   arms: $ARMS"

ALLOWED="Read,Glob,Grep,Write,Edit,MultiEdit,Skill,TodoWrite,Bash"

throttle() { while (( $(jobs -rp | wc -l) >= CONC )); do sleep 2; done; }
slug() { echo "${1/\//__}"; }
jget() { $PY -c "import json,sys;d=json.load(open(sys.argv[1]));v=d[sys.argv[2]];print(' '.join(v) if isinstance(v,list) else v)" "$1" "$2"; }

ensure_repo() { # repo
  local repo="$1" s; s="$(slug "$repo")"
  [[ -d "$REPOS/$s.git" ]] && return 0
  echo "  cloning $repo (one-time)..."
  git clone --bare -q "https://github.com/$repo.git" "$REPOS/$s.git"
}

setup_checkout() { # dir metafile
  local dir="$1" mf="$2" repo bc s
  repo="$(jget "$mf" repo)"; bc="$(jget "$mf" base_commit)"; s="$(slug "$repo")"
  ensure_repo "$repo"
  git clone -q --local --no-hardlinks "$REPOS/$s.git" "$dir"
  git -C "$dir" checkout -q "$bc"
  # Keep superskills, the venv, and tool/build droppings out of the model patch.
  printf '/.venv/\n/.claude/\n/.superskills/\n/AGENTS.md\n/CLAUDE.md\nuv.lock\n__pycache__/\n*.pyc\n.pytest_cache/\n*.egg-info/\n' >> "$dir/.git/info/exclude"
}

build_venv() { # dir metafile
  local dir="$1" mf="$2" py pins repo vpy
  py="$(jget "$mf" python)"; pins="$(jget "$mf" pip_packages)"; repo="$(jget "$mf" repo)"
  "$UV" venv -q --python "$py" "$dir/.venv" >/dev/null 2>&1 || "$UV" venv -q "$dir/.venv" >/dev/null 2>&1
  vpy="$dir/.venv/bin/python"
  # Pinned (era-correct) deps FIRST so the editable install keeps compatible versions
  # (e.g. flask 2.3 needs Werkzeug 2.3.x; a later install would otherwise pull a
  # newer Werkzeug whose removed symbols break import). Then the project editable,
  # then an era-appropriate pytest so the model can actually run the suite — except
  # for pytest's own repo, which ships pytest via the editable install.
  [[ -n "$pins" ]] && "$UV" pip install --python "$vpy" $pins >"$dir/.venvlog" 2>&1
  # editable: prefer an isolated build; if the project's build backend is too old
  # for PEP 660 (no build_editable), retry with a modern in-venv backend.
  if ! ( cd "$dir" && "$UV" pip install --python "$vpy" -e . ) >>"$dir/.venvlog" 2>&1; then
    "$UV" pip install --python "$vpy" "setuptools>=68" wheel setuptools_scm >>"$dir/.venvlog" 2>&1
    ( cd "$dir" && "$UV" pip install --python "$vpy" --no-build-isolation -e . ) >>"$dir/.venvlog" 2>&1
  fi
  [[ "$repo" == "pytest-dev/pytest" ]] || "$UV" pip install --python "$vpy" "pytest==7.4.4" >>"$dir/.venvlog" 2>&1
}

make_arm_fixture() { # dir arm
  local dir="$1" arm="$2"
  [[ "$arm" == B ]] || return 0
  mkdir -p "$dir/.claude/skills"
  for s in learn discover clarify test; do
    cp -R "$PLUGIN_DIR/skills/$s" "$dir/.claude/skills/$s"
  done
  local verify="${SWE_VERIFY_HOOK:-$PLUGIN_DIR/hooks/stop-verify.js}"
  cat > "$dir/.claude/settings.json" <<EOF
{
  "hooks": {
    "SessionStart": [
      { "matcher": "startup|resume|clear",
        "hooks": [{ "type": "command", "command": "node \"$PLUGIN_DIR/hooks/session-start.js\"", "timeout": 10 }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "node \"$verify\"", "timeout": 15 }] },
      { "hooks": [{ "type": "command", "command": "node \"$PLUGIN_DIR/hooks/stop-learn.js\"", "timeout": 15 }] }
    ]
  }
}
EOF
  # Optimization knob (experiment-only): inject a conventions file into arm B.
  if [[ -n "${SWE_CONV:-}" && -f "${SWE_CONV:-}" ]]; then
    mkdir -p "$dir/.superskills"
    cp "$SWE_CONV" "$dir/.superskills/conventions.md"
    printf '@.superskills/conventions.md\n' > "$dir/CLAUDE.md"
  fi
}

run_one() { # iid arm
  local iid="$1" arm="$2"
  local dir="$WORK/run-$iid-$arm" mf="$META/$iid/meta.json"
  local ps; ps="$(cat "$META/$iid/problem_statement.txt")"
  setup_checkout "$dir" "$mf"
  build_venv "$dir" "$mf"
  make_arm_fixture "$dir" "$arm"
  local extra=()
  [[ "$arm" == A ]] && extra+=(--disallowedTools "Skill")
  local prompt="Fix the bug described in the GitHub issue below by editing this repository's source code. The project is installed editable in ./.venv — reproduce the bug and check your fix by running existing tests or a short script with ./.venv/bin/python -m pytest <path> (or ./.venv/bin/python <script>). Do not edit the test suite to satisfy a grader; add your own scratch repro if helpful, then make the smallest change that fixes the root cause.

GitHub issue:
$ps"
  # Response and patch are written OUTSIDE the checkout so they never enter the diff.
  ( cd "$dir" && claude -p "$prompt" \
      --model "$MODEL" \
      --permission-mode acceptEdits \
      --allowedTools "$ALLOWED" \
      ${extra[@]+"${extra[@]}"} \
      --max-turns "$MAXTURNS" ) > "$WORK/resp-$iid-$arm.txt" 2>&1 || true
  git -C "$dir" add -A 2>/dev/null
  git -C "$dir" diff --cached > "$WORK/patch-$iid-$arm.diff" 2>/dev/null || true
  $PY "$SWE_DIR/emit_pred.py" "$iid" "ss_${arm}" "$WORK/patch-$iid-$arm.diff" > "$WORK/pred-$iid-$arm.jsonl"
  local nl; nl="$(grep -c '^+' "$WORK/patch-$iid-$arm.diff" 2>/dev/null || echo 0)"
  echo "  gen: $iid arm=$arm patch_added_lines=$nl"
}

# ---- phase 1: dump instance fields (held-out tests stay in $META, off-repo) ----
echo "== dumping instances =="
SWE_DATASET="$DATASET" $PY "$SWE_DIR/swe_instance.py" dump "$META" $SUBSET

# ---- phase 2: generate patches ----
if [[ "$GEN" == 1 ]]; then
  echo "== generating patches: arms [$ARMS], conc=$CONC =="
  for iid in $SUBSET; do
    for arm in $ARMS; do
      throttle; run_one "$iid" "$arm" &
    done
  done
  wait
  for arm in $ARMS; do
    : > "$PRED/swe-pred-$arm.jsonl"
    for iid in $SUBSET; do cat "$WORK/pred-$iid-$arm.jsonl" >> "$PRED/swe-pred-$arm.jsonl" 2>/dev/null || true; done
  done
fi

# ---- phase 3: official swebench Docker eval per arm ----
if [[ "$DO_EVAL" == 1 ]]; then
  for arm in $ARMS; do
    echo "== evaluating arm $arm via swebench Docker harness =="
    rm -f "$PRED/ss_${arm}.${TAG}-${arm}.json"
    # swe_eval.py forces native arm64 builds (swebench 4.1 hardcodes x86_64).
    ( cd "$PRED" && SWE_ARCH="${SWE_ARCH:-arm64}" "$PY" "$SWE_DIR/swe_eval.py" \
        -d "$DATASET" -p "$PRED/swe-pred-$arm.jsonl" \
        --run_id "${TAG}-${arm}" --namespace none \
        --cache_level env --max_workers "${EVAL_WORKERS:-2}" ) 2>&1 | grep -iE "resolved|completed|error|building|Done|instances" | tail -6
  done
  echo "== report =="
  node "$SWE_DIR/report-swe.js" "$PRED" "$TAG" "$ARMS" | tee "$PRED/swe-report.md"
fi

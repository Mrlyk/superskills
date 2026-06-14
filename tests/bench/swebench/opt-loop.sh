#!/usr/bin/env bash
# Optimization loop driver: run a list of superskills levers on the 5 unsolved
# SWE-bench instances. Per lever: re-generate arm B with that lever, grade with
# the official swebench harness, print resolved/5 and the resolved ids. Any lever
# that cracks a previously-unsolved instance is a real improvement (then confirm
# on the full 11). Appends one line per lever to results/opt-results.txt.
#
#   tests/bench/swebench/opt-loop.sh "tag1|conv1.md|hook1.js" "tag2|conv2.md|"
# Each entry is tag|convFileUnder levers/ (or empty)|hookFile under swebench/ (or empty).
set -uo pipefail
BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWE_DIR="$BENCH_DIR/swebench"
PY="$BENCH_DIR/.swebench-venv/bin/python"
SUBSET="${SWE_SUBSET:-$SWE_DIR/unsolved5.txt}"
IDS=$(tr '\n' ' ' < "$SUBSET")
N=$(grep -c . "$SUBSET")
OUT="$BENCH_DIR/results/opt-results.txt"

for entry in "$@"; do
  IFS='|' read -r tag conv hook <<< "$entry"
  echo "==== ROUND $tag (conv=${conv:-none} hook=${hook:-shipped}) ===="
  work="/tmp/opt-$tag"; rm -rf "$work"
  envs=()
  [ -n "$conv" ] && envs+=("SWE_CONV=$SWE_DIR/levers/$conv")
  [ -n "$hook" ] && envs+=("SWE_VERIFY_HOOK=$SWE_DIR/$hook")
  SWE_WORK="$work" BENCH_KEEP=1 env ${envs[@]+"${envs[@]}"} \
    "$BENCH_DIR/swe-bench.sh" --subset-file "$SUBSET" --arms B --tag "$tag" \
    --concurrency 3 --max-turns "${SWE_MAXTURNS:-50}" --no-eval > "/tmp/opt-$tag-gen.log" 2>&1
  # aggregate the 5 arm-B predictions (Python, RTK-safe)
  "$PY" - "$work" "$BENCH_DIR/results/pred-$tag-B.jsonl" $IDS <<'PY'
import json, os, sys
work, out = sys.argv[1], sys.argv[2]; ids = sys.argv[3:]
rows=[]
for iid in ids:
    f=f"{work}/pred-{iid}-B.jsonl"
    if os.path.exists(f):
        d=json.loads(open(f).read().strip()); d["model_name_or_path"]=f"ss_{os.path.basename(out)}"; rows.append(d)
open(out,"w").write("".join(json.dumps(d)+"\n" for d in rows))
print(f"aggregated {len(rows)} preds")
PY
  rm -f "$BENCH_DIR/ss_"*".$tag-B.json"
  ( cd "$BENCH_DIR" && SWE_ARCH=arm64 "$PY" "$SWE_DIR/swe_eval.py" \
      -d SWE-bench/SWE-bench_Lite -p "$BENCH_DIR/results/pred-$tag-B.jsonl" \
      --run_id "$tag-B" --namespace none --cache_level env --max_workers 2 \
      > "/tmp/opt-$tag-eval.log" 2>&1 )
  rep=$(ls "$BENCH_DIR"/ss_*."$tag-B.json" 2>/dev/null | head -1)
  line=$("$PY" -c "import json,sys; d=json.load(open(sys.argv[1])); r=sorted(d['resolved_ids']); print(f\"$tag: {len(r)}/$N resolved={r}\")" "$rep" 2>/dev/null || echo "$tag: eval-failed")
  echo "$line" | tee -a "$OUT"
done
echo "OPT-LOOP DONE"

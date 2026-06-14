---
topic: Benchmark harness
tags: [bench]
---
# Benchmark harness

**EvalPlus datasets share one schema** (`base_input`/`plus_input`/`canonical_solution`/`entry_point`/`atol`), so `tests/bench/humaneval/grade-plus.py` and `heval-hard.sh` extend to new sets with a flag: `--plus` = HumanEval+, `--mbpp` = MBPP+. MBPP prompts are a docstring + example `assert` with no `def` line, so the model prompt must name the `entry_point`.

**Plugin contamination guard**: never leave the superskills plugin installed at user scope while `heval-hard.sh` / `learn-*.sh` run — the local `directory`/`github` marketplace loads live repo files (or fires the global hooks) into every baseline trial. `claude plugin uninstall superskills@superskills` first, restore after. `--bare` is not a substitute: it drops the login session.

**SWE-bench Lite harness** (`tests/bench/swe-bench.sh` + `swebench/`): per instance, check out the repo at `base_commit` into a throwaway dir and build a RUNNABLE venv so the model can actually run tests, then `claude -p`; arm B drops superskills into the checkout's `.claude/`; the model patch (git diff, with superskills+venv kept out via `.git/info/exclude`) is graded by the official `swebench` Docker harness. Hard-won setup facts:

- **arm64**: swebench 4.1 hardcodes `arch="x86_64"` in `make_test_spec` (no CLI override), so on Apple Silicon it builds x86_64 under QEMU — unusably slow (base build never commits a layer). `swebench/swe_eval.py` patches `make_test_spec.__defaults__` to `arm64` → native builds. The daemon needs direct registry egress (Docker Desktop's `http.docker.internal:3128`, not the host's loopback proxy which the VM can't reach); first pulls/conda base build are just slow, not hung — don't kill early.
- **Gold-validate the subset**: only keep instances whose GOLD patch resolves in *your* arm64 Docker grader (`-p gold`). Dropped pylint (instance image `setup_repo.sh` build fails on arm64) and requests (tests need real network → gold scores 2 failed/108 errors). 11 of 12 attempted survived.
- **Runnable venv**: install pinned `pip_packages` FIRST, then `pip install -e .`, else a newer dep (e.g. Werkzeug) breaks import. Add an era-appropriate `pytest==7.4.4` (latest breaks old conftests); pytest's own repo ships pytest via the editable install. If `-e .` fails with no `build_editable`, retry with a modern in-venv setuptools + `--no-build-isolation`.
- **RTK breaks data pipelines**: the token-killer hook rewrites direct Bash `cat`/`tr`/`head` and returns a SUMMARY, silently corrupting predictions/aggregations. Aggregate JSONL with Python (its file I/O isn't intercepted), never `cat >>`.

**SWE-bench finding (parity, not a tuning miss)**: A 6/11 = B 6/11, identical resolved set. A full optimization loop (`swebench/opt-loop.sh`: 11 levers — conventions variants, hook variants, repro-gate, let-it-cook — + 6 variance passes, ~17 arm-B re-gens) found NO lever that reliably improves it. One instance (flask-4992) flipped in 2 of 9 levers, but pure conv-tdd replicated it 0/3 and baseline 0/4 — it's a ~15% run-to-run-variance instance, the flips are noise (the small-sample lesson again). Mechanism: the shipped verify hook fired 0/12 while the model self-ran pytest 12/12 — dormant because Sonnet already tests on agentic multi-file tasks, and the acceptance test (FAIL_TO_PASS) is hidden so no verification can close the gap. Lift across the three community benchmarks tracks whether the acceptance criteria are visible: HumanEval+ +10pp, MBPP+ +3pp, SWE-bench even. Screen levers on the unsolved subset; confirm any apparent win with a variance check before believing it.

Related: [[graders-multilingual-output]], [[node-test-no-dir-arg]]

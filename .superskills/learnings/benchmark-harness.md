---
topic: Benchmark harness
tags: [bench]
---
# Benchmark harness

**EvalPlus datasets share one schema** (`base_input`/`plus_input`/`canonical_solution`/`entry_point`/`atol`), so `tests/bench/humaneval/grade-plus.py` and `heval-hard.sh` extend to new sets with a flag: `--plus` = HumanEval+, `--mbpp` = MBPP+. MBPP prompts are a docstring + example `assert` with no `def` line, so the model prompt must name the `entry_point`.

**Plugin contamination guard**: never leave the superskills plugin installed at user scope while `heval-hard.sh` / `learn-*.sh` run — the local `directory`/`github` marketplace loads live repo files (or fires the global hooks) into every baseline trial. `claude plugin uninstall superskills@superskills` first, restore after. `--bare` is not a substitute: it drops the login session.

**No Docker on this machine** → SWE-bench's official harness is infeasible; stay on single-function EvalPlus sets (HumanEval+, MBPP+) for the verify dimension.

Related: [[graders-multilingual-output]], [[node-test-no-dir-arg]]

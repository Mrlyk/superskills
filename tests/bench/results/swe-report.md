# SWE-bench Lite — A/B + optimization (superskills)

Real GitHub-issue, multi-file repository fixes. Model: Sonnet 4.6 via `claude -p`
in a runnable per-instance checkout (project installed editable + era pytest).
Graded by the official `swebench` Docker harness (hidden FAIL_TO_PASS +
PASS_TO_PASS), native arm64, pass@1. Arm A = pure model; arm B = superskills in
the checkout's `.claude/`. Harness: `tests/bench/swe-bench.sh`.

## Subset (11 gold-validated instances)

Gold-validated = the gold patch resolves in this machine's arm64 Docker grader.
12 attempted; 4 dropped as unusable here (gold itself does not resolve):
pylint-7993 / 7228 / 7080 (instance image build fails on arm64), requests-3362
(tests need real network — gold scores 2 failed / 108 errors).

Kept: flask-4992, flask-5063, pytest-8906, pytest-9359, pytest-7373, pytest-7220,
pytest-7168, pytest-7432, sympy-23117, sympy-23191, sympy-23262.

## Baseline A/B

| Arm | resolved | rate |
|-----|----------|------|
| A — pure model | 6/11 | 54.5% |
| B — superskills | 6/11 | 54.5% |

Identical resolved set: {pytest-7168, pytest-7373, pytest-7432, pytest-9359,
sympy-23117, sympy-23262}. Identical unresolved set: {flask-4992, flask-5063,
pytest-7220, pytest-8906, sympy-23191}. superskills changes nothing.

## Why parity (mechanism, verified)

SWE-bench acceptance tests are hidden. Across the 12 baseline arm-B sessions the
model ran pytest on its own **12/12**, while the shipped `stop-verify.js` fired
**0/12** (it only triggers when code was edited but never executed — never true
here). The verify hook is dormant; even firing, it can only force runs against
visible tests, not the hidden acceptance criterion. The bottleneck is producing
the correct fix, which superskills does not provide.

## Optimization variants (arm B re-generated; no shipped config changed)

| Variant | resolved | vs baseline |
|---------|----------|-------------|
| Shipped superskills | 6/11 | parity |
| + generic bug-fix conventions | 6/11 | same set — reasoning-aid prompt gains nothing |
| Forced reproduce+regression verify hook (fired 11/11) | 6/11 | same set — forced verification gains nothing |

All four configurations converge on the identical 6/11. Conclusion: structural
parity on SWE-bench; no superskills lever moves the metric because the bottleneck
(producing the right fix against a hidden acceptance test) is orthogonal to what
superskills provides. Three-benchmark picture: lift tracks visibility of the
acceptance criteria — HumanEval+ +10pp, MBPP+ +3pp, SWE-bench even, no regression.

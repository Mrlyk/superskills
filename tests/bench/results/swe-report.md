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

## Optimization loop (11 levers + 6 variance passes, ~17 arm-B re-gens; no shipped config changed)

Full 11: shipped, +conv-bugfix, +forced-verify hook → all 6/11 (same set). Then,
on the 5 unsolved instances, each lever re-generated arm B (`swebench/opt-loop.sh`,
results in `opt-results.txt`):

| Lever | of 5 unsolved |
|-------|---------------|
| conv-tdd (write failing repro test first) | 1 (flask-4992) |
| conv-readtests / conv-plan / conv-edges / conv-combined | 0 each |
| conv-combined + forced verify hook | 1 (flask-4992) |
| repro-gate hook | 0 |
| let-it-cook (TDD + turns 80) | 0 |

Only flask-4992 ever flipped (2 of 9 levers) — but not in conv-combined, which has
the same TDD instruction. Decisive variance check: pure conv-tdd on flask-4992
replicated 0/3 (1/4 total), baseline 0/4. flask-4992 is a ~15% run-to-run-variance
instance; the flips are noise, not a lever effect.

Conclusion: across ~17 re-generations no superskills lever reliably moves the
SWE-bench resolve rate. The bottleneck (producing the right fix against a hidden
acceptance test) is orthogonal to what superskills provides. Shipped config stays
optimal at 6/11. Three-benchmark picture: lift tracks visibility of the acceptance
criteria — HumanEval+ +10pp, MBPP+ +3pp, SWE-bench even, no regression.

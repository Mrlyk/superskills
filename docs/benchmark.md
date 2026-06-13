# superskills benchmark

A/B comparison of the same model with and without superskills, on the scenarios each component is designed for, plus a public-benchmark control group for regression checking.

## Methodology

The harness follows the evaluation conventions of community benchmarks (HumanEval, SWE-bench): fixed tasks, isolated per-trial environments, real model runs end to end, and deterministic programmatic graders — no LLM-as-judge, no manual scoring. There is no public benchmark that measures what a coding harness adds (cross-session memory, convention adherence, clarification behavior), so the capability scenarios are purpose-built and fully reproducible from this repository; the control group reuses HumanEval problems verbatim.

- **Model**: `sonnet` (Claude Sonnet 4.6) for both arms, via `claude -p` with scoped permissions in throwaway git fixtures.
- **Arm A (baseline, pure model)**: the fixture contains only a one-line `CLAUDE.md` (project name). The `Skill` tool is disallowed, so no superskills component can fire.
- **Arm B (superskills)**: identical fixture plus exactly the artifacts the component under test produces (frozen output of a real `discover` run, or real learnings files). Hooks run for real — the learnings index in S2 reaches the model through the actual SessionStart hook, not through the prompt.
- **Grading**: each scenario has a Node grader that inspects the resulting working tree and dynamically imports the produced code to assert behavior. A check either passes or fails; scenario score is the fraction of checks passed. The HumanEval control uses the dataset's canonical `check()` tests.
- **Trials**: 3 per arm per scenario; HumanEval control runs each of the 10 problems once per arm.

### Scenarios

| ID | Component under test | Fixture | Task | Graded checks |
|----|----------------------|---------|------|---------------|
| S1 | `discover` artifacts (conventions.md + AGENTS.md + CLAUDE.md) | Node ESM store library whose written rules live in `docs/engineering-handbook.md` and `CONTRIBUTING.md` | Implement `applyDiscount(items, percent)` with validation and tests | implemented, barrel re-export, JSDoc, integer-cents rounding, `E_RANGE` on percent>100/negative, typed errors, tests written and passing (7) |
| S2 | `learn` + SessionStart hook injection | Same fixture with conventions docs removed — three team decisions exist only in `.superskills/learnings/` (pnpm not npm; ISO-8601 UTC timestamps; README quickstart examples) | Write a Getting-started README section and implement `makeReceipt(totalCents)` | uses pnpm, no plain npm, ISO timestamp behavior, README usage example, suite passes (5) |
| S3 | `clarify` | Store fixture | "Add an export feature for orders so users can download their order history" (format, fields, and delivery deliberately unspecified) | asked the load-bearing question AND did not commit guessed code (success = both) |
| S4 | `test` | Store fixture with a just-developed `applyCoupon` left in the working tree containing two planted convention bugs (float result; missing `E_RANGE` validation) | "Feature was just developed" + write tests (A) / apply the test skill (B) | tests cover coupon, suite passes, float bug fixed at root cause, range bug fixed, edge cases tested (5) |
| Control | none — regression check | Minimal Python project | HumanEval/0–9 verbatim: implement the function in `solution.py` | canonical HumanEval `check()` passes |

The control group exists because always-on context injection could plausibly hurt raw coding. Identical pass rates across arms mean superskills adds its capabilities without degrading baseline coding ability.

### Run details

Executed 2026-06-13 with claude CLI 2.1.175, model `sonnet` (Claude Sonnet 4.6), 44 trials, 26 minutes of total model runtime. Two methodology corrections were applied during the run and are reflected in the results: the S2 task originally hinted "add a usage example where appropriate", which leaked one graded check into the prompt — S2 was re-run for both arms with neutral wording; and the S3 grader originally recognized only ASCII question marks, misgrading correct clarifying questions asked with a fullwidth `？` — the affected trials were re-graded from their captured responses with the fixed grader.

### Threats to validity

- Fixtures are small; a baseline agent can sometimes find the scattered rules by reading the repo. This biases results against superskills, not for it — in real codebases the rules are spread across far more files, while conventions.md stays one read away.
- S1 came out at parity for exactly that reason: in a ten-file fixture the baseline reliably finds and follows the rule docs by itself, so the discover artifacts added no measurable quality there (only a small time saving). The S2/S4 gaps show what happens once the knowledge is not one obvious read away.
- S2 measures the value of knowledge that exists nowhere in the repo. That is by construction: it isolates the memory channel, which is exactly the gap the learn skill exists to fill.
- Arm B invokes `clarify`/`test` explicitly (the same way a user types the slash command), so the numbers measure skill content, not auto-trigger rates. In one S3 trial the model never engaged the skill and implemented directly; that trial counts as an arm-B failure rather than being excluded.
- 3 trials per cell is small; treat single-digit percentage differences as noise and read the per-check tables instead.

## Results

| Scenario | Measures | Baseline (pure model) | With superskills | Δ | Mean time A → B |
|----------|----------|----------------------|------------------|---|------------------|
| S1 Convention adherence | mean check score | 100% | 100% | +0pp | 54s → 52s |
| S2 Cross-session memory | mean check score | 20% | 100% | +80pp | 39s → 38s |
| S3 Requirement clarification | asked-before-guessing rate | 0% | 67% | +67pp | 98s → 84s |
| S4 Final test pass | mean check score | 40% | 100% | +60pp | 35s → 62s |
| Control: HumanEval/0-9 | pass@1 | 100% | 100% | +0pp | 10s → 10s |

### S1 Convention adherence

superskills component under test: discover artifacts; trials: 3 baseline / 3 superskills.

| Check | Baseline | With superskills |
|-------|----------|------------------|
| implemented | 3/3 | 3/3 |
| barrelExport | 3/3 | 3/3 |
| jsdoc | 3/3 | 3/3 |
| integerCents | 3/3 | 3/3 |
| rangeError | 3/3 | 3/3 |
| typedError | 3/3 | 3/3 |
| testsCoverAndPass | 3/3 | 3/3 |

### S2 Cross-session memory

superskills component under test: learn + SessionStart hook; trials: 3 baseline / 3 superskills.

| Check | Baseline | With superskills |
|-------|----------|------------------|
| usesPnpm | 0/3 | 3/3 |
| noPlainNpm | 0/3 | 3/3 |
| isoTimestamp | 0/3 | 3/3 |
| readmeExample | 0/3 | 3/3 |
| testsPass | 3/3 | 3/3 |

### S3 Requirement clarification

superskills component under test: clarify; trials: 3 baseline / 3 superskills.

| Check | Baseline | With superskills |
|-------|----------|------------------|
| askedKeyQuestion | 0/3 | 2/3 |
| noPrematureCode | 0/3 | 2/3 |

### S4 Final test pass

superskills component under test: test; trials: 3 baseline / 3 superskills.

| Check | Baseline | With superskills |
|-------|----------|------------------|
| testsCoverCoupon | 3/3 | 3/3 |
| suitePasses | 3/3 | 3/3 |
| floatBugFixed | 0/3 | 3/3 |
| rangeBugFixed | 0/3 | 3/3 |
| edgeCasesTested | 0/3 | 3/3 |

### Control: HumanEval/0-9

superskills component under test: none (regression check); trials: 10 baseline / 10 superskills.

| Check | Baseline | With superskills |
|-------|----------|------------------|
| pass | 10/10 | 10/10 |

Total model runtime across trials: 26 min.

## HumanEval hard subset (community benchmark)

The 10-problem control above sits at the ceiling: a strong model passes easy HumanEval problems with or without a harness. To measure on community tasks where improvement is possible, we use the standard hard-subset method: screen the baseline once over a pre-registered contiguous range of the official dataset, take exactly its failures as the hard set, then measure both arms fresh.

- **Selection**: baseline-only screening (1 trial/problem, no superskills anywhere). Screening runs are independent of measurement runs, so regression to the mean affects both arms equally. The hard set is whatever fails — no manual picking.
- **Hermetic arms**: arm A runs with the `Skill` tool disallowed and no plugin; arm B loads the plugin per-run via `--plugin-dir`, immune to whatever is installed at user scope. Both arms get identical prompts and identical turn budgets (24); the only difference is the presence of superskills (frozen discover-generated specs in the fixture, plus the plugin's skills and hooks).
- **Grading**: the dataset's canonical `check()` tests, verbatim.

### What superskills contributes here

Nothing in superskills knows anything about HumanEval. The active ingredient is the final-test-pass capability made automatic, which took three iterations to get right:

1. **Round 1 — workflow pointer.** discover's `AGENTS.md` template gained a line: run one full test pass before declaring done. Result: ignored. In headless runs the model completes a "simple-looking" function in one shot and never reads the ceremony into action.
2. **Round 2 — definition of done.** Stronger wording ("no exceptions", boundary-case checklist). Result: still ignored. Prose discipline does not survive contact with a model that believes the task is trivial. A context probe confirmed the instructions were loaded — they were seen and skipped.
3. **Round 3 — enforcement in the harness.** A third hook, `stop-verify.js` (~100 lines): on Stop, if the session edited code files but never executed anything afterwards, block once and demand a real run — every documented example verbatim, empty input, and the boundary cases the spec implies — with root-cause fixes. Deterministic, once per session, loop-safe. Probe runs confirm the full loop: the model finishes, the hook blocks, the model writes a throwaway check, runs it, fixes, then finishes with run output.

That is the project's thesis in miniature: as models get stronger, prose process gets skipped; the two places a harness still earns its keep are knowledge the model cannot have (memory, conventions) and a few deterministic enforcement points (verification). Rounds 1–2 shipped anyway (better wording costs nothing); round 3 is the mechanism that moves the number.

### Results

<!-- RESULTS-HEVAL -->

## Reproducing

```bash
./tests/bench/freeze-specs.sh     # optional: regenerate arm-B specs with the real discover skill
./tests/bench/run.sh --trials 3   # full suite, writes tests/bench/results/report.md
./tests/bench/run.sh --scenarios s2 --trials 5   # one scenario, more trials
./tests/bench/heval-hard.sh                      # community hard subset: screen + measure
```

Prerequisites: `claude` CLI logged in, the superskills plugin installed and enabled, Node ≥ 18, Python 3 for the control group.

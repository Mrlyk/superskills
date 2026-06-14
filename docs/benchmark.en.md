# superskills benchmark

A/B comparison of the same model with and without superskills, on the scenarios each component is designed for, plus a public-benchmark group (HumanEval / HumanEval+) that targets raw single-shot coding.

[中文](benchmark.md)

## Methodology

The harness follows the evaluation conventions of community benchmarks: fixed tasks, isolated per-trial environments, real model runs end to end, and deterministic programmatic graders — no LLM-as-judge, no manual scoring. There is no public benchmark that measures what a coding harness adds (cross-session memory, convention adherence, clarification behavior), so the capability scenarios are purpose-built and fully reproducible from this repository; the public-benchmark group reuses HumanEval problems verbatim.

- **Model**: `sonnet` (Claude Sonnet 4.6) for both arms, via `claude -p` with scoped permissions in throwaway git fixtures.
- **Arm A (baseline, pure model)**: the fixture contains only a one-line `CLAUDE.md` (project name). The `Skill` tool is disallowed, so no superskills component can fire.
- **Arm B (superskills)**: identical fixture plus exactly the artifacts the component under test produces (frozen output of a real `discover` run, or real learnings files). Hooks run for real — the learnings index in S2 reaches the model through the actual SessionStart hook, not through the prompt.
- **Grading**: each scenario has a Node grader that inspects the resulting working tree and dynamically imports the produced code to assert behavior. A check either passes or fails; scenario score is the fraction of checks passed. The HumanEval group uses the dataset's canonical `check()` (and EvalPlus's stricter grader).
- **Trials**: 3 per arm per scenario; HumanEval control runs each of the 10 problems once per arm.

### Scenarios

| ID | Component under test | Fixture | Task | Graded checks |
|----|----------------------|---------|------|---------------|
| S1 | `discover` artifacts (conventions.md + AGENTS.md + CLAUDE.md) | Node ESM store library whose written rules live in `docs/engineering-handbook.md` and `CONTRIBUTING.md` | Implement `applyDiscount(items, percent)` with validation and tests | implemented, barrel re-export, JSDoc, integer-cents rounding, `E_RANGE` on percent>100/negative, typed errors, tests written and passing (7) |
| S2 | `learn` + SessionStart hook injection | Same fixture with conventions docs removed — three team decisions exist only in `.superskills/learnings/` (pnpm not npm; ISO-8601 UTC timestamps; README quickstart examples) | Write a Getting-started README section and implement `makeReceipt(totalCents)` | uses pnpm, no plain npm, ISO timestamp behavior, README usage example, suite passes (5) |
| S3 | `clarify` | Store fixture | "Add an export feature for orders" (format, fields, and delivery deliberately unspecified) | asked the load-bearing question AND did not commit guessed code (success = both) |
| S4 | `test` | Store fixture with a just-developed `applyCoupon` left in the working tree containing two planted convention bugs (float result; missing `E_RANGE` validation) | "Feature was just developed" + write tests (A) / apply the test skill (B) | tests cover coupon, suite passes, float bug fixed at root cause, range bug fixed, edge cases tested (5) |
| Control | none — regression check | Minimal Python project | HumanEval/0–9 verbatim: implement the function in `solution.py` | canonical HumanEval `check()` passes |

The control group exists because always-on context injection could plausibly hurt raw coding. Identical pass rates across arms mean superskills adds its capabilities without degrading baseline coding ability.

### Threats to validity

- Fixtures are small; a baseline agent can sometimes find the scattered rules by reading the repo. This biases results against superskills, not for it — in real codebases the rules are spread across far more files, while conventions.md stays one read away.
- S1 came out at parity for exactly that reason: in a ten-file fixture the baseline reliably finds and follows the rule docs by itself, so the discover artifacts added no measurable quality there (only a small time saving). The S2/S4 gaps show what happens once the knowledge is not one obvious read away.
- Arm B invokes `clarify`/`test` explicitly (the same way a user types the slash command), so the numbers measure skill content, not auto-trigger rates.
- 3 trials per cell is small; treat single-digit percentage differences as noise and read the per-check tables instead.

## Results — capability suite

| Scenario | Measures | Baseline (pure model) | With superskills | Δ | Mean time A → B |
|----------|----------|----------------------|------------------|---|------------------|
| S1 Convention adherence | mean check score | 100% | 100% | +0pp | 54s → 52s |
| S2 Cross-session memory | mean check score | 20% | 100% | +80pp | 39s → 38s |
| S3 Requirement clarification | asked-before-guessing rate | 0% | 67% | +67pp | 98s → 84s |
| S4 Final test pass | mean check score | 40% | 100% | +60pp | 35s → 62s |
| Control: HumanEval/0-9 | pass@1 | 100% | 100% | +0pp | 10s → 10s |

Per-check detail:

- **S2** (memory): every superskills trial used pnpm, avoided plain npm, applied ISO-8601 timestamps, and added the README example (0/3 → 3/3 on each); baseline 0/3 on all four. The suite passed in both arms.
- **S4** (test pass): baseline wrote passing tests *around* both planted bugs in 3/3 trials (float result, missing range validation); the test skill fixed both at root cause and added edge-case tests in 3/3.
- **S3** (clarify): baseline asked the load-bearing question in 0/3 and committed guessed code; arm B asked and held off coding in 2/3.
- **S1 / control**: identical 100% — superskills adds no regression to plain coding.

The pattern: when the knowledge is one obvious read away in a tiny fixture, a strong model already behaves (S1, control). The gains appear exactly where superskills operates — knowledge that exists nowhere in the repo (memory), questions nobody asked (clarification), and bugs that fresh tests happily cement in place (test pass).

## Results — public benchmarks (HumanEval & HumanEval+)

The 10-problem control sits at the ceiling: a strong model passes easy HumanEval problems with or without a harness — and on the full 164 problems the clean baseline scored 162/164 (98.8%), confirming HumanEval is essentially saturated for Sonnet 4.6. Two things follow: pick the problems the model actually fails, and grade them harder. So this runs two public benchmarks on hard subsets.

- **Standard HumanEval** — the canonical `check()` tests. Screening the baseline across all 164 problems leaves a 2-problem hard set ({101, 144}).
- **HumanEval+ (EvalPlus)** — the community's stricter grader: each problem gets up to ~1000 generated inputs (≈80× the original suite), built specifically to catch edge-case bugs that the sparse canonical tests miss. This is the benchmark that targets exactly what the verify hook enforces.

Method, identical for both:

- **Selection**: baseline-only screening (1 trial/problem, no superskills anywhere). Screening is independent of the measurement runs, so regression to the mean affects both arms equally. The hard set is whatever the baseline fails — no manual picking.
- **Hermetic arms**: arm A runs with the `Skill` tool disallowed and no superskills present anywhere. Arm B carries superskills entirely inside the fixture: the frozen discover-generated specs, the four skills under `.claude/skills/`, and a project-level `.claude/settings.json` wiring the three hooks by absolute path. Both arms get identical prompts and identical turn budgets (24).
- **A discarded run, and what caught it**: the first measurement loaded arm B's plugin with `--plugin-dir`. That flag registers the plugin in *global* state as a side effect, so every later `claude -p` — including the next baseline screen — silently inherited the verify hook, while arm B itself lost its hooks to a name collision. The tell was inverted timings: the "baseline" ran longer and more carefully than arm B. The verify hook's own per-session marker file doubled as the contamination probe that confirmed it. Fix: uninstall the global plugin for the duration of the benchmark, give arm B its own in-fixture `.claude/`, clean global state, and re-screen. The harness caught a flaw in its own benchmark — which is the verify hook's whole thesis, applied to ourselves.

### What superskills contributes here

Nothing in superskills knows anything about HumanEval. The active ingredient is the final-test-pass capability made automatic — and making a headless model actually verify took three attempts:

1. **Attempt 1 — workflow pointer.** discover's `AGENTS.md` template gained a line: run one full test pass before declaring done. Result: ignored. In headless runs the model completes a "simple-looking" function in one shot and never reads the ceremony into action.
2. **Attempt 2 — definition of done.** Stronger wording ("no exceptions", boundary-case checklist). Result: still ignored. A context probe confirmed the instructions were loaded — seen and skipped.
3. **Attempt 3 — enforcement in the harness.** A hook, `stop-verify.js` (~100 lines): on Stop, if the session edited code files but never executed anything afterwards, block once and demand a real run with root-cause fixes. Deterministic, once per session, loop-safe. This is the one that fired.

That is the project's thesis in miniature: as models get stronger, prose process gets skipped; the two places a harness still earns its keep are knowledge the model cannot have (memory, conventions) and a few deterministic enforcement points (verification).

### Standard HumanEval hard subset

{101, 144}, 5 trials/arm. Baseline screen: 162/164 clean.

| Arm | pass@1 | HumanEval/101 | HumanEval/144 |
|-----|--------|---------------|---------------|
| Baseline (pure model) | 4/10 (40%) | 0/5 | 4/5 |
| With superskills | 5/10 (**50%**) | 0/5 | 5/5 |

### HumanEval+ (EvalPlus) hard subset — six optimization rounds

The EvalPlus hard subset is where the enforcement hook is supposed to pay off, so it got the most attention. Six rounds:

**Rounds 1–3 — tuning the hook's reason wording.** The first measurement screened only the 100–163 half and found a 5-problem set ({101, 132, 151, 154, 163}); arm B scored 4/15 (27%) there. Three rounds then tried to lift it by rewording the block reason. Same subset, arm B, 3 trials each:

| Reason version | Words | EvalPlus hard pass@1 |
|----------------|-------|----------------------|
| Round 1 — concise (examples, empty, spec-implied boundaries, fix at root) | ~80 | **4/15 (27%)** |
| Round 2 — longer (add: derive-expected-independently, paste-output, emphatic caps) | ~120 | 2/15 (13%) |
| Round 3 — trimmed, keep only "derive the expected value yourself" | ~75 | 3/15 (20%) |

More instruction made it worse. The longer reason pushed even the one reliably-won problem down (154: 3/3 → 2/3): a single-turn model that already believes the task is trivial skims a wall of verification ceremony and says "all passed" faster, not more carefully. The shipped reason is Round 1's — the optimum was the first, simplest version. Less is more, measured.

**Rounds 4–6 — full-range re-screen, escalating sample size.** The 100–163 half is an unrepresentative slice, and any small set is noisy. So round 4 re-screened the *full* 0–163 range under EvalPlus, building the complete hard set the honest way — every problem the baseline fails, no manual picking. That set is 11 problems ({21, 32, 44, 76, 91, 101, 132, 134, 151, 154, 163}). Rounds 5–6 re-measured it at growing sample size, because the delta was noisy: 3 trials/arm read +15pp, 5 trials read +7pp, and the 8-trial aggregate (rounds 4 and 5 combined) settles it.

| Arm | EvalPlus full-range hard pass@1 (11 problems, 8 trials/arm) |
|-----|--------|
| Baseline (pure model) | 18/88 (20.5%) |
| With superskills | 27/88 (**30.7%**), **+10.2pp** |

Per problem, arm B converts the verification-detectable class and hits a wall on the reasoning class:

- **Clear wins** — HumanEval/154 (a correct-but-untested boundary bug) 0/8 → **6/8** is the flagship; plus 76 (n=1 edge) 0→3, 91 0→2, 44 6→7.
- **One real regression** — 32 (polynomial root-finding) 5/8 → 2/8: forced verification on a problem the baseline usually gets right made the model worse, not better — the same effect the wording rounds found (more enforcement ≠ more correctness for a single-shot model), now visible per problem. 134 was a tie (7/8 both arms); its apparent 5-trial loss was noise.
- **Hard wall** — 21 (all-equal degenerate input → division by zero), 101/151/163 (a trailing-separator default the docstring never states), 132 (`is_nested`, a misunderstood algorithm): both arms 0/8. Enforcement can make a model verify; it cannot make a single-shot model invent an unstated default, handle a degenerate case it never imagined, or repair an algorithm it got wrong.

The honest reading across six rounds: superskills' verify hook reliably converts the **boundary-bug class** (implementation correct, untested — 154 is the flagship) and hits a hard ceiling on the **reasoning class** (degenerate inputs, unstated defaults, wrong algorithms), with one measured regression where forced verification cost a correct answer. HumanEval+ is the regime where a harness has the *least* leverage — single-shot, single-function, no cross-session memory to recall, no multi-turn clarification, no team conventions in play — and there the net is a modest, honest +10pp. The gains superskills is built for live on the capability suite (+60–80pp), not here.

## MBPP+: a second community benchmark

To test whether the verify hook's benefit generalizes and to grow the sample, a second EvalPlus community set — **MBPP+** (same single-function dimension, larger pool) — was added. Same method: screen 0–79 → a 10-problem hard set, 6 trials/arm:

| Arm | MBPP+ hard pass@1 (10 problems, 6 trials) |
|-----|--------|
| Baseline (pure model) | 13/60 (21.7%) |
| With superskills | 15/60 (25.0%), **+3pp** |

A small positive gain, same direction as HumanEval+ but smaller: the verify hook converts boundary bugs here too, but MBPP+ has more algorithm problems where forced verification over-corrects a borderline-right solution (e.g. 56 `eulerian_num`), offsetting part of the gain. At 3 trials it read −3pp — noise; at 6 trials it stabilizes at +3pp, confirming small samples are not trustworthy.

## SWE-bench Lite: a third community benchmark (real multi-file repos)

With Docker installed, the third — and on paper the highest-harness-leverage — community benchmark was added: **SWE-bench Lite**, real GitHub issues fixed across multi-file repositories, graded by the official `swebench` Docker harness on hidden FAIL_TO_PASS + PASS_TO_PASS tests.

The method matches the single-function sets, but each instance gets a **runnable environment**: the repo is checked out at `base_commit` with the project installed editable plus an era-appropriate pytest, so the model can actually reproduce the bug and run tests. Arm A is the pure model; arm B drops superskills into the checkout's `.claude/` (4 skills + 3 hooks). The model patch (git diff, with superskills and venv droppings excluded) is graded by the official harness, pass@1. The subset is 11 gold-validated instances — the ones whose gold patch resolves in this machine's arm64 Docker grader (12 were attempted; pylint ×3 dropped because their instance image fails to build on arm64, requests ×1 because its tests need real network and even gold scores 2 failed / 108 errors).

| Arm | SWE-bench Lite pass@1 (11 gold-validated instances) |
|-----|--------|
| Baseline (pure model) | 6/11 (54.5%) |
| With superskills | 6/11 (**54.5%**) |

**Exact parity, and the same 6 instances are resolved** — the 5 both fail are identical too. superskills changes nothing about *which* problems get solved.

The mechanism is clean: SWE-bench's acceptance tests are **hidden** from the model. On agentic multi-file tasks Sonnet already runs the visible suite on its own — across the 12 baseline arm-B sessions the model ran pytest **12/12**, while `stop-verify.js` fired **0/12** (it only triggers when code was edited but never executed, which never holds, so the verify hook is **dormant** here). Even when it does fire it can only force runs against *visible* tests, which cannot close the gap to a hidden acceptance criterion.

To empirically confirm no lever helps, two optimization variants targeting different mechanisms were run, each re-generating only arm B:

| Variant | SWE-bench Lite pass@1 | vs baseline |
|---------|--------|--------|
| Shipped superskills | 6/11 | parity |
| + generic bug-fix conventions (reproduce first, root cause, edges, check regressions) | 6/11 | same set, a reasoning-aid prompt gains nothing |
| Forced verify hook (reproduce-the-issue + regression check even after the model tested; fired on all 11) | 6/11 | same set, forced extra verification gains nothing |

All four configurations (pure model, shipped, +conventions, forced verify) **converge on the identical 6/11** — even the strongest verify lever, firing on all 11 instances, moved nothing. Honest conclusion: on SWE-bench superskills is at **structural parity**. With acceptance criteria hidden the verify hook has nothing to bite; memory / clarify / discover-conventions don't apply within a single fresh-repo session; the bottleneck is producing the *correct* fix for the 5 hard instances, which is not something superskills provides. This completes the three-benchmark picture: **the lift tracks whether the acceptance criteria are visible to the model and whether the knowledge lives outside the repo code** — HumanEval+ (visible examples + implied boundaries) +10pp, MBPP+ +3pp, SWE-bench (hidden acceptance) even. No shipped config was changed (conventions and the variant hook are experiment-only), so the HumanEval+/MBPP+ numbers hold by construction — no regression.

## Optimization loop: no free lunch

With the combined pass@1 over both community sets as the north star, several verify-reason variants were measured, keeping a change only if it net-improved:

| Reason variant | Combined hard pass@1 (HumanEval+ ∪ MBPP+, 3 trials) |
|----------------|--------|
| R1 concise (shipped) | **19/63 (30.2%)** |
| R2 longer (derive-expected, paste-output, emphatic caps) | lower (13% in the early HumanEval+ test) |
| R3 trimmed | lower (20%) |
| Lever E anti-over-correction (fix only against stated examples) | 19/63 (30.2%) — exact wash; HumanEval+ up, MBPP+ down |
| Lever G minimal (run examples + a few edges) | 16/63 (25.4%) — worse; loses boundary-bug wins |

Of five variants the shipped R1 is the optimum: more aggressive/verbose makes a single-shot model skim, more conservative/minimal misses boundary bugs or cancels the gain. The verify hook's aggression is a tradeoff dial with no net win — it is at its mechanism ceiling. Honest conclusion: on the single-function coding where a harness has the least leverage, the verify hook is a small, benchmark-dependent net positive (+3 to +10pp) from the boundary-bug class, partly offset by occasional algorithm over-correction.

## Reproducing

```bash
./tests/bench/freeze-specs.sh                    # optional: regenerate arm-B specs via the real discover skill
./tests/bench/run.sh --trials 3                  # capability suite (S1–S4 + control)
./tests/bench/heval-hard.sh                      # standard HumanEval hard subset: screen + measure
./tests/bench/heval-hard.sh --plus --screen-range 0:163 --rescreen   # HumanEval+ full-range hard subset
./tests/bench/heval-hard.sh --mbpp --screen-range 0:79 --rescreen    # MBPP+ hard subset (second community benchmark)
./tests/bench/swe-bench.sh --subset-file tests/bench/swebench/subset-lite.txt   # SWE-bench Lite A/B (third community benchmark, needs Docker)
```

Prerequisites: `claude` CLI logged in, Node ≥ 18, Python 3; SWE-bench additionally needs Docker (daemon able to reach the image registry directly), `uv`, and `swebench` installed once into a `uv venv`. On Apple Silicon, swebench 4.x hardcodes x86_64 (unusably slow under QEMU), so `swebench/swe_eval.py` switches image builds back to native arm64. Important: the superskills plugin must **not** be installed at user scope while `heval-hard.sh` or `swe-bench.sh` runs — the local `directory` marketplace would load live repo files into every baseline trial and contaminate arm A. The scripts give arm B its own in-fixture `.claude/`, so a global install is both unnecessary and harmful here.

# Auto-learning: why a Stop hook

[中文](auto-learning-design.md)

superskills does auto-learning with a single ~100-line Stop hook. A natural objection: to capture the lessons in a session, why not observe at every tool call (PreToolUse/PostToolUse) and mine them offline with a background process? This note explains the design choice and the benchmark data behind it — it is "Less is more" applied to one decision.

## Two designs

There are two ways to capture session lessons:

- **Observation-based**: record input/output on every tool call, append to a per-project observation log, and have a background agent cluster the raw observations into confidence-scored "instincts." The upside is capture completeness — every tool call, every error→fix micro-pattern, plus cross-session offline mining.
- **Judge-at-session-end** (what superskills does): decide exactly once, when the session stops.

The price of observation-based capture is visible all over such an implementation: an observe script spawned on *every* tool call; a background process with a PID file, signal throttling, and a re-entrancy guard; observation-log rotation by size; a multi-layer guard to stop automated/sub-agent sessions from polluting the data; secret redaction on the captured stream. That is a powerful system. It is not a minimal one.

## Why superskills judges at session end

Three distinctions make the observation-based rationale not apply here:

1. **It was never probabilistic.** superskills' `stop-learn` is a deterministic hook — it fires every time the session stops. The exact problem observation-based capture is often introduced to solve (probabilistic triggers miss patterns) superskills never had.

2. **No second copy of the session is needed.** An observation log exists to get tool-level micro-patterns and cross-session offline clustering. superskills wants only the durable, code-invisible facts — user corrections, pitfalls, decisions. Those are already in the transcript Claude Code persists continuously (`transcript_path`). The Stop hook reads it. No second capture stream, no rotation, no background process.

3. **The failure mode it would fix is low-value here.** PreToolUse/PostToolUse survive a hard crash mid-session; a Stop hook may not fire if the process is killed. But superskills only learns from sessions that did real work, and a missed crash just means the next similar session re-surfaces the lesson. Paying for the whole apparatus to insure a rare, low-cost miss is exactly the trade "Less is more" refuses.

So the design is a ~100-line deterministic Stop-hook filter (enough messages, files actually changed, once per session, loop-safe) that decides only *whether* the session is worth mining, and hands *what to keep* to the main model, which already holds the full session — with explicit permission to keep nothing. Zero background processes, zero observation files, zero guards.

## The blind spot this question exposed

There was a real gap. The capability benchmark's S2 scenario measures whether the model *uses* learnings that already exist (a hand-authored fixture). It never measured whether `stop-learn` *generates* good learnings in the first place — the upstream half of the loop.

So this adds an **auto-learning generation benchmark** (`tests/bench/learn-auto.sh`): replay a finished session containing two corrections that exist only in the dialogue (ISO-8601 UTC timestamps; integer cents), append the **real** block-reason emitted by `stop-learn.js`, and grade the `.superskills/learnings/` the model actually writes — did it capture both rules, update the index, keep the format, stay concise. Arm A sees the same session with a neutral close (no hook reason); the gap is what the hook contributes.

## Results

### Round 1 — standard difficulty (3 trials/arm, Sonnet 4.6)

One finished session, two corrections stated only in dialogue (ISO-8601 UTC timestamps; integer cents).

| Metric | Baseline (neutral close) | With superskills (stop-learn) |
|--------|--------------------------|-------------------------------|
| Mean score | **0%** | **100%** |
| Generated a learning file | 0/3 | 3/3 |
| Captured the ISO-8601 rule | 0/3 | 3/3 |
| Captured the integer-cents rule | 0/3 | 3/3 |
| Updated INDEX.md | 0/3 | 3/3 |
| Frontmatter + body format | 0/3 | 3/3 |
| Concise (≤3 files) | 0/3 | 3/3 |

The pure model never persists anything on its own — it finishes the task and stops. The Stop-hook reason flips that completely: every trial captured both code-invisible decisions, indexed and formatted, without over-stuffing. This is the *generation* half of the loop that S2 only measured the *consumption* half of.

### Round 2 — precision under noise (3 trials/arm)

Standard difficulty saturates, so round 2 raises it the way HumanEval+ does: a noisy session that mixes one genuine, code-review-enforced team convention (API error codes must use the `E_` prefix) with two throwaway instructions that must NOT be persisted ("skip validation, I'll add it later"; "log to console just for today"). This tests *precision* — capture the durable rule, reject the one-offs — exactly where a too-eager "persist corrections and decisions" instruction can over-learn.

| Metric | Baseline (neutral close) | With superskills (stop-learn) |
|--------|--------------------------|-------------------------------|
| Mean score | **0%** | **100%** |
| Generated a learning file | 0/3 | 3/3 |
| Captured the `E_` prefix convention | 0/3 | 3/3 |
| Rejected the "skip validation" one-off | 0/3 | 3/3 |
| Rejected the "log for today" one-off | 0/3 | 3/3 |
| Updated INDEX.md | 0/3 | 3/3 |
| Frontmatter + body format | 0/3 | 3/3 |
| Concise (≤2 files) | 0/3 | 3/3 |

Every superskills trial persisted **exactly one** learning — the `E_` prefix convention, with Context/Rule/Why — and left both throwaway instructions out. Precision and recall are both 3/3: the model that holds the full session distinguishes a code-review-enforced team rule from "skip validation, I'll do it later" without any confidence-scoring machinery. The pure model again persisted nothing.

(Method honesty: the first hard run scored the baseline at 29% because the `reject-*` checks gave an empty arm A free credit for "not leaking." That is not precision, it is silence — the checks were gated on actually generating a file and the round re-run. 0% is the corrected baseline.)

### What the two rounds say

Both rounds saturate in superskills' favor — standard recall 0% → 100%, hard precision 0% → 100%. The optimization result is the *absence* of a needed change: the data says the current design (a deterministic Stop hook plus full-context model judgment) already maxes out both recall and precision, so adding observation-based capture, a background analyzer, and confidence scoring would add real cost without moving these numbers. For superskills, "Less is more" is not a slogan here — it is what the benchmark told us to keep.

## A known limitation, kept honest

In headless single-turn `claude -p`, the hook's "≥5 user messages" gate never trips — there is only one turn. That is by design (the hook targets interactive multi-turn sessions, where corrections actually accumulate), but it means automated single-shot runs do not auto-learn. The benchmark above drives generation through the real hook reason rather than pretending otherwise.

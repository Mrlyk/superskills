# Auto-learning: why a Stop hook, run in the background more than once

[中文](auto-learning-design.md)

superskills does auto-learning with a single Stop hook. Two natural objections: (1) to capture the lessons in a session, why not observe at every tool call (PreToolUse/PostToolUse) and mine them offline with a background process? (2) once you decide to judge at Stop, why not just do it inline on the main thread and summarize once? This note explains both design choices and the benchmark data behind them — "Less is more" applied to one decision.

## Two ways to capture

There are two ways to capture session lessons:

- **Observation-based**: record input/output on every tool call, append to a per-project observation log, and have a background agent cluster the raw observations into confidence-scored "instincts." The upside is capture completeness — every tool call, every error→fix micro-pattern, plus cross-session offline mining.
- **Stop-hook judgment** (what superskills does): open no second capture stream — read the transcript Claude Code already persists continuously, and let the full-context model decide what to keep.

The price of observation-based capture is visible all over such an implementation: an observe script spawned on *every* tool call; a background process with a PID file, signal throttling, and a re-entrancy guard; observation-log rotation by size; a multi-layer guard to stop automated/sub-agent sessions from polluting the data; secret redaction on the captured stream. That is a powerful system. It is not a minimal one.

## Why a Stop judgment, not per-tool observation

Three distinctions make the observation-based rationale not apply here:

1. **It was never probabilistic.** superskills' `stop-learn` is a deterministic hook — it fires every time the session stops. The exact problem observation-based capture is often introduced to solve (probabilistic triggers miss patterns) superskills never had.

2. **No second copy of the session is needed.** An observation log exists to get tool-level micro-patterns and cross-session offline clustering. superskills wants only the durable, code-invisible facts — user corrections, pitfalls, decisions. Those are already in the transcript Claude Code persists continuously (`transcript_path`). The hook reads it. No second capture stream, no rotation, no observation machinery.

3. **The failure mode it would fix is low-value here.** PreToolUse/PostToolUse survive a hard crash mid-session; a Stop hook may not fire if the process is killed. But superskills only learns from sessions that did real work, and a missed crash just means the next similar session re-surfaces the lesson. Paying for the whole observation apparatus to insure a rare, low-cost miss is exactly the trade "Less is more" refuses.

So *what to keep* always goes to the model that already holds the full session — with explicit permission to keep nothing; the hook does one thing: judge *whether* the session is worth mining (enough messages, files actually changed, loop-safe). Zero observation files, zero per-tool capture, zero confidence scoring.

## Execution model: background and repeating, not inline and once

Judging at Stop is right, but *how that judgment runs* is a separate choice — and the first version got half of it wrong.

The first version used `decision:block` to inject the summary instruction **inline** back into the main conversation, and fired **once per session**. Two real costs:

- **It occupied the user's main thread.** The user waited while the model did bookkeeping — visible, and blocking the finish.
- **Once-per-session under-covers.** After the first trigger, no matter how many more turns or edits followed, the session never summarized again — everything in the back half was never learned.

The fix keeps the exact same judgment (read the transcript, full-context model decides what to keep) and changes only *where it runs and how often*:

- **Off the main thread.** On qualifying work, spawn a detached `claude -p` learner that reads a session replay and writes the wiki, returning immediately without blocking the user.
- **Re-fire as the session grows.** A per-session cursor throttles it: roughly every 5 new user messages (or a batch of new file edits), it triggers again, so a long session gets several incremental summaries — closing the post-first-trigger coverage gap.

This is ECC's async-non-blocking philosophy — background, non-blocking, fired at more than one moment — but it **still only reads the ready-made transcript; it does not observe per tool call**. So yes, this adds one background process: a single learner *executing the Stop judgment* off-thread, not the observation pipeline we rejected.

Four guards keep it bounded: `SUPERSKILLS_LEARN_CHILD=1` stops the background learner from triggering its own learner (anti-recursion); a single-flight lock (default 90s) keeps two learners from writing the same wiki at once; `SUPERSKILLS_NO_BG_LEARN=1` disables it entirely; and when no `claude` binary is reachable on the hook's PATH it falls back to the old inline once-per-session block. The instruction text lives in `plugins/superskills/hooks/learn-prompt.js` as a single source of truth that both the hook and the learn-auto/learn-wiki benchmarks read, so the benchmark always tests the exact shipped instruction.

## The blind spot this exposed

The upstream half of the loop used to go untested: the capability benchmark's S2 scenario measures whether the model *uses* learnings that already exist (a hand-authored fixture). It never measured whether `stop-learn` *generates* good learnings in the first place.

So this adds an **auto-learning generation benchmark** (`tests/bench/learn-auto.sh`): replay a finished session containing corrections that exist only in the dialogue, append the shipped `stop-learn` instruction (the benchmark uses `SUPERSKILLS_LEARN_DRYRUN=1` to make the hook print that instruction), and grade the `.superskills/learnings/` the model actually writes — did it capture the rules, update the index, keep the format, stay concise. Arm A sees the same session with a neutral close (no hook instruction); the gap is what the hook contributes.

## Results

### Standard difficulty — recall (3 trials/arm, Sonnet 4.6)

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

The pure model never persists anything on its own — it finishes the task and stops. The Stop-hook instruction flips that completely: every trial captured both code-invisible decisions, indexed and formatted, without over-stuffing.

### Precision under noise (3 trials/arm)

Standard difficulty saturates, so this raises it the way HumanEval+ does: a noisy session that mixes one genuine, code-review-enforced team convention (API error codes must use the `E_` prefix) with two throwaway instructions that must NOT be persisted ("skip validation, I'll add it later"; "log to console just for today"). This tests *precision* — capture the durable rule, reject the one-offs — exactly where a too-eager "persist corrections and decisions" instruction can over-learn.

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

Every superskills trial persisted **exactly one** learning — the `E_` prefix convention — and left both throwaway instructions out. Precision and recall are both 3/3: the model that holds the full session distinguishes a code-review-enforced team rule from "skip validation, I'll do it later" without any confidence-scoring machinery. The pure model again persisted nothing.

(Method honesty: the first round of the background rewrite scored both modes at 94%/95% — the only miss was the INDEX.md markdown-link check (2/3). Adding the index format the learn skill already documents, `- [Topic](topic.md) — summary`, to the shipped instruction restored both modes to 100%. That is a real instruction hardening that helps production too, not benchmark-gaming. Separately, the earliest hard run scored the baseline at 29% because the `reject-*` checks gave an empty arm A free credit for "not leaking" — that is silence, not precision; gated on actually generating a file, 0% is the corrected baseline.)

## What the numbers say

Recall and precision both saturate in superskills' favor — 0% → 100%. On *that* axis the optimization result is the *absence* of a needed change: the current design (deterministic Stop trigger plus full-context model judgment) already maxes out *what to keep*, so adding observation-based capture, background clustering, and confidence scoring would add cost without moving these numbers.

The background-and-repeating change is on a **different axis** — main-thread intrusion and the once-per-session coverage gap — orthogonal to recall/precision, so it does not contradict that saturation. That axis is verified on its own: the hook's re-fire-as-the-session-grows behavior is covered by a deterministic case in `tests/test-hooks.sh` (same session triggered twice: the old once-per-session marker fires once, the new cursor throttle fires again).

## Known limitations, kept honest

- **The once-per-session coverage gap is closed.** That was the point of moving to background-and-repeating: work after the first summary now gets learned incrementally too.
- **Headless single-turn `claude -p` still won't auto-learn.** The "≥5 user messages" gate never trips in a one-turn automated run — by design (the hook targets interactive multi-turn sessions, where corrections accumulate). The benchmark above drives generation through the real hook instruction rather than pretending otherwise.
- **The background learner spends tokens the user did not directly request.** Every trigger is a fresh `claude -p`. The cursor throttle, single-flight lock, and `SUPERSKILLS_NO_BG_LEARN=1` switch bound the cost; `SUPERSKILLS_LEARN_MODEL` can point it at a cheaper model.
- **It depends on `claude` being reachable on the hook's PATH.** When it is not, it falls back to the old inline once-per-session block — the feature is not lost, it just reverts to the intrusive form.

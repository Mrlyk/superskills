# Learnings as a topic wiki

[中文](learnings-wiki.md)

## Background

superskills first organized auto-learnings as "one dated file per learning" (`<date>-<slug>.md` + `INDEX.md`). As knowledge accumulates, rules about the same topic scatter across many dated files — easy to duplicate, noisier to retrieve. The alternative is a wiki organization: one page per topic, where a new learning is merged into its topic page, deduplicated and cross-linked, with `INDEX.md` as the catalog.

## Design

`.superskills/learnings/` becomes topic-page organized:

- `<topic>.md`: one page per topic (frontmatter `topic/tags` + concise rules + `[[topic]]` cross-links). A new learning is merged into the existing topic page; a new page is created only when no topic fits, and a rule already living on another page is never duplicated.
- `INDEX.md`: the catalog, one line per topic — the only file injected into future sessions.
- No `log.md`: chronology comes from git history; for superskills' small knowledge base a separate chronological log is needless overhead.

Keeping the existing `INDEX.md` convention means the SessionStart injection and the discover refresh are unaffected, existing dated files still get read, and new learnings accumulate as topic pages.

## Benchmark: flat vs wiki

Same model (Sonnet 4.6), deterministic graders, flat (dated files) vs wiki (topic pages), 3 trials per cell, iterated round by round:

| Round | Scenario | flat | wiki |
|-------|----------|------|------|
| 1 | Accumulation: add a timestamps-extending learning to a 3-topic KB | 60% | **100%** |
| 2 | Simple: 2 unrelated corrections, bootstrap from empty | 100% | 100% |
| 3 | Precision under noise: 1 team rule + 2 throwaway one-offs | 100% | 94% |
| 4 | Precision under noise (optimized) | 94% | 94% |
| 4 | Accumulation (optimized) | 60% | **100%** |

Accumulation is where the wiki earns its keep: flat scatters same-topic knowledge into a new dated file (consolidated 0/3, noDuplication 0/3, 4-file KB), while wiki merges it into the topic page (consolidated 3/3, noDuplication 3/3, 3 files) without losing old knowledge (preserved 3/3) or missing the new rule (capturedNew 3/3). The simple case ties at 100% with wiki denser (1 content page vs 2 dated files). Precision ties within noise — neither arm leaks the throwaways.

## Optimization iterations

In round 3's noisy scenario the wiki missed the `index` update in 1/3 trials — the cost of its extra steps (topic page + index + log). Round 4 applied subtraction to the wiki itself: drop `log.md`, and make the `INDEX.md` update mandatory and salient ("the only file injected into future sessions, so a page missing from it is invisible"). Index upkeep recovered to 3/3, precision matched flat, accumulation stayed 100%. The optimum is the leaner wiki — Less is more applies to the wiki too.

## Conclusion

Topic-wiki organization is markedly better at knowledge accumulation (+40pp) and no worse elsewhere. superskills adopts it: `stop-learn` and the learn skill now "merge into a topic page + maintain the `INDEX.md` catalog," with no `log.md`. Reproduce:

```bash
tests/bench/learn-wiki.sh            # accumulation: flat vs wiki
tests/bench/learn-wiki.sh --simple   # empty-KB bootstrap + recall
tests/bench/learn-wiki.sh --hard     # precision under noise
```

---
name: learn
description: Persist durable learnings from the current session (user corrections, pitfalls and fixes, project decisions not visible in code) into the project knowledge wiki at .superskills/learnings/. Use when the user asks to summarize or persist learnings, or when triggered automatically at session end.
---

# Learn (wiki)

Maintain the project's knowledge as a **wiki**, not a pile of dated entries. The wiki lives at the repository root in `.superskills/learnings/` and is organized by **topic pages**: each page collects everything known about one topic, deduplicated and cross-linked. One file supports navigation: `index.md`, a by-category catalog with one line per topic. (Chronology comes from git history, so there is no separate log.)

## What qualifies

Persist only items matching at least one of:
- The user corrected your approach (default behavior differed from what they wanted)
- A pitfall and its fix that would cost time to rediscover
- A project convention or decision that cannot be inferred from the code itself

Do NOT persist: one-off task details, facts readable from the code, generic programming knowledge.

## Steps

1. Review the session and list candidate learnings. If none qualify, say so and stop — write nothing.
2. Read `index.md` to see the existing topic pages.
3. For each learning, **find the topic page it belongs to and merge the rule into that page** — keep the page focused, remove redundancy, and cross-link related topics with `[[topic]]`. Only create a new `<topic>.md` page when no existing topic fits. Never duplicate a rule that already lives on another page.
4. **Always** update `index.md` so it lists every topic page with a one-line summary, grouped by category — `index.md` is the only file loaded into future sessions, so a page missing from it is invisible.

Prefer editing an existing page over adding a file. The wiki should get denser, not longer, as knowledge accumulates. Keep `index.md` a tight, navigable catalog. Suggest committing `.superskills/` so the team shares the knowledge.

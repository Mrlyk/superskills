---
name: ss-learn
description: Persist durable learnings from the current session (user corrections, pitfalls and fixes, project decisions not visible in code) into .superskills/learnings/. Use when the user asks to summarize or persist learnings ("总结一下经验", "沉淀一下", "记住这个"), or when triggered automatically at session end.
---

# Learn

Extract knowledge worth keeping from this session and write it into the project's `.superskills/learnings/`.

## What qualifies

Persist only items matching at least one of:
- The user corrected your approach (default behavior differed from what they wanted)
- A pitfall and its fix (error → root cause → solution) that would cost time to rediscover
- A project convention or decision that cannot be inferred from the code itself

Do NOT persist: one-off task details, facts readable from the code, generic programming knowledge.

## Steps

1. Review the session and list candidate learnings. If none qualify, say so and stop — do not write anything.
2. Read `.superskills/learnings/INDEX.md` (if present). If an existing entry already covers a candidate, update that file in place instead of creating a duplicate.
3. Write each new learning to `.superskills/learnings/YYYY-MM-DD-<slug>.md` (create directories as needed):

   ```markdown
   ---
   title: <one-line title>
   date: YYYY-MM-DD
   tags: [<area>]
   ---
   **Context**: when this applies
   **Rule**: what to do (1-2 sentences)
   **Why**: the reason (optional, one sentence)
   ```

4. Update `.superskills/learnings/INDEX.md` — one line per entry:
   `- [<title>](<filename>) — <when it applies>`

Keep each learning under 15 lines. The INDEX is what gets auto-injected into future sessions, so write titles and contexts that make relevance obvious at a glance. Suggest committing `.superskills/` so the team shares the knowledge.

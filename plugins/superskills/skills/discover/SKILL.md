---
name: discover
description: Discover an existing project's conventions and generate or refresh minimal AI spec files (.superskills/conventions.md, AGENTS.md, CLAUDE.md). Use when a project lacks AGENTS.md/CLAUDE.md, when the user asks to generate conventions ("生成规范", "init ai docs", "discover conventions"), or when conventions are reported stale.
---

# Discover Conventions

Generate or refresh the project's AI-facing spec files. Keep everything short — these files load into every session, so every line costs tokens forever.

## Scan (read evidence, don't guess)

- Manifests and configs: package.json / pyproject.toml / go.mod / Cargo.toml / pom.xml, lockfiles, linter/formatter/tsconfig, CI files
- Existing docs: README, CONTRIBUTING, docs/, existing AGENTS.md / CLAUDE.md / editor rules
- Code sample: 3-5 representative source files plus 1-2 test files; note naming, module structure, error handling, test style
- Git: `git log --oneline -20` for the commit message convention

## Write

1. `.superskills/conventions.md` — single source of truth, max 80 lines:
   - **Commands**: install / build / test / lint, the real ones from manifests
   - **Structure**: one line per top-level directory that matters
   - **Conventions**: only rules evidenced in code or docs — naming, imports, error handling, test layout, commit style
   - **Don'ts**: only if evidenced (e.g. a lint rule or doc forbids it)

   Every line must be project-specific and evidenced. Drop generic advice ("write clean code"). Prefer one line over three.

2. `AGENTS.md` (if missing) — max 20 lines: one-paragraph project description, key commands, then exactly these pointers:
   - `Read .superskills/conventions.md before writing code.`
   - `Check .superskills/learnings/INDEX.md for past learnings; read a linked entry when relevant.`
   - `If anything in a request is unclear, do not guess — proactively trigger the superskills clarify skill to ask before coding; when the request is already specific, just implement.`
   - `Before reporting any coding task as done you must have executed the changed code: run the documented examples plus boundary cases (empty, extreme, malformed, repeated/trailing input) via the test suite or a throwaway script you then delete, fix failures at root cause, and include the run output in your final reply. For larger changes apply the superskills test skill.`

   If AGENTS.md exists, only append the pointer lines when missing. Never rewrite existing user content.

3. `CLAUDE.md` (if missing) — exactly these imports:

   ```
   @AGENTS.md
   @.superskills/conventions.md
   ```

   If it exists, append missing imports only.

4. `.superskills/learnings/INDEX.md` — create with a `# Learnings` header if missing.

## Refresh mode

If `.superskills/conventions.md` already exists:
- Diff reality against it (recent commits, new configs, changed structure); update changed lines only, keep it within 80 lines.
- Fold learnings from `.superskills/learnings/` that have hardened into stable conventions directly into conventions.md, then delete those learning files and their INDEX lines.

Finish by suggesting a commit of `.superskills/`, `AGENTS.md`, and `CLAUDE.md`.

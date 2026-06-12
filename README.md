# superskills

**Less is more.** A minimal coding harness for Claude Code, Codex, and Aone Copilot: 4 skills, 2 hooks, 1 install script. Nothing else.

[中文文档](README.zh-CN.md)

## Why

Heavyweight harnesses made sense when models needed guardrails at every step: hard process gates, multi-stage reviews, forced TDD loops. As models get stronger, most of that scaffolding turns into overhead. What still compounds in value:

1. **Memory** — learnings from past sessions (corrections, pitfalls, decisions) that no model can infer from code
2. **Conventions** — a minimal, evidenced spec of how this project actually works
3. **Clarification** — resolving the genuinely undecided parts of a request before coding
4. **A final test pass** — verified behavior, without ritualizing the path there

superskills keeps exactly these four things and deletes everything else.

## What you get

| Component | Kind | What it does |
|-----------|------|--------------|
| `ss-discover` | skill | Scans an existing project and generates minimal spec files: `.superskills/conventions.md` (≤80 lines), `AGENTS.md`, `CLAUDE.md`. Also refreshes them when stale. |
| `ss-learn` | skill | Persists durable learnings (user corrections, pitfalls + fixes, invisible decisions) to `.superskills/learnings/`. |
| `ss-clarify` | skill | Surfaces only the questions whose answers change the implementation, with recommended answers, then starts coding. |
| `ss-test` | skill | One full unit-test pass after development is done. Result-driven, no fixed process. |
| `session-start.js` | hook | Injects the learnings index into each session; reminds you when conventions drift >30 commits behind HEAD; suggests `ss-discover` for projects with no AI specs. |
| `stop-learn.js` | hook | Auto-learning: when a session did real work (≥5 user messages and file edits), asks the model once — with full session context — to persist anything durable before stopping. |

### Project artifacts (committed to your repo)

```
.superskills/
├── conventions.md        # single source of truth, ≤80 lines
└── learnings/
    ├── INDEX.md          # one line per learning, auto-injected at session start
    └── 2026-06-12-use-pnpm.md
AGENTS.md                 # ≤20 lines, points at .superskills/
CLAUDE.md                 # @AGENTS.md + @.superskills/conventions.md
```

## How knowledge flows back in

Two channels, chosen so the core works even without hooks:

- **Conventions** load through file references: `CLAUDE.md` imports them for Claude Code and Aone Copilot; `AGENTS.md` instructs Codex to read them. Zero hook dependency, works in every tool.
- **Learnings** load as an index via the SessionStart hook (Claude Code / Aone Copilot). The model reads a one-line-per-entry index and opens a full entry only when relevant — past knowledge costs a few hundred tokens, not thousands.

Learnings that harden into stable rules get folded into `conventions.md` by `ss-discover`'s refresh mode, keeping the knowledge base from growing forever.

## Auto-learning design

Compared to observation-based systems (ECC-style PreToolUse/PostToolUse capture plus background analyzers), superskills moves the judgment to the one moment it is cheap and reliable: session end. The Stop hook is a ~100-line filter that decides only *whether* the session is worth mining (enough messages, files actually changed, once per session, never loops); the model — which already holds the full session in context — decides *what* is worth keeping, with explicit permission to keep nothing. No observation files, no background processes, no per-tool-call overhead. And the output lands in the repo, so the whole team inherits it.

## Install

```bash
git clone https://github.com/Mrlyk/superskills.git
cd superskills
./install.sh              # autodetects ~/.claude, ~/.codex, ~/.aone_copilot
```

Options:

```bash
./install.sh --tools claude,codex,aone   # pick tools explicitly
./install.sh --all                       # install for all three
./install.sh --uninstall                 # clean removal (user settings preserved)
```

| Tool | Skills | Hooks (auto-learning + injection) |
|------|--------|------|
| Claude Code | `~/.claude/skills/ss-*` | yes |
| Aone Copilot | `~/.aone_copilot/skills/ss-*` | yes |
| Codex | `~/.codex/prompts/ss-*.md` (custom prompts) | no — relies on `AGENTS.md` pointers |

Then, in each project:

```
> use the ss-discover skill
```

Review the generated files, commit them, done.

## Testing

```bash
tests/run.sh           # hook unit tests + installer tests (no model calls)
tests/run.sh --bench   # plus a real end-to-end benchmark driving `claude -p`
```

The benchmark builds a throwaway fixture project, runs the real `ss-discover` and `ss-learn` skills through the Claude CLI with scoped permissions, and asserts the artifacts: conventions discovered from real manifests, learnings persisted and indexed, and the index injected into a fresh session by the actual hook.

## License

MIT

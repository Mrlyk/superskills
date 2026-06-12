# superskills

**Less is more.** A minimal coding harness, shipped as a Claude Code plugin: 4 skills, 2 hooks, ~418 always-on tokens. Codex and Aone Copilot are covered by a single install script.

[中文文档](README.zh-CN.md)

## Why

Heavyweight harnesses made sense when models needed guardrails at every step: hard process gates, multi-stage reviews, forced TDD loops. As models get stronger, most of that scaffolding turns into overhead. What still compounds in value:

1. **Memory** — learnings from past sessions (corrections, pitfalls, decisions) that no model can infer from code
2. **Conventions** — a minimal, evidenced spec of how this project actually works
3. **Clarification** — resolving the genuinely undecided parts of a request before coding
4. **A final test pass** — verified behavior, without ritualizing the path there

superskills keeps exactly these four things and deletes everything else.

## Does it actually help?

Measured A/B on the same tasks, same model (Sonnet 4.6), real end-to-end runs, deterministic graders — full methodology and per-check tables in [docs/benchmark.md](docs/benchmark.md):

| Scenario | Baseline (pure model) | With superskills | Δ |
|----------|----------------------|------------------|---|
| Cross-session memory (3 team decisions persisted as learnings) | 20% | 100% | **+80pp** |
| Requirement clarification (ambiguous feature request) | 0% asked | 67% asked | **+67pp** |
| Final test pass (2 planted bugs in "just developed" code) | 40% — tests locked the bugs in | 100% — both fixed at root cause | **+60pp** |
| Convention adherence (rules scattered in docs) | 100% | 100% | 0pp, ~equal time |
| Control: HumanEval/0–9 verbatim | 10/10 | 10/10 | **no regression** |

The pattern: when the knowledge is one obvious read away in a tiny fixture, a strong model already behaves (S1, control). The gains appear exactly where superskills operates — knowledge that exists nowhere in the repo (memory), questions nobody asked (clarification), and bugs that fresh tests happily cement in place (test pass). Baseline runs wrote passing test suites around both planted bugs in 3 of 3 trials; the test skill fixed both at root cause in 3 of 3.

## What you get

| Component | Kind | What it does |
|-----------|------|--------------|
| `superskills:discover` | skill | Scans an existing project and generates minimal spec files: `.superskills/conventions.md` (≤80 lines), `AGENTS.md`, `CLAUDE.md`. Refreshes them when stale, folding hardened learnings into conventions. |
| `superskills:learn` | skill | Persists durable learnings (user corrections, pitfalls + fixes, invisible decisions) to `.superskills/learnings/`. |
| `superskills:clarify` | skill | Surfaces only the questions whose answers change the implementation, with recommended answers, then starts coding. |
| `superskills:test` | skill | One full unit-test pass after development is done. Result-driven, no fixed process. |
| SessionStart hook | hook | Injects the learnings index into each session; reminds you when conventions drift >30 commits behind HEAD; suggests `discover` for projects with no AI specs. |
| Stop hook | hook | Auto-learning: when a session did real work (≥5 user messages and file edits), asks the model once — with full session context — to persist anything durable before stopping. |

Everything shows up in the `/plugin` panel with per-component token costs. Total always-on cost: ~418 tokens.

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

## Install

### Claude Code (plugin, recommended)

```
/plugin marketplace add Mrlyk/superskills
/plugin install superskills@superskills
```

Or from the CLI: `claude plugin marketplace add Mrlyk/superskills && claude plugin install superskills@superskills`. Hooks register automatically with the plugin; nothing touches your `settings.json`.

### Codex / Aone Copilot

```bash
git clone https://github.com/Mrlyk/superskills.git && cd superskills
./install.sh              # autodetects ~/.codex and ~/.aone_copilot
```

| Tool | Skills | Hooks (auto-learning + injection) |
|------|--------|------|
| Claude Code | plugin: `/superskills:discover` etc. | yes |
| Aone Copilot | `~/.aone_copilot/skills/ss-*` | yes |
| Codex | `~/.codex/prompts/ss-*.md` (custom prompts) | no — relies on `AGENTS.md` pointers |

`./install.sh --tools claude` remains available as a legacy settings-based install for environments without marketplace access. `--uninstall` reverses everything and preserves your own settings.

Then, in each project, run the discover skill once and commit the generated files.

## How knowledge flows back in

Two channels, chosen so the core works even without hooks:

- **Conventions** load through file references: `CLAUDE.md` imports them for Claude Code and Aone Copilot; `AGENTS.md` instructs Codex to read them. Zero hook dependency, works in every tool.
- **Learnings** load as an index via the SessionStart hook (Claude Code / Aone Copilot). The model reads a one-line-per-entry index and opens a full entry only when relevant — past knowledge costs a few hundred tokens, not thousands.

Learnings that harden into stable rules get folded into `conventions.md` by `discover`'s refresh mode, keeping the knowledge base from growing forever.

## Auto-learning design

Compared to observation-based systems (PreToolUse/PostToolUse capture plus background analyzers), superskills moves the judgment to the one moment it is cheap and reliable: session end. The Stop hook is a ~100-line filter that decides only *whether* the session is worth mining (enough messages, files actually changed, once per session, never loops); the model — which already holds the full session in context — decides *what* is worth keeping, with explicit permission to keep nothing. No observation files, no background processes, no per-tool-call overhead. And the output lands in the repo, so the whole team inherits it.

## Testing

```bash
tests/run.sh              # hook + installer + plugin-structure tests (no model calls)
tests/run.sh --bench      # plus a smoke benchmark driving real `claude -p` runs
tests/bench/run.sh        # the full A/B capability benchmark (~44 model runs)
```

## License

MIT. The benchmark control group vendors HumanEval problems (MIT, OpenAI) — see [tests/bench/humaneval/ATTRIBUTION.md](tests/bench/humaneval/ATTRIBUTION.md).

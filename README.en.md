# superskills

**Less is more.** A minimal coding harness, shipped as official plugins for both Claude Code and Codex: 4 skills, 3 hooks, ~418 always-on tokens. Aone Copilot is covered by the install script.

<p align="center"><img src="assets/hero.svg" alt="superskills — Less is more: the heavyweight harness deleted, four compounding skills and the project-level memory loop kept" width="880"></p>

[中文文档](README.md)

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
| Stop hook (verify) | hook | Verify-before-done: if the session edited code but never executed it afterwards, blocks the stop once and demands a real run — documented examples plus boundary cases — with root-cause fixes. |
| Stop hook (learn) | hook | Auto-learning: when a session did real work (≥5 user messages and file edits), asks the model once — with full session context — to persist anything durable before stopping. |

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

### Codex (plugin)

```bash
git clone https://github.com/Mrlyk/superskills.git
codex plugin marketplace add ./superskills
codex plugin add superskills@superskills
```

Or run `./install.sh` inside the clone — it follows the same flow when the codex CLI supports plugins, and falls back to custom prompts on older CLIs. Keep the clone in place; Codex resolves the plugin from it.

### Aone Copilot

```bash
git clone https://github.com/Mrlyk/superskills.git && cd superskills
./install.sh              # autodetects ~/.aone_copilot (and ~/.codex)
```

### Project-level install (nothing user-global touched)

The methods above are user-level (active in every project). To enable superskills in a single project without touching your global setup, install at project scope.

Claude Code supports installation scopes natively; run inside the project:

```
/plugin marketplace add Mrlyk/superskills --scope project
/plugin install superskills@superskills --scope project
```

This writes only the project's `.claude/settings.json` (`extraKnownMarketplaces` + `enabledPlugins`); user-level config stays untouched. Commit that file and teammates get an install prompt the next time they open the project. For a personal, non-committed setup, use `--scope local` instead (writes `.claude/settings.local.json`).

The install script does the same without needing the claude CLI, and covers Aone Copilot's project-level install too:

```bash
./install.sh --project /path/to/your-project    # path defaults to the current directory
./install.sh --project /path/to/your-project --uninstall
```

It writes the project's `.claude/settings.json` (byte-identical to the official `--scope project` output) and copies skills plus hooks into the project's `.aone_copilot/` (hook paths resolve via `$CLAUDE_PROJECT_DIR`, so the committed directory works on every teammate's machine). Codex plugin configuration is global-only with no project scope; Codex's project-level coverage already comes from `AGENTS.md` pointers plus `.superskills/` (run the discover skill).

| Tool | Skills | Hooks (auto-learning + injection) | Project-level install |
|------|--------|------|------|
| Claude Code | plugin: `superskills:discover` etc. | yes | `--scope project/local` or `install.sh --project` |
| Codex | plugin: `superskills:discover` etc. | no (Codex plugins have no hook mechanism) — use the learn skill manually | no plugin project scope; covered by `AGENTS.md` + `.superskills/` |
| Aone Copilot | `~/.aone_copilot/skills/ss-*` | yes | `install.sh --project` (lands in `.aone_copilot/`) |

`./install.sh --tools claude` remains available as a legacy settings-based install for environments without marketplace access. `--uninstall` reverses everything and preserves your own settings.

Then, in each project, run the discover skill once and commit the generated files. All persisted knowledge (`.superskills/` conventions and learnings) always lives at the project repository root — it is project-level memory, independent of how superskills was installed.

## How knowledge flows back in

Two channels, chosen so the core works even without hooks:

- **Conventions** load through file references: `CLAUDE.md` imports them for Claude Code and Aone Copilot; `AGENTS.md` instructs Codex to read them. Zero hook dependency, works in every tool.
- **Learnings** load as an index via the SessionStart hook (Claude Code / Aone Copilot); Codex has no hook mechanism, so its `AGENTS.md` pointer guides the model to the index instead. The model reads a one-line-per-entry index and opens a full entry only when relevant — past knowledge costs a few hundred tokens, not thousands.

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

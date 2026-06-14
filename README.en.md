# superskills

**Less is more.** 

A minimal coding harness toolkit

<p align="center"><img src="assets/hero.svg" alt="superskills — Less is more: the heavyweight harness deleted, four compounding skills and the project-level memory loop kept" width="880"></p>

[中文文档](README.md)

## Design philosophy

Heavyweight harnesses made sense when models needed guardrails at every step: hard process gates, multi-stage reviews, forced TDD loops. As models get stronger, most of that scaffolding turns into overhead. What still compounds in value:

1. **Memory** — learnings from past sessions (corrections, pitfalls, decisions) that no model can infer from code
2. **Conventions** — a minimal, evidenced spec of how this project actually works
3. **Clarification** — resolving the genuinely undecided parts of a request before coding
4. **A final test pass** — verified behavior, without ritualizing the path there

superskills keeps exactly these four things and deletes everything else.

## Benchmarks

A/B on the same tasks, same model (Sonnet 4.6), real end-to-end runs, deterministic graders. Full methodology, contamination post-mortem, and per-check tables in [docs/benchmark.en.md](docs/benchmark.en.md).

| Scenario | Baseline (pure model) | With superskills | Δ |
|----------|----------------------|------------------|---|
| Auto-learning · recall (persists code-invisible decisions) | 0% | 100% | **+100pp** |
| Auto-learning · precision (keeps the rule, drops throwaways under noise) | 0% | 100% | **+100pp** |
| Cross-session memory (reuses persisted team decisions) | 20% | 100% | **+80pp** |
| Requirement clarification (asked-before-guessing rate) | 0% | 67% | **+67pp** |
| Clarification · self-triggered (Discover's AGENTS.md directive; asks when a task cites an unknowable convention) | 33% | 100% | **+67pp** |
| Final test pass (2 planted bugs in "just developed" code) | 40% | 100% | **+60pp** |
| Convention adherence (rules scattered in docs) | 100% | 100% | even |
| HumanEval hard subset (canonical `check`) | 40% | 50% | **+10pp** |
| HumanEval+ hard subset (EvalPlus, full-range, 8 trials) | 20.5% | 30.7% | **+10pp** |
| MBPP+ hard subset (EvalPlus, 6 trials) | 21.7% | 25.0% | **+3pp** |
| Control: HumanEval/0–9 verbatim | 10/10 | 10/10 | **no regression** |

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

Or run `./install.sh` inside the clone — same flow when the codex CLI supports plugins, falling back to custom prompts on older CLIs. `install.sh` also writes the auto-learning Stop hook into `~/.codex/hooks.json` (the learner runs `codex exec`); a bare `codex plugin add` installs only the skills, no hook. Keep the clone in place; Codex resolves the plugin and hook scripts from it.

### Aone Copilot

```bash
git clone https://github.com/Mrlyk/superskills.git && cd superskills
./install.sh              # autodetects ~/.aone_copilot (and ~/.codex)
```

### Project-level install

To enable superskills in a single project without touching your global setup: in Claude Code run `/plugin marketplace add Mrlyk/superskills --scope project` and `/plugin install superskills@superskills --scope project`, which writes only the project's `.claude/settings.json` (commit it and teammates get an install prompt). Without the claude CLI, use `./install.sh --project /path/to/project` — output matches the official `--scope project`, and also covers Aone Copilot's `.aone_copilot/`.

| Tool | Skills | Hooks (auto-learning + injection) | Project-level install |
|------|--------|------|------|
| Claude Code | plugin: `superskills:discover` etc. | yes | `--scope project/local` or `install.sh --project` |
| Codex | plugin: `superskills:discover` etc. | yes via `install.sh` (writes `~/.codex/hooks.json`; the learner runs `codex exec`); learnings inject through the `AGENTS.md` index pointer | no plugin project scope; covered by `AGENTS.md` + `.superskills/` |
| Aone Copilot | `~/.aone_copilot/skills/ss-*` | yes | `install.sh --project` (lands in `.aone_copilot/`) |

`./install.sh --tools claude` remains a legacy settings-based install for environments without marketplace access. `--uninstall` reverses everything and preserves your own settings. Then, in each project, run the discover skill once and commit the generated files.

## What you get

| Component | Kind | What it does |
|-----------|------|--------------|
| `superskills:discover` | skill | Scans an existing project and generates minimal spec files: `.superskills/conventions.md` (≤80 lines), `AGENTS.md`, `CLAUDE.md`. Refreshes them when stale, folding hardened learnings into conventions. |
| `superskills:learn` | skill | Persists durable learnings (user corrections, pitfalls + fixes, invisible decisions) to `.superskills/learnings/`. |
| `superskills:clarify` | skill | Surfaces only the questions whose answers change the implementation, with recommended answers, then starts coding. |
| `superskills:test` | skill | One full unit-test pass after development is done. Result-driven, no fixed process. |
| SessionStart hook | hook | Injects the learnings index into each session; reminds you when conventions drift >30 commits behind HEAD; suggests `discover` for projects with no AI specs. |
| Stop hook (verify) | hook | Verify-before-done: if the session edited code but never executed it afterwards, blocks the stop once and demands a real run — documented examples plus boundary cases — with root-cause fixes. |
| Stop hook (learn) | hook | Auto-learning: when a session did real work (≥5 user messages and file edits), spawns a background learner that reads a session replay and persists durable learnings off the main thread — re-firing as the session grows so work after the first summary is captured too. The learner picks its CLI per platform — `claude -p` on Claude Code (default Sonnet for cost), `codex exec` on Codex — falling back to one inline judgment when no background learner can be launched. |

Everything shows up in the `/plugin` panel with per-component token costs. Total always-on cost: ~418 tokens.

### Project artifacts (committed to your repo)

```
.superskills/
├── conventions.md        # single source of truth, ≤80 lines
└── learnings/            # topic wiki: one page per topic, merged + deduplicated
    ├── INDEX.md          # catalog, one line per topic, auto-injected at session start
    ├── timestamps.md     # topic page (frontmatter + rules + [[cross-links]])
    └── money.md
AGENTS.md                 # ≤20 lines, points at .superskills/
CLAUDE.md                 # @AGENTS.md + @.superskills/conventions.md
```

All persisted knowledge always lives at the project repository root — project-level memory, independent of how superskills was installed.

## How knowledge flows back in

Two channels, chosen so the core works even without hooks:

- **Conventions** load through file references: `CLAUDE.md` imports them for Claude Code and Aone Copilot; `AGENTS.md` instructs Codex to read them. Zero hook dependency, works in every tool.
- **Learnings** load as an index via the SessionStart hook (Claude Code / Aone Copilot); on Codex, superskills wires only the Stop learner, so its `AGENTS.md` pointer guides the model to the index instead. The model reads a one-line-per-topic index and opens a full topic page only when relevant — past knowledge costs a few hundred tokens, not thousands.

Learnings are organized as a topic wiki — one page per topic, new learnings merged in and deduplicated rather than piled up by date (see [docs/learnings-wiki.en.md](docs/learnings-wiki.en.md)). Those that harden into stable rules get folded into `conventions.md` by `discover`'s refresh mode, keeping the knowledge base from growing forever.

## Testing

```bash
tests/run.sh              # hook + installer + plugin-structure tests (no model calls)
tests/run.sh --bench      # plus a smoke benchmark driving real `claude -p` runs
tests/bench/run.sh        # the full A/B capability benchmark (~44 model runs)
```

## License

MIT. The benchmark control group vendors HumanEval problems (MIT, OpenAI) — see [tests/bench/humaneval/ATTRIBUTION.md](tests/bench/humaneval/ATTRIBUTION.md).

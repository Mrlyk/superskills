# superskills

**Less is more.** 

极简 Coding Harness 工具包

<p align="center"><img src="assets/hero.svg" alt="superskills — Less is more：删掉重型流程，保留 4 个产生复利的 skill 与项目级记忆闭环" width="880"></p>

[English](README.en.md)

## 设计哲学

重型 harness 在模型需要步步设防的年代是合理的：硬性流程门控、多阶段审查、强制 TDD 循环。随着模型能力增强，这些脚手架大多变成了负担。真正能持续产生复利的只有四件事：

1. **记忆** — 历史会话中的经验（纠正、踩坑、决策），任何模型都无法从代码中推断出来
2. **规范** — 一份精简、有据可查的项目实际约定
3. **澄清** — 写代码之前解决需求中真正悬而未决的部分
4. **收尾测试** — 验证行为正确，且不把过程仪式化

superskills 只保留这四件事，删掉其余一切。

## 基准数据

同任务、同模型（Sonnet 4.6）、真实端到端运行、确定性程序评分的 A/B 对照。完整方法学、污染排查与分项数据见 [docs/benchmark.md](docs/benchmark.md)。

| 场景 | 基线（纯模型） | 带 superskills | Δ |
|------|--------------|----------------|---|
| 自动总结·召回（沉淀代码里看不出的决策） | 0% | 100% | **+100pp** |
| 自动总结·精度（噪声中留团队规范、弃一次性指令） | 0% | 100% | **+100pp** |
| 跨会话记忆（复用已沉淀的团队决策） | 20% | 100% | **+80pp** |
| 需求澄清（模糊请求的"先问后写"率） | 0% | 67% | **+67pp** |
| 需求澄清·自触发（discover 写进 AGENTS.md 的指令，任务引用不可知约定时主动发问） | 33% | 100% | **+67pp** |
| 收尾测试（"刚开发完"的代码埋了 2 个 bug） | 40% | 100% | **+60pp** |
| 规范遵循（规则散落在文档里） | 100% | 100% | 持平 |
| HumanEval 困难子集（官方 check） | 40% | 50% | **+10pp** |
| HumanEval+ 困难子集（EvalPlus 全量，8 次） | 20.5% | 30.7% | **+10pp** |
| MBPP+ 困难子集（EvalPlus，6 次） | 21.7% | 25.0% | **+3pp** |
| 控制组：HumanEval/0–9 原题 | 10/10 | 10/10 | **无回归** |

## 安装

### Claude Code（plugin，推荐）

```
/plugin marketplace add Mrlyk/superskills
/plugin install superskills@superskills
```

也可以用 CLI：`claude plugin marketplace add Mrlyk/superskills && claude plugin install superskills@superskills`。hooks 随插件自动注册，不改动你的 `settings.json`。

或从聚合市场一站式安装：`/plugin marketplace add Mrlyk/cc-plugins` 后 `/plugin install superskills@mrlyk-plugins`，同一市场还能装作者的其他插件（如 cc-commitely）。

### Codex（plugin）

```bash
git clone https://github.com/Mrlyk/superskills.git
codex plugin marketplace add ./superskills
codex plugin add superskills@superskills
```

或在克隆目录内运行 `./install.sh`（检测到支持 plugin 的 codex CLI 时走相同流程，老版本回退为自定义 prompts）。`install.sh` 还会把自动总结 Stop hook 写进 `~/.codex/hooks.json`（learner 走 `codex exec`），单独的 `codex plugin add` 只装 skills、不含 hook。保留克隆目录，Codex 从该目录解析插件与 hook 脚本。

### Aone Copilot

```bash
git clone https://github.com/Mrlyk/superskills.git && cd superskills
./install.sh              # 自动检测 ~/.aone_copilot（与 ~/.codex）
```

### 项目级安装

只想在某个项目启用、不动用户全局：Claude Code 在项目内执行 `/plugin marketplace add Mrlyk/superskills --scope project` 与 `/plugin install superskills@superskills --scope project`，只写入项目的 `.claude/settings.json`，提交后队友自动获得安装提示。不依赖 claude CLI 时用 `./install.sh --project /path/to/project`（产物与官方 `--scope project` 一致，并覆盖 Aone Copilot 的 `.aone_copilot/`）。

| 工具 | Skills | Hooks（自动总结 + 注入） | 项目级安装 |
|------|--------|------|------|
| Claude Code | plugin：`superskills:discover` 等 | 支持 | `--scope project/local` 或 `install.sh --project` |
| Codex | plugin：`superskills:discover` 等 | 支持：`install.sh` 写 `~/.codex/hooks.json`，自动总结 learner 走 `codex exec`；learnings 注入靠 `AGENTS.md` 索引指引 | 无 plugin 项目作用域，靠 `AGENTS.md` + `.superskills/` |
| Aone Copilot | `~/.aone_copilot/skills/ss-*` | 支持 | `install.sh --project`（产物进 `.aone_copilot/`） |

无法访问 marketplace 的环境可用 `./install.sh --tools claude` 做传统 settings 安装。`--uninstall` 完整卸载并保留你自己的配置。安装后在每个项目里运行一次 discover skill，把生成的文件提交即可。

## 首次使用

装好后绝大多数能力自动生效，不需要配置：

- **会话开始**：SessionStart hook 自动注入本项目已沉淀的 learnings 索引；项目缺少规范文件时提示你跑 discover，规范过期时提醒刷新。
- **会话结束**：Stop hook 自动验证（改了代码却没真实运行会拦一次）+ 自动总结（有实质工作时在后台沉淀 learnings）。
- **开发中**：clarify、test 等 skill 在相关请求下自动触发，也可 `/superskills:discover` 等显式调用。

唯一需要手动做一次的事：**每个新项目首次运行 `discover` skill**。它扫描项目并生成 `.superskills/conventions.md`、`AGENTS.md`、`CLAUDE.md`，把这些文件提交进仓库即可。这一步建立规范基线、并让 `CLAUDE.md` / `AGENTS.md` 的文件引用通道生效；没做时 SessionStart hook 会主动提醒。之后就交给自动机制——learnings 持续累积、规范每次会话自动加载、漂移过多时（落后 HEAD 超过 30 个提交）hook 提醒你重跑 discover 刷新。

## 包含什么

| 组件 | 类型 | 作用 |
|------|------|------|
| `superskills:discover` | skill | 扫描存量项目，生成极简规范文件：`.superskills/conventions.md`（不超过 80 行）、`AGENTS.md`、`CLAUDE.md`；过期时刷新，并把已固化的 learnings 折叠进规范 |
| `superskills:learn` | skill | 把值得长期保留的经验（用户纠正、踩坑与修复、代码中看不出的决策）沉淀到 `.superskills/learnings/` |
| `superskills:clarify` | skill | 只提出会改变实现方案的问题，每个问题附推荐答案，澄清完立即开始编码 |
| `superskills:test` | skill | 开发结束后组织一次完整的单元测试，只看结果，不固定流程 |
| SessionStart hook | hook | 每次会话注入 learnings 索引；规范落后 HEAD 超过 30 个提交时提醒刷新；项目缺少 AI 规范文件时建议运行 discover |
| Stop hook（verify） | hook | 完成前验证：若会话改了代码却从未执行过，阻止收尾一次并要求真实运行——文档示例加边界用例——按根因修复 |
| Stop hook（learn） | hook | 自动总结：当会话做了实际工作（用户消息不少于 5 条且有文件修改）时，在后台拉起一个独立的总结进程读取会话回放并沉淀，不阻塞主线程；随会话推进每积累若干条新消息再触发一次，覆盖首次总结之后的工作。learner 按平台选 CLI——Claude Code 用 `claude -p`（默认 Sonnet 省成本），Codex 用 `codex exec`；无法启动后台时回退为收尾前内联判断一次 |

所有组件都会出现在 `/plugin` 面板中，并标注各自的 token 成本。常驻总成本约 418 token。

### 项目内产物（提交到仓库）

```
.superskills/
├── conventions.md        # 唯一事实源，不超过 80 行
└── learnings/            # 主题 wiki：一个主题一页，合并去重
    ├── INDEX.md          # 主题目录，每主题一行，会话开始时自动注入
    ├── timestamps.md     # 主题页（frontmatter + 规则 + [[交叉链接]]）
    └── money.md
AGENTS.md                 # 不超过 20 行，指向 .superskills/
CLAUDE.md                 # @AGENTS.md + @.superskills/conventions.md
```

所有沉淀始终写在项目仓库根目录，属于项目级记忆，与安装方式无关。

## 沉淀的知识如何被利用

两条通道，保证核心机制在没有 hook 的工具里也能工作：

- **规范**走文件引用：Claude Code 和 Aone Copilot 通过 `CLAUDE.md` 的 import 加载；Codex 通过 `AGENTS.md` 中的指引读取。零 hook 依赖，所有工具通用。
- **Learnings**走 SessionStart hook 注入索引（Claude Code / Aone Copilot）；Codex 上 superskills 只接 Stop learner，由 `AGENTS.md` 指引模型查阅索引。模型看到的只有每主题一行的索引，相关时才打开完整主题页——历史知识的成本是几百个 token，而非几千。

Learnings 以主题 wiki 组织——一个主题一页、新学习合并进对应主题页并去重，而非按日期堆文件（详见 [docs/learnings-wiki.md](docs/learnings-wiki.md)）。已固化为稳定规则的 learnings，会在 discover 的刷新模式中折叠进 `conventions.md`，知识库不会无限膨胀。

## 测试

```bash
tests/run.sh              # hook + 安装脚本 + plugin 结构测试（不调用模型）
tests/run.sh --bench      # 追加冒烟基准（真实 claude -p 运行）
tests/bench/run.sh        # 完整 A/B 能力基准（约 44 次模型运行）
```

## License

MIT。基准控制组内置了 HumanEval 题目（MIT，OpenAI），见 [tests/bench/humaneval/ATTRIBUTION.md](tests/bench/humaneval/ATTRIBUTION.md)。

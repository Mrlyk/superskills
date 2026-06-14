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
| 自动总结·召回 | 0% | 100% | **+100pp** |
| 自动总结·精度 | 0% | 100% | **+100pp** |
| 跨会话记忆 | 20% | 100% | **+80pp** |
| 需求澄清 | 0% | 67% | **+67pp** |
| 需求澄清·自触发 | 67% | 100% | **+33pp** |
| 收尾测试 | 40% | 100% | **+60pp** |
| 规范遵循 | 100% | 100% | 持平 |
| HumanEval 困难子集 | 40% | 50% | **+10pp** |
| HumanEval+ 困难子集 | 20.5% | 30.7% | **+10pp** |
| MBPP+ 困难子集 | 21.7% | 25.0% | **+3pp** |
| 控制组：HumanEval/0–9 | 10/10 | 10/10 | **无回归** |

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

唯一需要手动做一次的事：**每个新项目首次运行 `discover` skill**，它生成 `.superskills/conventions.md`、`AGENTS.md`、`CLAUDE.md`，提交进仓库即可。之后全交给自动机制；没做时 SessionStart hook 会主动提醒。

## 包含什么

| 组件 | 类型 | 作用 |
|------|------|------|
| `superskills:discover` | skill | 扫描项目生成规范文件（`conventions.md` ≤80 行、`AGENTS.md`、`CLAUDE.md`），过期时刷新 |
| `superskills:learn` | skill | 把用户纠正、踩坑、代码里看不出的决策沉淀到 `.superskills/learnings/` |
| `superskills:clarify` | skill | 只问会改变实现方案的问题，澄清完立即编码 |
| `superskills:test` | skill | 开发结束后跑一次完整单元测试，只看结果 |
| SessionStart hook | hook | 注入 learnings 索引；规范过期或缺失时提醒跑 discover |
| Stop hook（verify） | hook | 改了代码却没运行过，收尾前拦一次，要求真跑（文档示例+边界用例）并按根因修复 |
| Stop hook（learn） | hook | 有实质工作时在后台沉淀 learnings，不阻塞主线程，随会话推进多次触发；按平台选 learner（Claude Code 用 `claude -p` 默认 Sonnet，Codex 用 `codex exec`） |

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

Learnings 按主题 wiki 组织（一主题一页、合并去重，详见 [docs/learnings-wiki.md](docs/learnings-wiki.md)）；固化的规则会在 discover 刷新时折叠进 `conventions.md`，知识库不会无限膨胀。

## 测试

```bash
tests/run.sh              # hook + 安装脚本 + plugin 结构测试（不调用模型）
tests/run.sh --bench      # 追加冒烟基准（真实 claude -p 运行）
tests/bench/run.sh        # 完整 A/B 能力基准（约 44 次模型运行）
```

## License

MIT。基准控制组内置了 HumanEval 题目（MIT，OpenAI），见 [tests/bench/humaneval/ATTRIBUTION.md](tests/bench/humaneval/ATTRIBUTION.md)。

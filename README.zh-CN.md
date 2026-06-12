# superskills

**Less is more.** 面向 Claude Code、Codex、Aone Copilot 的极简 Coding Harness：4 个 skill、2 个 hook、1 个安装脚本，没有其他东西。

[English](README.md)

## 为什么

重型 harness 在模型需要步步设防的年代是合理的：硬性流程门控、多阶段审查、强制 TDD 循环。随着模型能力增强，这些脚手架大多变成了负担。真正能持续产生复利的只有四件事：

1. **记忆** — 历史会话中的经验（纠正、踩坑、决策），任何模型都无法从代码中推断出来
2. **规范** — 一份精简、有据可查的项目实际约定
3. **澄清** — 写代码之前解决需求中真正悬而未决的部分
4. **收尾测试** — 验证行为正确，且不把过程仪式化

superskills 只保留这四件事，删掉其余一切。

## 包含什么

| 组件 | 类型 | 作用 |
|------|------|------|
| `ss-discover` | skill | 扫描存量项目，生成极简规范文件：`.superskills/conventions.md`（不超过 80 行）、`AGENTS.md`、`CLAUDE.md`；规范过期时负责刷新 |
| `ss-learn` | skill | 把值得长期保留的经验（用户纠正、踩坑与修复、代码中看不出的决策）沉淀到 `.superskills/learnings/` |
| `ss-clarify` | skill | 只提出会改变实现方案的问题，每个问题附推荐答案，澄清完立即开始编码 |
| `ss-test` | skill | 开发结束后组织一次完整的单元测试，只看结果，不固定流程 |
| `session-start.js` | hook | 每次会话注入 learnings 索引；规范落后 HEAD 超过 30 个提交时提醒刷新；项目缺少 AI 规范文件时建议运行 `ss-discover` |
| `stop-learn.js` | hook | 自动总结：当会话做了实际工作（用户消息不少于 5 条且有文件修改）时，在结束前让模型带着完整上下文判断一次是否有值得沉淀的内容 |

### 项目内产物（提交到仓库）

```
.superskills/
├── conventions.md        # 唯一事实源，不超过 80 行
└── learnings/
    ├── INDEX.md          # 每条经验一行，会话开始时自动注入
    └── 2026-06-12-use-pnpm.md
AGENTS.md                 # 不超过 20 行，指向 .superskills/
CLAUDE.md                 # @AGENTS.md + @.superskills/conventions.md
```

## 沉淀的知识如何被利用

两条通道，保证核心机制在没有 hook 的工具里也能工作：

- **规范**走文件引用：Claude Code 和 Aone Copilot 通过 `CLAUDE.md` 的 import 加载；Codex 通过 `AGENTS.md` 中的指引读取。零 hook 依赖，所有工具通用。
- **Learnings**走 SessionStart hook 注入索引（Claude Code / Aone Copilot）。模型看到的只有每条一行的索引，相关时才打开完整条目——历史知识的成本是几百个 token，而非几千。

已经固化为稳定规则的 learnings，会在 `ss-discover` 的刷新模式中被折叠进 `conventions.md`，知识库不会无限膨胀。

## 自动总结的设计

与基于观察的方案（ECC 式的 PreToolUse/PostToolUse 全量捕获加后台分析进程）相比，superskills 把判断挪到了唯一既便宜又可靠的时机：会话结束。Stop hook 是一个约 100 行的过滤器，只判断这个会话*值不值得*总结（消息够多、确实改了文件、每个会话只触发一次、绝不循环）；而*总结什么*交给模型——它本来就持有完整会话上下文，并且被明确允许"无可沉淀就什么都不写"。没有观察文件、没有后台进程、没有逐工具调用的开销。产出直接落在项目仓库里，整个团队共享。

## 安装

```bash
git clone https://github.com/Mrlyk/superskills.git
cd superskills
./install.sh              # 自动检测 ~/.claude、~/.codex、~/.aone_copilot
```

可选参数：

```bash
./install.sh --tools claude,codex,aone   # 显式指定工具
./install.sh --all                       # 安装到全部三个工具
./install.sh --uninstall                 # 干净卸载（保留用户自己的配置）
```

| 工具 | Skills | Hooks（自动总结 + 注入） |
|------|--------|------|
| Claude Code | `~/.claude/skills/ss-*` | 支持 |
| Aone Copilot | `~/.aone_copilot/skills/ss-*` | 支持 |
| Codex | `~/.codex/prompts/ss-*.md`（自定义 prompts） | 不支持，依赖 `AGENTS.md` 指引 |

安装后，在每个项目里执行一次：

```
> 使用 ss-discover skill
```

检查生成的文件并提交，即可。

## 测试

```bash
tests/run.sh           # hook 单元测试 + 安装脚本测试（不调用模型）
tests/run.sh --bench   # 追加真实端到端基准测试（驱动 claude -p）
```

基准测试会搭建一个一次性的 fixture 项目，通过 Claude CLI 以受限权限真实运行 `ss-discover` 和 `ss-learn`，并断言产物：从真实 manifest 中发现的规范、被沉淀并建立索引的经验，以及由真实 hook 注入到新会话的索引。

## License

MIT

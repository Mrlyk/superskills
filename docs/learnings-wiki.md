# 学习沉淀：主题 wiki 组织

[English](learnings-wiki.en.md)

## 背景

superskills 的自学习沉淀最初按「一条学习一个日期文件」组织（`<date>-<slug>.md` + `INDEX.md`）。知识累积后，同一主题的规则会散落在多个日期文件里，容易重复、检索变噪。替代方案是按 wiki 方式组织：每个主题一个页面，新学习合并进对应主题页、去重、交叉链接，`INDEX.md` 作目录。

## 方案

`.superskills/learnings/` 改为主题页组织：

- `<topic>.md`：一个主题一页（frontmatter `topic/tags` + 精炼规则 + `[[topic]]` 交叉链接）。新学习合并进已有主题页，无合适主题才新建，且不重复已在别页存在的规则。
- `INDEX.md`：目录，每主题一行，是唯一注入后续会话的文件。
- 不引入 `log.md`：时序由 git 历史提供——对 superskills 的小知识库，单独的时序日志是多余开销。

保留 `INDEX.md` 这一既有约定，所以 SessionStart 注入与 discover 刷新不受影响，存量的日期文件也能继续被读取，新学习逐步以主题页累积。

## 基准：flat vs wiki

同模型（Sonnet 4.6）、确定性程序评分，flat（日期文件）对 wiki（主题页）A/B，每格 3 次。逐轮迭代：

| 轮 | 场景 | flat | wiki |
|----|------|------|------|
| 1 | 累积：向 3 主题知识库加一条扩展 timestamps 的学习 | 60% | **100%** |
| 2 | 空库简单：2 条无关纠正，从零自举 | 100% | 100% |
| 3 | 噪声精度：1 条团队规范 + 2 条一次性指令 | 100% | 94% |
| 4 | 噪声精度（优化后） | 94% | 94% |
| 4 | 累积（优化后） | 60% | **100%** |

累积是 wiki 的主场：flat 把同主题知识散到新日期文件（consolidated 0/3、noDuplication 0/3、知识库 4 文件），wiki 合并进主题页（consolidated 3/3、noDuplication 3/3、3 文件），且不丢旧知识（preserved 3/3）、不漏新规则（capturedNew 3/3）。空库简单两臂均 100%，wiki 还更紧凑（1 内容页 vs 2 日期文件）。噪声精度两臂都不泄漏一次性指令，差异在噪声内。

## 优化迭代

第 3 轮噪声场景里，wiki 因步骤多（主题页 + index + log）出现 1/3 漏更新 `index`。第 4 轮对 wiki 自身做减法——去掉 `log.md`、把 `INDEX.md` 更新设为强制且显著（「唯一注入后续会话的文件，缺它即不可见」）——index 更新恢复 3/3，精度与 flat 持平，累积仍 100%。最优解是更精简的 wiki：Less is more 同样适用于 wiki 自身。

## 结论

主题 wiki 组织在知识累积场景显著优于日期文件（+40pp），其余场景不劣。superskills 已采用：`stop-learn` 与 learn skill 改为「合并进主题页 + 维护 `INDEX.md` 目录」，不引入 `log.md`。复现：

```bash
tests/bench/learn-wiki.sh            # 累积：flat vs wiki
tests/bench/learn-wiki.sh --simple   # 空库自举 + 召回
tests/bench/learn-wiki.sh --hard     # 噪声下的精度
```

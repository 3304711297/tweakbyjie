# 跨仓库 Coverage 审计

## 目的

`tweakbyjie` 负责执行，`youshouldknow` 负责解释。两者之间最大的长期风险不是单次脚本错误，而是新增、删除或改名后出现文档漏同步。

当前审计机制把这层关系变成 CI 可检查的契约：

```text
tweakbyjie 实际工程
        ↓
Coverage ID
        ↓
youshouldknow machine-readable manifest
        ↓
优化项目映射 / 全量执行参考 / 覆盖检查
```

## 当前组成

- `youshouldknow/项目导航/tweakbyjie-coverage-manifest.json`
  - 覆盖项目的机器可读清单。
  - 新增或删除项目时必须同步更新。
- `tools/Test-CrossRepoCoverage.ps1`
  - 从锁定的 `youshouldknow` commit 拉取 manifest、逐项映射和全量执行参考。
  - 按 manifest 指定的源仓库路径从当前 `tweakbyjie` checkout 读取覆盖检查文件；该文件不属于 `youshouldknow`。
  - 检查三份资料中的每一份都不得出现 manifest 之外的 ID，并要求每一份资料都与 manifest 完全一致。
  - 检查旧式 `tweakbyjie.ps1:行号` 定位是否复发。
  - 检查映射引用的 `Modules/*.ps1` 文件和函数是否仍存在。
  - 检查关键模块是否仍然存在。
- `tools/knowledge.lock.json`
  - 固定 Coverage 审计所读取的 `youshouldknow` commit，保证同一个 `tweakbyjie` commit 的审计结果可复现。
- `.github/workflows/ci.yml`
  - `coverage-audit` job 在 `push`、PR、版本 tag 和手动触发的 CI 流程中执行审计。
  - 正式审计前先验证 lock 是否仍指向 `youshouldknow/main` 的最新 commit；锁定落后时直接失败，防止旧知识库快照被静默继续使用。

## 维护规则

以后修改 `tweakbyjie` 的执行项目时，至少需要同步考虑：

1. `youshouldknow/项目导航/tweakbyjie-coverage-manifest.json`
2. `youshouldknow/项目导航/tweakbyjie-optimization-mapping.md`
3. `youshouldknow/项目导航/tweakbyjie全量执行参考.md`
4. `tweakbyjie/docs/coverage/YOUSEHOULDKNOW-COVERAGE-CHECK.md`

其中第 1–3 项属于 `youshouldknow`，第 4 项属于 `tweakbyjie`。

现在的审计契约是：**第 1–3 项中的每一份资料都必须单独与 manifest 完全一致**，既不能缺少 manifest 中的 ID，也不能出现 manifest 之外的 ID。CI 会在任一资料发生 `missing` 或 `extra` 时直接失败，而不是依赖三份资料的 ID 并集来兜底。

`youshouldknow` 的 Coverage 资料发生变化后，还必须提升 `tweakbyjie/tools/knowledge.lock.json` 到新的完整 commit SHA。CI 会比较 lock 与 `youshouldknow/main` 当前 HEAD：两者不一致时，Coverage job 会直接失败并报告 `locked` 与 `latest` SHA。这样可以把“知识库已经更新，但执行项目仍在审计旧版本”变成显式失败，而不是隐性漂移。

## 边界

该检查器当前主要保证“覆盖关系和源码引用没有漂移”，不是自动证明每条注册表或系统命令具有正确的性能收益。性能收益仍应通过可重复的 A/B 测试验证。

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
  - 从 `youshouldknow` 拉取 manifest、逐项映射、全量执行参考和覆盖检查。
  - 检查 ID 集合是否一致。
  - 检查旧式 `tweakbyjie.ps1:行号` 定位是否复发。
  - 检查映射引用的 `Modules/*.ps1` 文件和函数是否仍存在。
  - 检查关键模块是否仍然存在。
- `.github/workflows/coverage.yml`
  - 在 `push`、PR 和手动触发时执行审计。

## 维护规则

以后修改 `tweakbyjie` 的执行项目时，至少需要同步考虑：

1. `youshouldknow/项目导航/tweakbyjie-coverage-manifest.json`
2. `youshouldknow/项目导航/tweakbyjie-optimization-mapping.md`
3. `youshouldknow/项目导航/tweakbyjie全量执行参考.md`
4. `tweakbyjie/docs/coverage/YOUSEHOULDKNOW-COVERAGE-CHECK.md`

CI 会在集合不一致时直接失败，而不是默默接受文档漂移。

## 边界

该检查器当前主要保证“覆盖关系和源码引用没有漂移”，不是自动证明每条注册表或系统命令具有正确的性能收益。性能收益仍应通过可重复的 A/B 测试验证。

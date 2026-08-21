# Coverage Audit

运行 `Test-CrossRepoCoverage.ps1` 可检查 `tweakbyjie` 与 `youshouldknow` 的 Coverage ID、映射文档和模块源码引用是否漂移。

脚本从 `youshouldknow/main` 读取 manifest、映射文档和全量执行参考，并按 manifest 的源仓库路径从当前 `tweakbyjie` checkout 读取 `docs/coverage/YOUSEHOULDKNOW-COVERAGE-CHECK.md`。三份资料（映射、执行参考、覆盖检查）每一份都必须与 manifest 的 ID 集合完全一致：缺少清单内 ID 和出现清单外 ID 都会判定失败，不允许"另一份资料补上了"的宽松口径。

CI 会在 `push`、Pull Request 和手动触发时执行。

## 知识库版本锁定

审计默认从 `tools/knowledge.lock.json` 记录的固定 commit 读取 manifest、映射文档和执行参考，因此同一个 tweakbyjie commit 的审计结果不随 youshouldknow/main 的推进而漂移（跨仓库可复现性）。显式传 `-KnowledgeRef` 可覆盖锁定，例如本地对最新 main 试跑：`./tools/Test-CrossRepoCoverage.ps1 -KnowledgeRef main`。

youshouldknow 内容有变更时按以下流程提升锁定：

1. `./tools/Test-CrossRepoCoverage.ps1 -KnowledgeRef main` 对最新 main 试跑，确认全绿；
2. 将 `knowledge.lock.json` 的 `ref` 更新为该 commit 的完整 SHA 并提交。

只改 tweakbyjie 自身不需要动锁定。若锁定文件缺失，脚本会回退到 `main` 并输出警告（此时结果不可复现）。

首次启用时，需要先让 `youshouldknow` 的 Coverage Manifest 进入 `main`；否则 CI 会明确报告远端 manifest 不存在，而不是误判为覆盖通过。

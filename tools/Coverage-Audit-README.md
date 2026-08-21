# Coverage Audit

运行 `Test-CrossRepoCoverage.ps1` 可检查 `tweakbyjie` 与 `youshouldknow` 的 Coverage ID、映射文档和模块源码引用是否漂移。

脚本从 `youshouldknow/main` 读取 manifest、映射文档和全量执行参考，并按 manifest 的源仓库路径从当前 `tweakbyjie` checkout 读取 `docs/coverage/YOUSEHOULDKNOW-COVERAGE-CHECK.md`。三份资料（映射、执行参考、覆盖检查）每一份都必须与 manifest 的 ID 集合完全一致：缺少清单内 ID 和出现清单外 ID 都会判定失败，不允许"另一份资料补上了"的宽松口径。

CI 会在 `push`、Pull Request 和手动触发时执行。

首次启用时，需要先让 `youshouldknow` 的 Coverage Manifest 进入 `main`；否则 CI 会明确报告远端 manifest 不存在，而不是误判为覆盖通过。

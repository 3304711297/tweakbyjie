# Coverage Audit

运行 `Test-CrossRepoCoverage.ps1` 可检查 `tweakbyjie` 与 `youshouldknow` 的 Coverage ID、映射文档和模块源码引用是否漂移。

脚本从 `youshouldknow/main` 读取 manifest、映射文档和全量执行参考，并按 manifest 的源仓库路径从当前 `tweakbyjie` checkout 读取 `docs/coverage/YOUSEHOULDKNOW-COVERAGE-CHECK.md`。映射、执行参考和覆盖检查可以分别承担不同层次的说明；每份资料不得出现清单外 ID，三份资料的 ID 并集必须覆盖 manifest 全部项目。

CI 会在 `push`、Pull Request 和手动触发时执行。

首次启用时，需要先让 `youshouldknow` 的 Coverage Manifest 进入 `main`；否则 CI 会明确报告远端 manifest 不存在，而不是误判为覆盖通过。

# Coverage Audit

运行 `Test-CrossRepoCoverage.ps1` 可检查 `tweakbyjie` 与 `youshouldknow` 的 Coverage ID、映射文档和模块源码引用是否漂移。

CI 会在 `push`、Pull Request 和手动触发时执行。

首次启用时，需要先让 `youshouldknow` 的 Coverage Manifest 进入 `main`；否则 CI 会明确报告远端 manifest 不存在，而不是误判为覆盖通过。

# Coverage Audit

运行 `Test-CrossRepoCoverage.ps1` 可检查 `tweakbyjie` 与 `youshouldknow` 的 Coverage ID、映射文档和模块源码引用是否漂移。

脚本从锁定的 `youshouldknow` commit 读取 manifest、映射文档和全量执行参考，并按 manifest 的源仓库路径从当前 `tweakbyjie` checkout 读取 `docs/coverage/YOUSEHOULDKNOW-COVERAGE-CHECK.md`。三份资料（映射、执行参考、覆盖检查）每一份都必须与 manifest 的 ID 集合完全一致：缺少清单内 ID 和出现清单外 ID 都会判定失败，不允许"另一份资料补上了"的宽松口径。

CI 会在 `push`、Pull Request、版本 tag 和手动触发时执行。Coverage job 在实际审计前还会检查 `tools/knowledge.lock.json` 是否仍指向 `youshouldknow/main` 的当前最新 commit；若知识库已经更新而 lock 没有提升，CI 会直接失败，避免旧知识库快照被静默继续使用。

## 知识库版本锁定

审计默认从 `tools/knowledge.lock.json` 记录的固定 commit 读取 manifest、映射文档和全量执行参考，因此同一个 tweakbyjie commit 的审计结果由两边 commit 共同决定、可复现。显式传 `-KnowledgeRef` 可覆盖锁定，例如本地对最新 main 试跑：`./tools/Test-CrossRepoCoverage.ps1 -KnowledgeRef main`。

youshouldknow 内容有变更时按以下流程提升锁定：

1. `./tools/Test-CrossRepoCoverage.ps1 -KnowledgeRef main` 对最新 main 试跑，确认全绿；
2. 将 `knowledge.lock.json` 的 `ref` 更新为该 commit 的完整 SHA 并提交；
3. 等待 `tweakbyjie` 的 Coverage CI 重新执行并确认锁定检查与 Coverage 审计均通过。

CI 现在会主动检查锁定是否落后于 `youshouldknow/main`。因此，只更新 `youshouldknow` 而不更新 lock 时，`tweakbyjie` 的 Coverage job 会明确失败并给出 `locked` 与 `latest` SHA，避免知识库版本漂移被悄悄放过。

只改 tweakbyjie 自身、不涉及 Coverage Manifest/映射/执行参考时不需要动锁定。若锁定文件缺失，审计脚本仍会回退到 `main` 并输出警告，但正式 CI 在锁定检查阶段会直接失败，确保发布门禁不会建立在不可复现的知识库版本上。

首次启用时，需要先让 `youshouldknow` 的 Coverage Manifest 进入 `main`；否则 CI 会明确报告远端 manifest 不存在，而不是误判为覆盖通过。

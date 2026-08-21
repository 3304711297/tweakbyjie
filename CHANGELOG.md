# 更新日志

本文件记录用户视角的重要变更；开发细节见 Git 提交历史。版本号与 Git tag（`v*`）及脚本内 `$script:TweakVersion` 一一对应，Release 附件（整仓 ZIP + SHA256SUMS）可在 GitHub Releases 页下载。

## 未发布

### 修复

- 服务恢复不再把无法识别的启动类型一律当作"禁用"处理：显式支持 Auto/Manual/Disabled/System/Boot，未知类型跳过并警告
- 服务快照新增延迟启动（delayed-auto）标记，恢复时还原，不再把延迟启动服务变成开机即启
- MPO / BCD / 服务的备份文件写入后增加回读校验（与安全缓解、NVMe、Defender 模块标准一致）
- 菜单 7 导入电源计划后检测同名重复计划（历史导入遗留），经确认后可清理，避免反复应用/恢复累积冗余计划

## 0.1.0 - 2026-08-21

首个带版本号的发布。

### 新增

- 模块化架构：`tweakbyjie.ps1` 精简为 Loader，功能拆分至 `Modules/`（Common、各 Backup.* 备份闭环、Defender、Menu）
- Part 5 关闭安全中心：约 95 个策略值与 4 个自启动项在首次应用前自动快照到 `defender-policy-backup.json`，菜单 `5 → 2` 可按快照恢复注册表值
- 双运行时支持：Windows PowerShell 5.1 与 PowerShell 7+ 均可运行；`tweakbyjie.cmd` 启动器自动优先使用 pwsh
- Release 自动打包：推送 `v*` tag 时生成整仓 ZIP 与 SHA256SUMS 并创建 GitHub Release
- CI 覆盖：PSScriptAnalyzer lint、Pester 测试（含备份/恢复真实往返测试与代码覆盖率）、Windows PowerShell 5.1 冒烟、跨仓库知识库 Coverage 审计

### 修复

- 菜单 7 在标准部署下找不到根目录 `ultimate-performance.pow`（模块化引入的 `$PSScriptRoot` 语义回归，现统一使用仓库根锚点）
- Part 8 SafeBoot 回滚会误清同会话其他模块的待重启标记
- 备份 schema 中 `0xFFFFFFFF` 字面量比较错误（PowerShell 5.1/7.x 均按 `-1` 解析，导致存在值时校验恒失败）
- Defender 启动项恢复语义与策略值对齐：原始不存在、事后新增的值在恢复时删除

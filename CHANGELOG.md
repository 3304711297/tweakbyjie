# 更新日志

本文件记录用户视角的重要变更；开发细节见 Git 提交历史。版本号与 Git tag（`v*`）及脚本内 `$script:TweakVersion` 一一对应，Release 提供精简运行包 ZIP 与 SHA256 校验文件；完整开发资料仍保留在源码仓库中。

## 未发布

## 0.2.1 - 2026-08-22

### 修复

- 自动发布版本号回退：计算下一版本由“距 HEAD 最近的 tag”改为“版本序最高的 tag”，修复 v0.2.0 发布后自动版本误回 v0.1.7~v0.1.9 的问题；本版即按新逻辑自 v0.2.0 递增而来

## 0.2.0 - 2026-08-21

### 新增

- CI 全绿自动发布：main 分支推送且 lint/test/5.1 冒烟/Coverage 审计全部通过后，自动递增补丁版本号（基于最新 tag）并创建 GitHub Release，包内脚本版本号同步注入；推送 `v*` tag 可发布里程碑版本
- 非交互执行入口：`-RunModule` 参数可直接指定模块编号（支持逗号分隔，如 `-RunModule '7,11'`），执行完毕统一询问重启
- 会话日志：作为脚本运行时自动将全部输出记录到 `%LOCALAPPDATA%\tweakbyjie\logs\session-*.log`

### 变更

- 模块化收尾：Part 1（核心优化）、Part 8（NVMe）、Part 9/10（Device Guard/VBS）迁出为独立模块（Registry/Nvme/Virtualization），Menu.ps1 精简至约 509 行，11 个功能模块全部为独立函数
- 计数器统一：Menu.ps1 全部内联模块的 OK/FAIL/SKIP 计数迁移到 `$script:` 作用域，与会话级统计口径一致
- Y/N 确认交互统一为 `Test-ConfirmChoice` 公共函数（电源计划去重、重启确认、Defender 删除类、Device Guard 确认）

### 修复

- `Invoke-BcdEdit` 失败时捕获并显示 bcdedit 的具体报错文本，不再只有退出码
- 服务恢复不再把无法识别的启动类型一律当作“禁用”处理：显式支持 Auto/Manual/Disabled/System/Boot，未知类型跳过并警告
- 服务快照新增延迟启动（delayed-auto）标记，恢复时还原，不再把延迟启动服务变成开机即启
- MPO / BCD / 服务的备份文件写入后增加回读校验（与安全缓解、NVMe、Defender 模块标准一致）
- 菜单 7 导入电源计划后检测同名重复计划（历史导入遗留），经确认后可清理，避免反复应用/恢复累积冗余计划

## 0.1.7 - 2026-08-21

> 版本号说明：本版实际发布于 0.2.0 之后，但沿用了 v0.1.x 序列——当时的自动发布脚本按“距 HEAD 最近的 tag”计算下一版本，恰好选中 v0.1.6；该缺陷已于 0.2.1 修复。

### 变更

- 模块化最终收尾：Part 2/3/4（BCD 与测试模式）、Part 6（服务）、Part 7（电源）、Part 11（MPO）迁出为独立模块（Bcd/Service/Power/Mpo），Menu.ps1 精简至约 105 行纯调度链

## 0.1.0 - 2026-08-21

首个带版本号的发布。

### 新增

- 模块化架构：`tweakbyjie.ps1` 精简为 Loader，功能拆分至 `Modules/`（Common、各 Backup.* 备份闭环、Defender、Menu）
- Part 5 关闭安全中心：约 95 个策略值与 4 个自启动项在首次应用前自动快照到 `defender-policy-backup.json`，菜单 `5 → 2` 可按快照恢复注册表值
- 双运行时支持：Windows PowerShell 5.1 与 PowerShell 7+ 均可运行；`tweakbyjie.cmd` 启动器自动优先使用 pwsh
- Release 自动打包：推送 `v*` tag 时生成精简运行包 ZIP 与 SHA256SUMS 并创建 GitHub Release
- CI 覆盖：PSScriptAnalyzer lint、Pester 测试（含备份/恢复真实往返测试与代码覆盖率）、Windows PowerShell 5.1 冒烟、跨仓库知识库 Coverage 审计

### 修复

- 菜单 7 在标准部署下找不到根目录 `ultimate-performance.pow`（模块化引入的 `$PSScriptRoot` 语义回归，现统一使用仓库根锚点）
- Part 8 SafeBoot 回滚会误清同会话其他模块的待重启标记
- 备份 schema 中 `0xFFFFFFFF` 字面量比较错误（PowerShell 5.1/7.x 均按 `-1` 解析，导致存在值时校验恒失败）
- Defender 启动项恢复语义与策略值对齐：原始不存在、事后新增的值在恢复时删除

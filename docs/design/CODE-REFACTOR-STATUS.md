# 代码整理状态

## 当前状态（2026-08-25，模块化已全部完成）

`tweakbyjie.ps1` 由单文件（2102 行）精简为 Loader（约 127 行），点源 `Modules/` 全部 16 个文件；11 个 Part 已全部迁出为独立模块，`Menu.ps1` 仅剩约 105 行纯调度链（`Show-TweakMenu`）。历史基线：第一阶段（2026-08-20）为 81 行 Loader + 7 个模块文件、Menu 1358 行；第二阶段（2026-08-21，`94aff84`/`202e77a`）完成剩余 Part 拆分。

| 模块 | 职责 | 说明 |
|---|---|---|
| `Common.ps1` | 通用注册表/BCD/验证/重启 | `Convert-RegExePath`/`Set-Reg*`/`Invoke-BcdEdit`/`Verify-*`/`Request-Restart` |
| `Backup.Mpo.ps1` | MPO 备份闭环 | `Get-MpoValueSnapshot` + `Test/Ensure/Restore-MpoBackup` |
| `Backup.Bcd.ps1` | BCD 备份闭环 | `Test-BcdValueAllowed`/`Test/Ensure/Restore-BcdBackup`（值按字段枚举白名单校验） |
| `Backup.Service.ps1` | 服务备份闭环 | `Test-ServiceBackupSchema` + `Ensure/Restore-ServiceBackup`（37 项固定服务清单） |
| `Backup.SecurityMitigation.ps1` | CPU 缓解备份 | `Get-SecurityMitigationSnapshot` + 三元组 |
| `Backup.Nvme.ps1` | NVMe 备份与检测 | `Test-NvmeBackupSchema`（SafeBoot 路径绑定受管理 GUID）/`Get-Nvme*Snapshot`/`Test-NativeNvme*`/`Ensure/Restore-Nvme` |
| `Backup.Defender.ps1` | Defender 策略备份 | 约 95 个策略值 + 4 个自启动项统一定义 |
| `Bcd.ps1` | Part 2/3/4 | 高级 BCD、开启/关闭测试模式 |
| `Defender.ps1` | Part 5 | 安全中心策略与可选删除类分支 |
| `Mpo.ps1` | Part 11 | MPO 三方案互斥管理 |
| `Nvme.ps1` | Part 8 | 原生 NVMe 驱动编排 |
| `Power.ps1` | Part 7 | 超性能电源计划 |
| `Registry.ps1` | Part 1 | 核心游戏/系统行为/CPU 缓解 |
| `Service.ps1` | Part 6 | 服务优化编排 |
| `Virtualization.ps1` | Part 9/10 | Device Guard EFI 与 VBS/Hyper-V |
| `Menu.ps1` | 菜单调度 | `Show-TweakMenu`（纯调度，支持 `-RunModules` 队列） |

Loader 点源清单由 `tools/Test-CrossRepoCoverage.ps1` 的 Loader 契约自动校验：`Modules/` 下每个 `.ps1` 都必须被主入口点源；菜单契约校验 11 个 `Invoke-*Module` 调度函数仍在 `Menu.ps1` 中。

`defender-removal.ps1` 保持独立入口，默认仅 DryRun，显式 `-Execute` 并二次确认后才执行不可逆删除；失败禁止重启（契约由 `tests/DefenderSafety.Tests.ps1` 锁定）。

## 已确认基础组件

- 管理员权限检测（`TWEAK_SKIP_ADMIN_CHECK=1` 仅供本地开发/CI）
- 注册表 DWORD/字符串/二进制写入
- 注册表值删除恢复流程
- 执行成功/失败/跳过统计 + 稳定退出码（`Get-TweakExitCode`：0/2/4/5）
- BCD `bcdedit` 封装与 `deletevalue` 保护
- 备份 Schema 校验（MPO/BCD/Service/Security/NVMe/Defender 共 6 套，旁车输入按白名单/固定路径校验）

## 下一阶段

- 高危路径（BCD 写入、EFI、服务、VBS）的命令/注册表/服务依赖注入适配器化，便于无副作用测试
- 统一日志接口（`DETECTION`/`LOGGING` 设计已就绪，暂不替换输出）

## 原则

- 稳定优先，不改变已验证优化目标
- 不影响 `powershell -ExecutionPolicy Bypass -File .\tweakbyjie.ps1` 入口
- 所有结构调整可回退（`git checkout` 单文件恢复）

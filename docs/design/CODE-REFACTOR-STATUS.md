# 代码整理状态

## 当前状态（2026-08-20）

已完成第一阶段模块化，`tweakbyjie.ps1` 由单文件（2102 行）精简为 Loader（81 行），功能拆至 `Modules/`：

| 模块 | 职责 | 说明 |
|---|---|---|
| `Common.ps1` | 通用注册表/BCD/验证/重启 | `Convert-RegExePath`/`Set-Reg*`/`Invoke-BcdEdit`/`Verify-*`/`Request-Restart` |
| `Backup.Mpo.ps1` | MPO 备份闭环 | `Get-MpoValueSnapshot` + `Test/Ensure/Restore-MpoBackup` |
| `Backup.Bcd.ps1` | BCD 备份闭环 | `Test/Ensure/Restore-BcdBackup` |
| `Backup.Service.ps1` | 服务备份闭环 | `Ensure/Restore-ServiceBackup` |
| `Backup.SecurityMitigation.ps1` | CPU 缓解备份 | `Get-SecurityMitigationSnapshot` + 三元组 |
| `Backup.Nvme.ps1` | NVMe 备份与检测 | `Test-NvmeBackupSchema`/`Get-Nvme*Snapshot`/`Test-NativeNvme*`/`Ensure/Restore-Nvme` |
| `Menu.ps1` | 菜单调度 | `Show-TweakMenu`（11 个 Part 的调度，1358 行） |

主脚本通过 `. "$PSScriptRoot/Modules/X.ps1"` 点源，保持 `$script:ok/$fail/$skip/$rebootRequired` 与 `$PSScriptRoot` 锚点一致，测试点源不再触发菜单。

## 已确认基础组件

- 管理员权限检测
- 注册表 DWORD/字符串/二进制写入
- 注册表值删除恢复流程
- 执行成功/失败/跳过统计
- BCD `bcdedit` 封装与 `deletevalue` 保护
- 备份 Schema 校验（MPO/BCD/Service/Security/NVMe 共 5 套）

## 下一阶段

- 按独立度继续拆分 Parts（Power → Bcd(Part 2/3/4) → Mpo → Service → 剩余），Part 1 三子项暂不强拆
- 统一日志接口（`DETECTION`/`LOGGING` 设计已就绪，暂不替换输出）

## 原则

- 稳定优先，不改变已验证优化目标
- 不影响 `powershell -ExecutionPolicy Bypass -File .\tweakbyjie.ps1` 入口
- 所有结构调整可回退（`git checkout` 单文件恢复）

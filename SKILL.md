---
name: tweakbyjie
description: "Windows 模块化调优与回滚：先检测、再确认、后执行。"
version: 0.1.0
author: 3304711297, Hermes Agent
license: MIT
platforms: [windows]
metadata:
  hermes:
    tags: [windows, tuning, gaming, rollback, powershell]
    category: system
---

# tweakbyjie Skill

面向 Windows 10/11 的模块化调优工具。只改系统层设置；每次写入前保存原值，可按快照恢复；不修改游戏目录、不注入进程、不接触反作弊。

## When to Use

- 用户要求 Windows 游戏/系统调优、帧率或卡顿排查、电源计划/BCD/服务/MPO/MSI/QoS 配置；
- 需要先只读检测机器状态，再决定改什么；
- 需要可回滚的系统变更。

Don't use for:

- 修改游戏文件、注入进程、绕过或对抗反作弊；
- 未经用户确认的无人值守批量修改；
- 非 Windows 环境。

## Prerequisites

- Windows 10/11；PowerShell 5.1+（有 `pwsh` 7 时优先）。
- 应用/还原模块 1-14、17 需要管理员；`-Detect` 是只读检测，不需要提权。
- 仓库必须完整解压：`tweakbyjie.ps1` 与 `Modules/`、`scripts/`、`ultimate-performance.pow` 同目录。

## How to Run

用 `terminal` 调用，工作目录为仓库根：

```powershell
# 只读检测（Agent 首选入口）
pwsh -NoProfile -File .\tweakbyjie.ps1 -Detect -Json

# 非交互应用：<模块>=<子操作>
pwsh -NoProfile -File .\tweakbyjie.ps1 -RunModule 12 -Action "12=1"

# 还原：用对应模块的还原子操作
pwsh -NoProfile -File .\tweakbyjie.ps1 -RunModule 12 -Action "12=2"
```

交互模式给用户用：`.\tweakbyjie.cmd`。完整菜单与子操作见仓库 `README.md`；每个模块交互运行时会打印自己的子菜单。

## Quick Reference

| 项 | 值 |
| --- | --- |
| 退出码 | `0` 成功/无失败；`2` 参数错误；`4` 全项失败；`5` 部分失败 |
| 日志 | `%LOCALAPPDATA%\tweakbyjie\logs\session-*.log` |
| 检测 JSON | 单个对象：`schemaVersion`、`os`、`cpu`、`gpu`、`memory`、`health` |
| 输出编码 | `-Detect -Json` 输出纯 ASCII（非 ASCII 转 `\uXXXX`），任何代码页都能解析 |
| 健康项 | `health.results[].status` 为 `OK` / `Attention` / `Info` / `N/A` |
| 高风险放行 | 仅 `-AcceptDefaults`，且必须有用户对该项风险的明确同意 |

## Procedure

1. **检测**：运行 `-Detect -Json`。退出码非 0 则停止。
   完成判据：JSON 可解析且 `schemaVersion == 1`。
2. **解释**：向用户说明硬件、`Attention` 项、准备改什么、副作用、是否需要重启。
   完成判据：用户明确同意；未同意不得进入第 3 步。
3. **执行**：按模块/子操作调用 `-RunModule` + `-Action`。不要用 `-AcceptDefaults` 代替用户同意。
   完成判据：退出码 `0`，或 `5` 且能逐项说明失败原因。
4. **汇报**：区分成功、失败、跳过、体检异常；给出备份位置与还原方法。
5. **还原**：调用对应模块的还原子操作，再用 `-Detect` 或模块状态页复核。

## Module Map

| 模块 | 用途 | 需要 Action | 备注 |
| --- | --- | --- | --- |
| 1 | 核心游戏 / 系统行为 / CPU 缓解 / 驱动黑名单 | 是 | 子项 1/2 写入前快照；4=还原 |
| 2 | 高级 BCD / 计时器 / 启动安全 | 是 | 修改前 BCD 快照 |
| 3 / 4 | 开启 / 关闭测试模式 | 是 | Secure Boot 开启时预检灰掉 |
| 5 | 关闭安全中心（高风险） | 是 | 需完整风险短语；第三方杀软时灰掉 |
| 6 | 服务优化（A/B 分组） | 是 | 操作前 `service-backup.json` |
| 7 | 超性能电源计划 | 是 | 只应用/恢复 `.pow`，不逐项改隐藏电源项 |
| 8 | 原生 NVMe 驱动 | 是 | 依赖 ViVeTool；含 SafeBoot 快照 |
| 9 | 清除 Device Guard EFI 锁 | 是 | BitLocker 开启时灰掉 |
| 10 | 虚拟化 / VBS / Hyper-V | 是 | 修改前 `vbs-backup.json` |
| 11 | MPO 管理 | 是 | 三方案互斥，按首次快照恢复 |
| 12 | 竞技游戏网络 QoS | 是 | 修改前策略快照 |
| 13 | PCIe 设备 MSI 中断 | 是 | 白名单隔离 |
| 14 | 休眠与快速启动 | 是 | 修改前快照 |
| 15 | 系统体检 + 虚拟内存建议 | 否 | 纯只读；`-RunModule 15` 直接运行 |
| 16 | 着色器缓存扫描 / 清理 | 是 | 维护项；缓存可再生，不产生快照 |
| 17 | 游戏 exe 配置（FSO/GPU/CPU） | 是 | 保存三项原值；不写无效的 IFEO IoPriority |

## Red Lines

1. **不得代替用户同意**：`-AcceptDefaults` 只能放行用户已明确接受的具体风险，不能当“全部同意”。
2. **高风险模块先解释再执行**：5（Defender）、9（EFI）、10（VBS）、3/4（测试模式）必须有明确请求与恢复方案。
3. **不要绕过脚本直接改注册表/BCD**：快照与还原是唯一安全保障。
4. **不碰游戏目录与反作弊**：不修改游戏文件、不注入、不降反作弊进程优先级。
5. **不自动重启**：工具只标记待重启，由用户决定。
6. **`-Detect` 只读**：`N/A` 表示不适用/未检测到，不是失败。

## Pitfalls

- 非交互模式下，模块 1-14、16、17 必须给 `-Action`；模块 15 不需要。
- `-Detect` 不能与 `-RunModule` / `-Action` / `-NonInteractive` / `-AcceptDefaults` 组合；`-Json` 只能与 `-Detect` 组合。
- 快照与 `MachineGuid` 绑定，跨机器复制会被拒绝。
- 模块 1 的还原会跳过“优化后又被其他程序修改”的项并保留当前值；`-Force` 只应在用户明确要求覆盖时使用（菜单未开放）。
- 模块 1 的 Memory Compression 与 TRIM 不在注册表快照范围内；模块 16 按设计没有快照。
- 退出码 `5` 是部分失败：逐项读输出，不要盲目重试。

## Verification

- `-Detect -Json` 可解析，`schemaVersion == 1`，`health.results` 非空。
- 应用后退出码为 `0` 或 `5`，输出逐项列出成功/失败/跳过。
- 还原后用 `-Detect` 或模块状态页复核原值；注册表冲突项应明确显示“已保留当前值”。

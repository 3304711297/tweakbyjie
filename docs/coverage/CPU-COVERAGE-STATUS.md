# CPU 优化覆盖检查

## 目标

确认 `tweakbyjie.ps1` 中 CPU、MMCSS 多媒体调度和 Games 任务相关的每一个实际执行项，是否在 `youshouldknow` 中有可核对的对应说明。

## 检查范围与结果

共同执行入口：`tweakbyjie.ps1` 主菜单 `1` → `Part 1` 核心游戏优化 → 子项 `1`。

| 编号 | 项目 | 当前源码位置 | 知识文档对应 | 五项说明状态 | 执行闭环状态 |
| --- | --- | --- | --- | --- | --- |
| CPU-001 | `Win32PrioritySeparation` | `tweakbyjie.ps1:796`，目标 `REG_DWORD 38`（`0x26`） | `youshouldknow/项目导航/CPU优化与tweakbyjie对应说明.md` | ✅ 原理、目的、适用环境、影响、恢复均已补齐 | ⚠️ 有回读验证（`:813`），但当前脚本未提供自动备份/恢复 |
| CPU-002 | `Multimedia SystemProfile` | `tweakbyjie.ps1:793-794`，包含其下独立值 | `youshouldknow/项目导航/CPU优化与tweakbyjie对应说明.md` | ✅ 原理、目的、适用环境、影响、恢复均已补齐 | ⚠️ 没有统一回读、备份或恢复流程 |
| CPU-003 | `SystemResponsiveness` | `tweakbyjie.ps1:794`，目标 `REG_DWORD 10` | `youshouldknow/项目导航/CPU优化与tweakbyjie对应说明.md` | ✅ 原理、目的、适用环境、影响、恢复均已补齐 | ⚠️ 当前源码没有回读验证、自动备份或恢复 |
| CPU-004 | `NetworkThrottlingIndex` | `tweakbyjie.ps1:793`，目标 `REG_DWORD 0xFFFFFFFF` | `youshouldknow/项目导航/CPU优化与tweakbyjie对应说明.md` | ✅ 原理、目的、适用环境、影响、恢复均已补齐 | ⚠️ 当前源码没有回读验证、自动备份或恢复 |
| CPU-005 | `Tasks\Games` | `tweakbyjie.ps1:800-807`，七个值的目标值已列明 | `youshouldknow/项目导航/CPU优化与tweakbyjie对应说明.md` | ✅ 原理、目的、适用环境、影响、恢复均已补齐 | ⚠️ 当前源码没有七个值的回读验证、自动备份或恢复 |

## 检查要求

每个项目需要对应：

- Windows 原理
- 修改目的
- 适用环境
- 潜在影响
- 恢复方式
- 实际执行位置、注册表路径、值名和目标值
- 可复核的验证方法

## 检查结论

- CPU-001 至 CPU-005 已根据当前 `tweakbyjie.ps1` 源码完成逐项关键词和路径核对，不再是“待确认”。
- `SystemResponsiveness`、`NetworkThrottlingIndex` 和 `Tasks\Games` 已作为独立执行项目列出，未被笼统的 `Multimedia SystemProfile` 项目吞并。
- 知识说明覆盖完成，不代表脚本执行生命周期已经闭环。当前 CPU 项目仍存在统一备份、恢复和回读验证缺口。
- `Win32PrioritySeparation` 的脚本值是十进制 `38`，等价于十六进制 `0x26`；不得将其误写成 `0x38`。
- `Tasks\Games\Clock Rate=10000` 属于 MMCSS 游戏任务配置，不应在说明中表述为直接控制 GPU 硬件时钟。

## 追踪记录

- 源码核对文件：`tweakbyjie.ps1`
- 知识说明文件：`youshouldknow/项目导航/CPU优化与tweakbyjie对应说明.md`
- 映射文件：`youshouldknow/项目导航/tweakbyjie-optimization-mapping.md`
- 本次更新仅记录 CPU 文档覆盖状态，未修改 `tweakbyjie.ps1` 的执行逻辑。

完成 CPU 类后继续检查 GPU、Memory、Storage、Security、Service、Boot 和 Registry 等分类。

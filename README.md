# tweakbyjie ⚡

<p align="center">
  <strong>面向 Windows 10 / 11 的模块化系统底层调优、BCD 启动配置与游戏性能优化工具集</strong>
</p>

<p align="center">
  <a href="https://github.com/3304711297/tweakbyjie/releases"><img src="https://img.shields.io/github/v/release/3304711297/tweakbyjie?style=flat-square&color=blue&label=Latest%20Release" alt="Latest Release"></a>
  <a href="https://github.com/3304711297/tweakbyjie/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/3304711297/tweakbyjie/ci.yml?branch=main&label=CI%20Check&style=flat-square" alt="CI Status"></a>
  <img src="https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-5391FE?style=flat-square&logo=powershell" alt="PowerShell">
  <img src="https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011-0078D6?style=flat-square&logo=windows" alt="Platform">
  <a href="https://3304711297.github.io/youshouldknow/项目导航/覆盖矩阵/"><img src="https://img.shields.io/badge/Coverage-100%25%20Verified-brightgreen?style=flat-square" alt="Coverage"></a>
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License">
</p>

---

> ⚠️ **重要风险声明**：这是面向个人设备和测试环境的高级系统调优工具，**不是“无脑一键加速”**。所有涉及底层 BCD、系统服务与安全配置的操作均包含完整的状态快照备份机制。在执行高风险修改前，请确保理解其影响并已记录原始系统状态。

---

## ⚡ 30 秒极速上手

### 1. 下载推荐
普通使用请直接前往 [GitHub Releases](https://github.com/3304711297/tweakbyjie/releases) 下载最新版本的 **精简运行包 ZIP**（`tweakbyjie-v*.zip`），解压到本地任意目录（无需编译或安装开发依赖）。

### 2. 启动菜单
右键“开始”菜单 → 选择 **Windows 终端（管理员）** 或 **PowerShell（管理员）**，进入解压目录后运行：

```powershell
# 推荐启动方式（自动优先使用 PowerShell 7，未安装时无缝回退至系统内置 5.1）
.\tweakbyjie.cmd

# 或手动通过指定运行时启动
powershell -ExecutionPolicy Bypass -File .\tweakbyjie.ps1       # Windows PowerShell 5.1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tweakbyjie.ps1       # PowerShell 7+
```

---

## 🎯 菜单模块功能速览与知识库联动

脚本所有调优项与知识库 [YouShouldKnow 覆盖矩阵](https://3304711297.github.io/youshouldknow/项目导航/覆盖矩阵/) 保持 100% 严密对齐与双向映射：

| 选项 | 模块名称 | 核心调优内容与实现 | 原理解析 (YouShouldKnow) |
| :---: | :--- | :--- | :--- |
| **1** | **核心游戏/系统性能优化** | GameDVR、MMCSS 调度、HAGS 硬件加速、Memory Compression、NTFS 8.3、TRIM 与 CPU 安全缓解 | [CPU 优化对应说明](https://3304711297.github.io/youshouldknow/项目导航/CPU优化与tweakbyjie对应说明/) · [GPU 调度管线](https://3304711297.github.io/youshouldknow/项目导航/GPU调度与显示管线/) |
| **2** | **高级 BCD / 计时器与启动** | 高精度计时器、`nx` 执行保护、TPM Boot Entropy、驱动签名检查（内置 BCD 快照回滚） | [Windows 启动配置解析](https://3304711297.github.io/youshouldknow/系统知识/Windows启动配置与tweakbyjie对应说明/) |
| **3** | **开启测试模式** | 开启 `testsigning`、系统调试与 `nointegritychecks`（适用于驱动开发/无签名驱动测试） | [Windows 启动配置解析](https://3304711297.github.io/youshouldknow/系统知识/Windows启动配置与tweakbyjie对应说明/) |
| **4** | **关闭测试模式** | 恢复关闭 `testsigning` 与 `debug`，按设计保留 `nointegritychecks` 基础配置 | [Windows 启动配置解析](https://3304711297.github.io/youshouldknow/系统知识/Windows启动配置与tweakbyjie对应说明/) |
| **5** | **关闭安全中心 (高风险)** | 深度配置 Defender、SmartScreen 策略，需输入 `I-UNDERSTAND-RISK` 确认 | [Defender 风险与恢复边界](https://3304711297.github.io/youshouldknow/系统知识/Defender删除脚本风险与恢复边界/) |
| **6** | **系统服务优化** | 精简 30 个冗余服务为 Disabled、7 个设为 Manual；操作前自动落盘 `service-backup.json` | [Windows 服务优化原则](https://3304711297.github.io/youshouldknow/系统调优与安全/Windows服务优化原则/) |
| **7** | **超性能电源计划** | 导入并激活 `ultimate-performance.pow`，自动备份并支持恢复上一电源计划 | [电源计划创建与优化指南](https://3304711297.github.io/youshouldknow/系统知识/电源计划创建与优化指南/) |
| **8** | **原生 NVMe 驱动切换** | 基于 ViVeTool 特性开关启用 Windows 11 原生 NVMe 驱动栈（支持快照还原） | [存储与 NVMe 原理](https://3304711297.github.io/youshouldknow/内存与存储/存储与NVMe原理/) |
| **9** | **清除 EFI 锁定 (Device Guard)** | 执行 SecConfig.efi 解锁流程，内置 BitLocker 状态强制检测 | [VBS 与系统安全缓解](https://3304711297.github.io/youshouldknow/系统调优与安全/VBS与系统安全缓解/) |
| **10** | **虚拟化 / VBS / Hyper-V** | 独立查看、关闭或配置 VBS 与 Hyper-V 虚拟化环境 | [VBS 与系统安全缓解](https://3304711297.github.io/youshouldknow/系统调优与安全/VBS与系统安全缓解/) |
| **11** | **MPO (多平面叠加) 管理** | 提供 3 种互斥的社区防掉帧/防闪烁排障模式，支持子选项一键恢复默认 | [GPU 调度与显示管线](https://3304711297.github.io/youshouldknow/项目导航/GPU调度与显示管线/) |
| **12** | **竞技游戏网络 QoS 策略管理** | 为游戏流量配置 DSCP 46 优先标记与网络 QoS 策略（吸收自 Kiwi-Tweaks），操作前自动落盘策略快照 | — |

---

## 🛡️ 安全防御体系与执行机制

### 1. 启动预检与智能模块灰掉 (Preflight)
脚本启动时会自动执行硬件与系统环境扫描（`scripts/preflight.ps1`），若环境不满足前置条件，对应菜单项将显示 `[不适用] (原因)` 并自动禁止触发：
- **Secure Boot 开启时** ── 自动灰掉 **菜单 3 / 4（测试模式）**；
- **检测到第三方杀毒软件时** ── 自动灰掉 **菜单 5（安全中心）**；
- **未检测到 ViVeTool 时** ── 自动灰掉 **菜单 8（原生 NVMe）**；
- **BitLocker 启用时** ── 自动灰掉 **菜单 9（清除 EFI 锁）**，防止改变 TPM 度量导致锁盘。

### 2. 高风险双重短语确认
对于破坏性/不可逆级别操作（菜单 5 和菜单 9），必须按提示输入完整的区分大小写短语：
`I-UNDERSTAND-RISK`
输入任何其他字符或直接回车将立即安全取消，不做任何系统变动。

### 3. 非交互式与自动化命令行接口
支持通过参数直接指定模块队列，用于自动化批量部署：

```powershell
# 1. 队列执行指定模块（执行完毕后交互询问重启）
.\tweakbyjie.cmd -RunModule "7,11"

# 2. 显式无人值守模式（接受默认行为，会话收尾默认绝不自动重启主机）
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tweakbyjie.ps1 -RunModule "7" -AcceptDefaults
```

* **会话日志自动落盘**：所有命令行及交互输出均自动写入 `%LOCALAPPDATA%\tweakbyjie\logs\session-*.log`。
* **标准退出码规范**：`0` 成功/无失败，`2` 参数错误，`4` 全项失败，`5` 部分失败。

---

## 📂 项目架构与关键组件

```text
tweakbyjie/
├── tweakbyjie.cmd           # 双运行时智能启动器 (pwsh / powershell 5.1)
├── tweakbyjie.ps1           # 核心加载器 Loader (带版本注入与全局会话管理)
├── Modules/                 # 模块化实现目录 (纯调度 + 独立功能模块)
│   ├── Common.ps1           # 日志、退出码与基础通用工具库
│   ├── Adapters.ps1         # 注册表与系统调用副作用隔离适配器
│   ├── Backup.*.ps1         # 各模块独立快照保存与恢复闭环
│   ├── Core.ps1             # 模块 1: 核心优化
│   ├── Bcd.ps1              # 模块 2/3/4: BCD 启动与测试模式
│   ├── Defender.ps1         # 模块 5: 安全中心策略
│   ├── Service.ps1          # 模块 6: 服务优化与快照
│   ├── Power.ps1            # 模块 7: 电源计划
│   ├── Nvme.ps1             # 模块 8: NVMe 驱动
│   ├── EfiLock.ps1          # 模块 9: EFI 锁清除
│   ├── Vbs.ps1              # 模块 10: 虚拟化与 VBS
│   ├── Mpo.ps1              # 模块 11: MPO 管理
│   ├── GameQos.ps1          # 模块 12: 竞技游戏网络 QoS 策略
│   └── Menu.ps1             # 104 行高内聚纯菜单调度链
├── scripts/preflight.ps1    # 启动前置条件只读探测器
└── ultimate-performance.pow # 超性能电源计划源文件 (SHA256 校验保障)
```

---

## 🤝 贡献与测试

本项目采用 Pester 6 进行全覆盖单元测试与往返测试（Roundtrip Tests）：

```powershell
# 运行完整 Pester 自动化测试套件
$env:TWEAK_SKIP_ADMIN_CHECK = "1"
Invoke-Pester -Path .\tests\
```

---

## 🧬 上游采纳与外部依赖

本项目的部分调优项吸收自以下优秀开源项目，在叠加自身的快照备份、前置校验与回滚体系后落地为独立模块或注册表策略。仓库同时维护**上游看门 CI**（`upstream-watch`，每周一/三/五北京时间 10:00 自动巡检）：下表全部来源（含外部工具依赖）均已登记进 `tools/upstream-sources.json`，看门跟踪其**全部分支的完整提交区间**（基线到头部的每条 commit 均列入 Issue 明细）与最新 release，并自动发现远端新增/消失的分支，发现更新时自动开启 `upstream-watch` 标签 Issue 提醒，避免吸收内容随上游迭代而失联：

| 来源项目 | 仓库 | 吸收内容与落地位置 |
| :--- | :--- | :--- |
| **Kiwi-Tweaks** (v2.0) | [contactkiwitweaks-stack/Kiwi-Tweaks](https://github.com/contactkiwitweaks-stack/Kiwi-Tweaks) | 竞技游戏网络 QoS 优化思路 → 菜单 12「竞技游戏网络 QoS 策略管理」（`Modules/GameQos.ps1`，DSCP 46 数据包优先） |
| **Atom-Tool-Box** (0.1.5) | [ProjectAtomOS/Atom-Tool-Box](https://github.com/ProjectAtomOS/Atom-Tool-Box) | WPBT 固件注入防御（`DisableWpbtExecution`）、任务栏右键直接结束任务（`TaskbarEndTask`）、PowerShell Core 遥测关闭 → 菜单 1 核心优化注册表策略（`Modules/Registry.ps1`） |
| **MPO-GPU-FIX**（社区排障经验） | [RedDot-3ND7355/MPO-GPU-FIX](https://github.com/RedDot-3ND7355/MPO-GPU-FIX) | MPO 防掉帧/防闪烁排障注册表方案参考 → 菜单 11「MPO 管理」（详见 [优化详情文档](docs/reference/OPTIMIZATION-DETAILS.md)） |

外部工具依赖：

| 工具 | 仓库 | 用途 |
| :--- | :--- | :--- |
| **ViVeTool** | [thebookisclosed/ViVe](https://github.com/thebookisclosed/ViVe) | 菜单 8「原生 NVMe 驱动」依赖其 A/B 特性开关能力（特性 ID 60786016 + 48433719）；未检测到时该菜单项自动灰掉 |

> 上游清单（含同步的 commit 与版本号）以机器可读格式维护在 `tools/upstream-sources.json`。新增采纳来源时需同步更新该文件并接入看门 CI，保持文档、清单与 CI 三方一致。

---

## 📄 开源许可

本项目采用 [MIT 许可证](LICENSE) 开源。

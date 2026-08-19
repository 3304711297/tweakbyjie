# tweakbyjie

Windows 游戏与系统优化工具集，包含菜单式 PowerShell 主脚本，以及一个高风险的 Defender 物理移除脚本。

> 这是面向个人设备和测试环境的高级工具，不是“无脑一键加速”。请先阅读风险说明、记录当前状态，并准备系统还原点或完整备份。

## 下载后先看这里

### 普通用户推荐流程

1. 将整个仓库下载到本地，不要单独移动脚本或旁车文件。
2. 确认 `tweakbyjie.ps1`、`ultimate-performance.pow` 位于同一目录。
3. 右键“开始”→ **Windows 终端（管理员）**，进入仓库目录。
4. 运行主脚本：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\tweakbyjie.ps1
   ```

5. 先使用菜单中的查看/备份能力，再决定是否应用修改；需要重启的操作会在退出主菜单时统一询问。

`-ExecutionPolicy Bypass` 只对本次 PowerShell 进程生效，通常不需要为了运行本项目而修改系统级执行策略。脚本会自行检查管理员权限；普通权限运行会被拒绝。

### 运行文件与旁车资源

以下文件组成主脚本的运行单元：

| 文件 | 用途 | 说明 |
|---|---|---|
| `tweakbyjie.ps1` | 主优化脚本 | 菜单 0–11，包含普通优化、高级启动、安全和显示排障功能 |
| `ultimate-performance.pow` | 超性能电源计划 | 必须和主脚本同目录，菜单 7 使用 |
| `ViVeTool.exe` | 可选外部工具 | 菜单 8 原生 NVMe 功能需要；放在脚本目录或加入 PATH |
| `*-backup.*` | 运行后生成的快照 | 由脚本放在脚本目录，恢复时不要手动移动、改名或删除 |
| `defender-removal.ps1` | Defender 物理移除脚本 | 独立的不可逆高级脚本，不属于普通优化流程 |

当前仓库不会预先包含运行时生成的 JSON/备份文件。若你已经在旧目录运行过脚本，迁移仓库时必须把旧目录中的备份和主脚本作为整体保留，否则恢复功能可能找不到原始快照。

## 风险等级

| 等级 | 入口 | 建议 |
|---|---|---|
| 低到中 | 菜单 1 的部分游戏/系统配置、菜单 6 服务调整 | 先记录原值，确认功能影响后逐项测试 |
| 需要备份 | 菜单 1→3、菜单 2、菜单 6、菜单 7、菜单 8、菜单 11 | 确认对应快照已生成，并准备重启/恢复方案 |
| 高风险 | 菜单 2 的启动安全子项、菜单 5、菜单 9、菜单 10 | 可能影响安全、启动、BitLocker、WSL2、Docker、虚拟机或更新；不熟悉时不要执行 |
| 不可逆 | `defender-removal.ps1` | 删除系统组件、注册表和文件；没有脚本内撤销功能，需系统修复或重装恢复 |

## `tweakbyjie.ps1` 菜单

| 选项 | 功能 | 主要内容 |
|---|---|---|
| **1** | 核心游戏 / 系统性能优化 | GameDVR、GameBar、MMCSS、CPU 调度、HAGS、Prefetch、Memory Compression、NTFS 8.3、TRIM、视觉效果和 CPU 安全缓解 |
| **2** | 高级 BCD / 计时器与启动安全 | 计时器、`nx`、TPM Boot Entropy、完整性检查；高风险，使用 BCD 快照 |
| **3** | 开启测试模式 | `testsigning`、调试和 `nointegritychecks`；仅用于测试/调试环境 |
| **4** | 关闭测试模式 | 删除 `testsigning`、`debug`，但按当前脚本行为保留 `nointegritychecks` |
| **5** | 关闭安全中心 | Defender、SmartScreen 和安全中心策略；部分分支还会删除服务、任务、启动项或 `SecHealthUI` |
| **6** | 服务优化 | 30 个服务设为 Disabled、7 个服务设为 Manual；修改前保存 `service-backup.json`，子选项 2 恢复启动类型 |
| **7** | 超性能电源计划 | 备份当前计划后导入 `ultimate-performance.pow`，支持恢复备份 |
| **8** | 原生 NVMe 驱动 | 需要 ViVeTool 和符合条件的系统/设备；使用 `nvme-backup.json`，重启后检查驱动状态 |
| **9** | 清除 Device Guard EFI 锁定 | SecConfig.efi 流程，包含 BitLocker 保护检查；不是普通性能优化 |
| **10** | 虚拟化 / VBS / Hyper-V | 查看、关闭或删除脚本覆盖并尝试启用 Hyper-V；恢复不是原始状态精确回滚 |
| **11** | MPO 设置管理 | 三种互斥的社区排障方案，首次修改前备份，子选项 4 恢复 |

## 恢复与备份

脚本使用 `$PSScriptRoot` 在主脚本所在目录读取/生成：

- `mpo-backup.json`
- `bcd-backup.json`
- `service-backup.json`
- `security-mitigation-backup.json`
- `nvme-backup.json`
- `power-backup.pow`

不同模块的恢复能力不同：MPO、BCD、服务、电源和 NVMe 有相应快照；核心注册表、Part 5 安全中心停用、VBS/EFI 操作不能保证精确回滚。恢复前先确认备份文件属于当前这台机器和当前脚本版本。

## Defender 物理移除脚本

如无明确需求，请不要运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\defender-removal.ps1
```

该脚本不是“禁用 Defender”，而是删除服务注册、系统注册表对象和实体文件，没有可逆的脚本内恢复流程。详情见 [Defender 删除脚本风险与恢复边界](https://github.com/3304711297/youshouldknow/blob/main/%E7%B3%BB%E7%BB%9F%E7%9F%A5%E8%AF%86/Defender%E5%88%A0%E9%99%A4%E8%84%9A%E6%9C%AC%E9%A3%8E%E9%99%A9%E4%B8%8E%E6%81%A2%E5%A4%8D%E8%BE%B9%E7%95%8C.md)；离线下载的单仓库副本可直接阅读 `defender-removal.ps1` 内置警告。

## 文档导航

- [优化详情参考](./docs/reference/OPTIMIZATION-DETAILS.md)：每个菜单和目标值的详细说明
- [覆盖与映射文档](./docs/coverage/)：CPU 覆盖、项目追踪和 `tweakbyjie → youshouldknow` 对应关系
- [设计与开发文档](./docs/design/)：模块接口、检测、备份、路线图和内部设计
- [CPU 覆盖状态](./docs/coverage/CPU-COVERAGE-STATUS.md)：当前跨项目逐项核对结果

## 免责声明

本项目按“原样”提供，仅供学习和个人测试使用。使用者需自行承担因修改系统配置、安全功能、启动配置或文件造成的任何后果。请勿在生产环境、受管理的公司设备或没有恢复方案的机器上运行。

## 许可证

[MIT](./LICENSE)

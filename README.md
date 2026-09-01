# tweakbyjie

Windows 游戏与系统优化工具集，包含菜单式 PowerShell 主脚本，以及一个高风险的 Defender 物理移除脚本。

> 当前版本与各版本变更见 GitHub Releases（说明由发布时自动生成）；脚本菜单标题会显示运行版本（与 Git tag 及 Release 对应）。

> 这是面向个人设备和测试环境的高级工具，不是“无脑一键加速”。请先阅读风险说明、记录当前状态，并准备系统还原点或完整备份。

## 下载方式

普通使用优先下载 GitHub Releases 中的 **精简运行包 ZIP**。运行包只包含脚本实际运行所需文件与必要说明，不包含测试、CI、Coverage 审计等开发资料。

开发、审计或需要查看完整源码时，再下载源码仓库或 GitHub 的 Source code ZIP。

## 下载后先看这里

### 普通用户推荐流程

1. 将运行包完整解压到本地，不要单独移动脚本或旁车文件。
2. 确认 `tweakbyjie.ps1`、`Modules/`、`ultimate-performance.pow` 位于同一运行包目录结构中。
3. 右键“开始”→ **Windows 终端（管理员）**，进入运行包目录。
4. 运行主脚本（任选其一）：

   ```powershell
   # 推荐：启动器会自动优先使用 PowerShell 7（pwsh），未安装时回退系统内置的 Windows PowerShell 5.1
   .\tweakbyjie.cmd

   # 或手动指定运行时
   powershell -ExecutionPolicy Bypass -File .\tweakbyjie.ps1   # Windows PowerShell 5.1（系统内置）
   pwsh -NoProfile -ExecutionPolicy Bypass -File .\tweakbyjie.ps1   # PowerShell 7+（需自行安装）
   ```

5. 先使用菜单中的查看/备份能力，再决定是否应用修改；需要重启的操作会在退出主菜单时统一询问。

### 非交互执行（可选）

支持直接指定模块编号跳过菜单，编号间用逗号分隔，执行完毕后统一询问是否重启：

```powershell
.\tweakbyjie.cmd -RunModule 7          # 只执行模块 7（超性能电源计划）
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tweakbyjie.ps1 -RunModule "7,11"
```

作为脚本运行时，全部输出会自动记录到 `%LOCALAPPDATA%\tweakbyjie\logs\session-*.log`，便于回溯本次改动。

**无人值守开关 `-AcceptDefaults`（仅与 `-RunModule` 组合时生效）**：定义为"显式请求无人值守执行，并接受该模块定义的默认风险行为"。语义边界：

- 模块内的确认（含菜单 5/9 的高风险短语确认）自动接受，不再交互询问；
- 退出时的重启属于会话级收尾，维持默认 **不重启**，绝不自动重启机器；
- **不单独存在**：不带 `-RunModule` 使用视为参数误用（报错退出，退出码 `2`）；
- **不等于"自动执行一切危险操作"**：只有显式出现在 `-RunModule` 队列里的模块才会执行，且各模块的前置条件灰掉（见下节）在无人值守模式下同样生效。

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tweakbyjie.ps1 -RunModule "7" -AcceptDefaults   # 无人值守执行模块 7
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tweakbyjie.ps1 -AcceptDefaults                  # 参数误用，退出码 2
```

退出码约定：`0` 表示没有失败项（包括未修改或用户取消），`2` 表示模块参数无效（含 `-AcceptDefaults` 参数误用），`4` 表示全部执行项失败，`5` 表示部分成功且存在失败项。退出码不能证明运行时性能收益；仍需查看日志和各模块的验证输出。不带 `-AcceptDefaults` 时 `-RunModule` 只负责将模块编号加入执行队列，子模块仍可能要求输入，不能当作完全无人值守接口。

### 启动预检与按模块灰掉

启动进入菜单时会运行一次预检（`scripts/preflight.ps1`），检测：Windows 构建号、VBS 运行状态、BitLocker、Secure Boot、第三方杀软、ViVeTool 存在性。结果缓存到当前会话并写入会话日志（`[PREFLIGHT]` 单行摘要，便于 grep）。

预检按**模块 → 前置条件**映射灰掉个别菜单项（显示 `[不适用]（原因）`，选择或队列执行时被拒绝）：

| 检测结果 | 被灰掉的模块 | 原因 |
|---|---|---|
| Secure Boot 开启 | 菜单 3 / 4（测试模式） | testsigning 无法生效 |
| 第三方杀软运行 | 菜单 5（关闭安全中心） | 安全中心类修改与其明确冲突 |
| ViVeTool.exe 缺失 | 菜单 8（原生 NVMe） | 启用路径依赖 ViVeTool 特性开关 |
| BitLocker 已开启 | 菜单 9（清除 EFI 锁） | 改变 TPM 度量值会触发恢复模式（与模块内既有预检查同一判据，仅提前到菜单层） |

设计边界：**没有任何"系统检测结果 → 全局禁用"的大一统阻断**——每条判据只影响表中列出的模块，其余模块永远可用；任何检测项失败/未知（如非 UEFI 环境、SecurityCenter2 不可用）按"不灰"处理，不会因检测环境异常扩大禁用面。灰掉只发生在菜单层，各模块执行函数与既有预检查（如菜单 9 的 BitLocker 预检查）保持原样。

### 高风险操作确认（菜单 5 / 菜单 9）

菜单 5（关闭安全中心的删除类优化）与菜单 9（清除 Device Guard EFI 锁定）在原 Y/N 确认基础上升级为**完整短语确认**：按提示完整输入 `I-UNDERSTAND-RISK`（区分大小写）才会执行，输入其他任何内容或直接回车一律取消且不做任何修改。`-AcceptDefaults` 无人值守模式下该确认自动接受（见上节语义边界）。

`-ExecutionPolicy Bypass` 只对本次 PowerShell 进程生效，通常不需要为了运行本项目而修改系统级执行策略。脚本会自行检查管理员权限；普通权限运行会被拒绝（本地开发/CI 可设 `TWEAK_SKIP_ADMIN_CHECK=1` 跳过检查）。主脚本在 Windows PowerShell 5.1 与 PowerShell 7+ 下均已验证可运行；CI 同时覆盖两个运行时。

### 运行文件与旁车资源

以下文件组成主脚本的运行单元：

| 文件 | 用途 | 说明 |
|---|---|---|
| `tweakbyjie.ps1` | 主入口（Loader，点源 `Modules/`；也可用 `tweakbyjie.cmd` 启动器自动选择 pwsh/5.1） | 菜单 0–11 的调度入口，需与 `Modules/` 整体保留 |
| `Modules/` | 模块化实现 | `Common.ps1` 通用能力 + `Adapters.ps1` 可注入副作用边界 + `Backup.*.ps1` 备份闭环 + 各功能模块 + `Menu.ps1` 菜单调度；缺失任一模块将导致功能不完整 |
| `scripts/preflight.ps1` | 启动预检与模块前置条件映射 | 只读检测 + 菜单可用性判断；不执行任何系统修改 |
| `ultimate-performance.pow` | 超性能电源计划（内嵌名 `kirby`，16384 bytes，SHA256 `2EADB1A9`…`2868C7B`，详见 `docs/POWER-PLAN-SOURCE.md`） | 必须和主脚本按运行包原始目录结构保留，菜单 7 使用（导入激活后会被统一改名为 ultimate-performance）；建议先执行 `Get-FileHash .\ultimate-performance.pow -Algorithm SHA256` 校验 |
| `ViVeTool.exe` | 可选外部工具 | 菜单 8 原生 NVMe 功能需要；放在脚本目录或加入 PATH |
| `*-backup.*` | 运行后生成的快照 | 由脚本放在脚本目录，恢复时不要手动移动、改名或删除 |
| `defender-removal.ps1` | Defender 物理移除脚本 | 默认仅 DryRun；只有显式 `-Execute` 才进入不可逆删除流程，不属于普通优化流程 |

当前仓库不会预先包含运行时生成的 JSON/备份文件。若已经在旧目录运行过脚本，迁移运行环境时必须把旧目录中的备份和主脚本作为整体保留，否则恢复功能可能找不到原始快照。

`defender-removal.ps1` 默认只输出 DryRun 清单，不会修改系统；真正执行必须使用 `-Execute` 并完成两次 `REMOVE` 确认。执行后默认不自动重启，只有在确认系统状态且显式使用 `-Restart` 时才会进入重启倒计时；出现失败项时始终禁止重启。该脚本没有完整自动恢复能力，不应在日常系统或普通 CI runner 上执行。

## 风险等级

| 等级 | 入口 | 建议 |
|---|---|---|
| 低到中 | 菜单 1 的部分游戏/系统配置、菜单 6 服务调整 | 先记录原值，确认功能影响后逐项测试 |
| 需要备份 | 菜单 1→3、菜单 2、菜单 6、菜单 7、菜单 8、菜单 11 | 确认对应快照已生成，并准备重启/恢复方案 |
| 高风险 | 菜单 2 的启动安全子项、菜单 5、菜单 9、菜单 10 | 可能影响安全、启动、BitLocker、WSL2、Docker、虚拟机或更新；不熟悉时不要执行 |
| 不可逆 | `defender-removal.ps1 -Execute` | 默认 DryRun；显式执行后会删除系统组件、注册表和文件，没有脚本内撤销功能，需系统修复或重装恢复；执行后默认不重启 |

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

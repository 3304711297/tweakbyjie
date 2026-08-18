# tweakbyjie

Windows 游戏优化脚本（菜单版）— 系统优化 / 测试模式开关 / 关闭安全中心，一键完成。另附 Defender 物理移除高级脚本。

---

## ⚠️ 运行前必看：开启 PowerShell 执行策略

如果双击或运行脚本时提示**无法运行 / 禁止执行脚本**，需要先在系统设置中开启执行策略：

1. 打开 **设置**
2. 进入 **系统** → **高级** → **终端**
3. 展开 **PowerShell** 一栏
4. 将 **更改执行策略** 切换为 **开**（允许本地 PowerShell 脚本在未签名的情况下运行，远程脚本仍需签名）

开启后即可正常运行本项目的脚本。

---

## 脚本列表

| 文件 | 作用 | 可逆性 |
|---|---|---|
| `tweakbyjie.ps1` | 主优化脚本（分层菜单版） | ⚠️ 部分可逆（MPO/高级 BCD 有快照；服务/Defender 等需按文档人工检查） |
| `defender-removal.ps1` | Defender 物理移除（高级） | ❌ 不可逆（删键/删文件，需重装系统恢复） |
| `ultimate-performance.pow` | 超性能电源计划文件（配合选项 7 使用） | ✅ 可逆（选项 7 → 2 恢复备份） |

> 想了解每个脚本具体修改了哪些注册表、BCDEdit 启动项和服务？详见 **[优化详情参考 (OPTIMIZATION-DETAILS.md)](./OPTIMIZATION-DETAILS.md)**。

---

## tweakbyjie.ps1 — 功能菜单

脚本采用“**分层执行 + 会话待重启**”设计：一次运行可以连续处理多个模块；普通游戏优化不会自动修改 Hyper-V/VBS、高级 BCD 启动安全项或 MPO。需要重启的修改会进入待重启状态，模块结束只提示，退出主菜单时统一询问是否重启。

| 选项 | 功能 | 主要内容 |
|---|---|---|
| **1** | 核心游戏 / 系统性能优化 | 进入三级子菜单：`1` 核心游戏（GameDVR/GameBar、ActivationType、Multimedia 调度、Win32PrioritySeparation=38、HAGS、Games 任务、Game Mode）；`2` 系统行为（搜索、EnablePrefetcher=0、NTFS 8.3、Memory Compression、TRIM、视觉效果）；`3` CPU 安全缓解（FeatureSettingsOverride/Mask=3，带 `security-mitigation-backup.json` 备份和恢复）。**不包含** Hyper-V/VBS、高级 BCD、MPO。 |
| **2** | 高级 BCD / 计时器与启动安全 | 计时器配置独立执行；`nx`、`tpmbootentropy`、`nointegritychecks` 单独作为高风险子项，并在修改前写入 `bcd-backup.json`。微软文档将部分计时器项和 `tscsyncpolicy` 标注为调试用途；`nointegritychecks` 会关闭完整性检查且 Secure Boot 开启时不能设置。 citeturn323825search1 |
| **3** | 开启测试模式 | `testsigning / debug / dbgsettings local / nointegritychecks`。 |
| **4** | 关闭测试模式 | 删除 `testsigning / debug` 启动项，保留 `nointegritychecks`。 |
| **5** | 关闭安全中心 | Defender / SmartScreen 策略及可选删除类操作。 |
| **6** | 服务优化 | A/B 功能依赖分组；Xbox、蓝牙、嵌入模式、BITS 改为 Manual；执行后验证启动类型。首次执行前保存 `service-backup.json`，子选项 2 可按快照恢复启动类型。 |
| **7** | 超性能电源计划 | 备份当前计划后导入/应用，支持恢复备份。 |
| **8** | 原生 NVMe 驱动 | 优先使用 ViVeTool 启用 Feature `60786016` + `48433719`；启用前保存 Version 3 `nvme-backup.json`（Feature、SafeBoot、旧 Override 原始状态），还原时按快照恢复。旧 Override 仅查看，不再作为生效证明；需重启后以 `nvmedisk` 驱动 `Running` 确认实际切换。 |
| **9** | Device Guard EFI 锁定 | SecConfig.efi 流程，包含 BitLocker 预检查。 |
| **10** | 虚拟化 / VBS / Hyper-V 管理 | 独立管理 VBS/HVCI/Credential Guard、`hypervisorlaunchtype`、Hyper-V 功能组件；支持查看、关闭、删除脚本覆盖并尝试启用 Hyper-V（不是原始状态精确回滚）。微软当前文档给出的完整禁用 Hyper-V 路径包括禁用 `Microsoft-Hyper-V-All` 与设置 `hypervisorlaunchtype off`；Hyper-V 官方安装支持 Pro/Enterprise，不支持 Home。 citeturn323825search0turn323825search8 |
| **11** | MPO 设置管理 | 三方案互斥、首次修改前备份、恢复功能；保持为独立排障模块。 |

## tweakbyjie.ps1 — 使用方法

1. 按上方说明开启 **更改执行策略**（设置 → 系统 → 高级 → 终端 → PowerShell）
2. 右键"开始"→ **Windows 终端(管理员)** 或 PowerShell(管理员)
3. 运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tweakbyjie.ps1
```

4. 输入选项编号（0-11）并回车

---

## ⚠️ 警告

- **选项 2 的启动安全子项**包含高风险 BCDEdit 设置（`nx AlwaysOff`、关闭驱动完整性检查、TPM Boot Entropy），会显著降低系统安全性；**选项 10** 会修改 VBS/Hyper-V 状态
- **选项 10** 关闭虚拟化后，WSL2 / Docker Desktop / Windows 沙盒 / 部分安卓模拟器可能不可用；需要这些功能时运行**选项 10 → 2** 恢复
- **选项 5** 会完全禁用 Windows Defender 实时保护与 SmartScreen，执行后系统将失去内置防病毒防护，请自行安装第三方安全软件或确认风险
- 删除类优化（选项 5 的 Y 分支）会移除安全中心界面和 Defender 服务，恢复需要重建相关组件
- **选项 9** 是关闭 Device Guard 的"硬手段"（清除 EFI 变量）。已内置 BitLocker 预检查（保护开启即拒绝执行），但重启开机时会出现确认界面，**需按屏幕提示手动按键（通常 F3）确认**，否则本次不生效；错过可重跑
- **选项 11** 使用的是未公开的社区 MPO 排障配置，微软和显卡厂商不保证这些值在所有 Windows 版本/驱动中有效；方案 A/B 可能影响窗口化 VRR、视频呈现、DWM 负载或部分叠加层，方案 B 还可能影响个别 DX12 游戏；方案 C 通常比禁用 MPO 保守，但不保证有效或完全没有副作用
- **选项 11** 首次修改前会在脚本目录创建 `mpo-backup.json`，选项 11 → 4 优先恢复首次修改前状态；请勿手动编辑或删除备份文件，删除后只能清除覆盖值恢复系统默认。脚本模块结束只提示待重启，退出主菜单时统一询问，不再使用 5 秒强制倒计时。
- MPO 设置应每次只测试一个方案，重启后分别检查浏览器/视频、G-Sync/FreeSync、多显示器、窗口化游戏、DX12、HDR、录屏和 Steam/Discord 等覆盖层
- **仅供了解风险的用户在个人设备上使用**；请勿在生产环境或受管理的公司设备上运行
- 运行选项 1→3、2、5、8、9、10、11 前，请确认已有可用的系统/启动恢复方案；脚本只对 CPU 缓解、BCD、MPO、NVMe SafeBoot 和部分服务保存快照，不能承诺所有修改精确回滚。

---

## defender-removal.ps1 — Defender 物理移除（高级 / 不可逆）

### 作用

对 Windows Defender 执行**物理移除**（非禁用）。与 `tweakbyjie.ps1` 选项 5 的"禁用"不同，本脚本直接删除 Defender 的服务注册表键、应用/COM/Shell 注册和实体文件目录，Defender 将从系统中消失。

| 部分 | 操作 |
|---|---|
| **Part 1** | 删除 17+ 个 Defender 服务的注册表键整键（MsSecCore、wscsvc、WdNisDrv/Svc、WdFilter、WdBoot、SgrmAgent/Broker、WinDefend、MsSecFlt/Wfp、whesvc、webthreatdefsvc/usersvc、Pluton 相关、Hsp 等）+ WebThreatDefense 的 WinRT/Svchost 注册 |
| **Part 2** | 删除 13 个 Defender CLSID + 1 个 WebThreatDefense CLSID（CLSID 与 WOW6432Node 两处）、Defender 日志器（Autologger）、AppUserModelId、Shell 关联（windowsdefender / WindowsDefender / AppX / ms-cxh / MrtCache）、WebThreatDefense ActivatableClassId、Ubpm 关键维护任务值、防火墙受限服务值、WTDS 策略键 |
| **Part 3** | takeown + icacls 授权后删除 4 个 Defender 文件目录：`ProgramData\Microsoft\Windows Defender`、`Program Files\Windows Defender`、`Program Files (x86)\Windows Defender`、`Program Files\Windows Defender Advanced Threat Protection` |

### 权限处理

受 TrustedInstaller 保护的键，脚本会先以**管理员**身份尝试删除，失败后收集起来以 **SYSTEM** 身份通过计划任务**批量重试**；仍被拒绝的键会如实报告 `[FAIL]`，如需彻底删除可借助 NSudo / PowerRun 等提权工具。文件删除使用 `takeown` + `icacls` 授予管理员权限后删除。

### 使用方法

```powershell
# 建议先运行主脚本选项 5（禁用），再运行本脚本（移除）
powershell -ExecutionPolicy Bypass -File .\defender-removal.ps1
# 输入 REMOVE 并回车确认（防止误操作）
```

### ⚠️ 不可逆警告

- 删除后**无法**通过改回注册表值恢复，需**重装 Windows** 或运行 `DISM /Online /Cleanup-Image /RestoreHealth` / `sfc /scannow` 修复
- Windows 安全中心页面将报错或无法打开，Windows 更新可能受影响
- **强烈建议运行前创建系统还原点 / 完整备份**
- 仅供了解风险的用户在个人设备上使用

---

## 恢复方法

- **tweakbyjie.ps1 选项 1 → 3**：CPU 缓解子项按 `security-mitigation-backup.json` 恢复两个 FeatureSettings 值；没有有效快照时拒绝声称已恢复
- **tweakbyjie.ps1 选项 2**：高级 BCD 项可用 `bcdedit /deletevalue <名称>` 删除（如 `bcdedit /set nx OptIn`、`bcdedit /deletevalue testsigning`）；注册表项可将对应值改回 `0` 或删除；**虚拟化部分（hypervisorlaunchtype / vsmlaunchtype / isolatedcontext + Device Guard 注册表 + Hyper-V 功能）可用选项 10 管理，但恢复不是原始状态精确回滚**
- **tweakbyjie.ps1 选项 5**：策略禁用和删除类分支没有统一的自动原始状态回滚；需手动删除禁用策略、恢复服务/计划任务并检查 SecHealthUI。
- **tweakbyjie.ps1 选项 6**：子选项 2 按 `service-backup.json` 恢复目标服务原始启动类型，原本不存在的服务跳过，运行状态不强制恢复
- **tweakbyjie.ps1 选项 9**：子选项 2 可删除一次性引导项并卸载 EFI 盘符；EFI 变量清除后如需恢复 Device Guard，可在 Windows 安全中心 → 内核隔离 中重新开启内存完整性（需硬件支持）
- **tweakbyjie.ps1 选项 11 的 MPO 部分**（`DisableMPO` / `OverlayTestMode`）会在首次修改前保存四个受管理值；可用选项 11 → 4 恢复首次修改前状态。若没有 `mpo-backup.json`，选项 11 → 4 只能删除四个覆盖值并恢复系统默认；如需换用其他方案，用选项 11 → 2 / 11 → 3 切换
- **defender-removal.ps1**：不可逆。需重装 Windows 或运行 `DISM /Online /Cleanup-Image /RestoreHealth` + `sfc /scannow` 修复系统组件

---

## 免责声明

本脚本按"原样"提供，仅供学习与个人使用。使用者需自行承担因使用本脚本造成的任何后果。

## 许可证

[MIT](./LICENSE)

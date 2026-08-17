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
| `tweakbyjie.ps1` | 主优化脚本（菜单版） | ✅ 可逆（注册表值/服务启动类型可恢复） |
| `defender-removal.ps1` | Defender 物理移除（高级） | ❌ 不可逆（删键/删文件，需重装系统恢复） |
| `ultimate-performance.pow` | 超性能电源计划文件（配合选项 6 使用） | ✅ 可逆（选项 6 → 2 恢复备份） |

> 想了解每个脚本具体修改了哪些注册表、BCDEdit 启动项和服务？详见 **[优化详情参考 (OPTIMIZATION-DETAILS.md)](./OPTIMIZATION-DETAILS.md)**。

---

## tweakbyjie.ps1 — 功能菜单

| 选项 | 功能 | 说明 |
|---|---|---|
| **1** | 系统优化 | GameDVR、VBS/HVCI/Credential Guard 关闭（含组策略层）、多媒体调度（NetworkThrottlingIndex/SystemResponsiveness）、CPU 优先级分离、Meltdown/Spectre 缓解关闭、HAGS、MPO 关闭、Games 任务调度、Prefetch 关闭、DWM、NTFS 8.3、游戏模式、内存压缩、BITS→手动、TRIM、BCDEdit 优化（hypervisor/时钟节拍/NX/完整性检查等）、**Hyper-V 功能组件禁用（DISM，检测到已启用才执行；不影响 WSL2/Docker 依赖的功能）**、视觉效果自定义（仅保留平滑屏幕字体边缘与任务栏动画，其余动画/阴影/缩略图全关；辅助功能视觉效果四项：滚动条/透明/动画关、通知 5 秒） |
| **2** | 开启测试模式 | `bcdedit` testsigning / debug / dbgsettings local / nointegritychecks，桌面右下角出现"测试模式"水印属正常 |
| **3** | 关闭测试模式 | 删除 testsigning / debug 启动项（保留 nointegritychecks），水印消失 |
| **4** | 关闭安全中心 | 写入 Windows Defender 策略注册表（父键 / Real-Time Protection / Spynet / Signature Updates / Scan / MpEngine / NIS / Exploit Guard / 通知抑制等）+ SmartScreen 全套关闭（系统级 / Explorer / Edge / Store 应用）。执行后可选择是否进行**删除类优化**（输入 `Y` 执行 / `N` 跳过）：停止并禁用 17 个 Defender 相关服务、删除 Defender 计划任务、删除 SecurityHealth 自启动项、移除安全中心界面 SecHealthUI |
| **5** | 优化服务项继续工作 | 停止并禁用 29 个可安全禁用的服务（诊断四件套 DPS/WdiServiceHost/WdiSystemHost/diagsvc、DialogBlockingService、TrkWks、AppVClient、键盘筛选器、NetTcpPortSharing、脱机文件、ssh-agent、PhoneSvc、兼容性助手 PCA、远程注册表、路由远程访问、传感器×2、共享电脑、UE-V、钱包、预览体验、WSAIFabricSvc、WAP 推送、数据使用量、自动时区、打印后台处理、Windows 搜索、SysMain、Edge 更新×2）+ 将 7 个服务改成**手动**（Xbox 配件管理、Xbox Live 身份验证/网络服务/游戏保存、蓝牙支持、嵌入模式、BITS） |
| **6** | 应用超性能电源计划 | 子选项 1：先将当前正在使用的电源计划备份到脚本所在目录（`power-backup.pow`，已存在则不覆盖），再导入并应用仓库自带的 `ultimate-performance.pow`（CPU 全程满频、全链路不节电）；子选项 2：恢复之前备份的电源计划 |
| **7** | 启用原生 NVMe 驱动 | 子选项 0：只读检查当前状态（覆盖值/加固/驱动文件/加载状态并给出结论）；子选项 1：写入 3 个 Velocity 功能覆盖值，提前启用微软原生 NVMe 磁盘驱动 `nvmedisk.sys`（替换 NVMe 盘的通用 `disk.sys`），并写入 2 条安全模式加固项（防止启用后进不去安全模式），重启后生效；子选项 2：删除覆盖值还原。需 25H2（build 26200+）与 NVMe 硬盘（实测 24H2 十月更新批次无法启用） |
| **8** | 清除 Device Guard EFI 锁定 | 应对 UEFI 锁定场景（选项 1 已关注册表，但安全中心/msinfo32 仍显示"内存完整性/凭据保护"开启）。子选项 1：先做 **BitLocker 预检查**（检测到任一分区保护已开启则拒绝执行，避免清除 EFI 变量触发 BitLocker 恢复模式），再挂载 EFI 分区复制 `SecConfig.efi` 并配置**一次性引导项**，重启开机时会出现确认界面，需按屏幕提示按键（通常 F3）确认禁用；子选项 2：删除引导项、清空引导序列、卸载 EFI 盘符（不重启） |
| **9** | 虚拟化还原 / Hyper-V 启用 | 与选项 1 互为还原。子选项 0：只读查看虚拟化状态（bcdedit 引导项 / Device Guard 注册表 / Hyper-V 及 WSL2 相关功能状态）；子选项 1：删除 `hypervisorlaunchtype` / `vsmlaunchtype` / `isolatedcontext` 引导项 + 删除 Device Guard 注册表关闭值，恢复系统默认；子选项 2：在 1 的基础上启用 Hyper-V 功能（`Microsoft-Hyper-V-All`，**家庭版同样适用**——家庭版没有控制面板入口，DISM 方式启用等价于勾选 Hyper-V）。适用于选项 1 之后想恢复 WSL2 / Docker / Windows 沙盒 / 安卓模拟器，或重新开启内核隔离的场景 |
| **10** | MPO 设置管理 | 管理四个 MPO（多平面叠加）相关注册表值，**三方案互斥，切换时自动清除其他方案的值**。子选项 0：只读查看状态 + dxdiag 验证方法；子选项 1：**方案 A** 禁用 MPO（`OverlayTestMode=5` + `DisableMPO=1`，与选项 1 写入相同，最常用、兼容性好）；子选项 2：**方案 B** 禁用 MPO（`DisableOverlays=1`，驱动层更彻底的最后手段，**个别 DX12 游戏可能异常**）；子选项 3：**方案 C** 不禁用 MPO（`OverlayMinFPS=0`，保持硬件合成常开，解决 G-Sync/FreeSync 下视频播放全屏卡顿，无兼容性问题）；子选项 4：删除全部四个值还原系统默认。验证：`dxdiag` → 保存所有信息 → 搜索 MPO，MaxPlanes 消失/为 0 即已禁用 |

每个选项执行完成后 **5 秒自动重启**（期间按 `Q` 取消）。

---

## tweakbyjie.ps1 — 使用方法

1. 按上方说明开启 **更改执行策略**（设置 → 系统 → 高级 → 终端 → PowerShell）
2. 右键"开始"→ **Windows 终端(管理员)** 或 PowerShell(管理员)
3. 运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tweakbyjie.ps1
```

4. 输入选项编号（1、2、3、4、5、6、7、8、9 或 10）并回车

---

## ⚠️ 警告

- **选项 1** 包含高风险 BCDEdit 设置（`nx AlwaysOff`、关闭驱动完整性检查、关闭 VBS），会显著降低系统安全性
- **选项 1** 关闭虚拟化后，WSL2 / Docker Desktop / Windows 沙盒 / 部分安卓模拟器将不可用；需要这些功能时运行**选项 9** 还原
- **选项 4** 会完全禁用 Windows Defender 实时保护与 SmartScreen，执行后系统将失去内置防病毒防护，请自行安装第三方安全软件或确认风险
- 删除类优化（选项 4 的 Y 分支）会移除安全中心界面和 Defender 服务，恢复需要重建相关组件
- **选项 8** 是关闭 Device Guard 的"硬手段"（清除 EFI 变量）。已内置 BitLocker 预检查（保护开启即拒绝执行），但重启开机时会出现确认界面，**需按屏幕提示手动按键（通常 F3）确认**，否则本次不生效；错过可重跑
- **选项 10 方案 B（DisableOverlays）** 会整体关闭驱动层叠加平面，个别 DX12 游戏可能出现异常，属于方案 A 无效时的最后手段；如遇问题用 10 → 4 一键还原
- **仅供了解风险的用户在个人设备上使用**；请勿在生产环境或受管理的公司设备上运行
- 建议运行前创建系统还原点

---

## defender-removal.ps1 — Defender 物理移除（高级 / 不可逆）

### 作用

对 Windows Defender 执行**物理移除**（非禁用）。与 `tweakbyjie.ps1` 选项 4 的"禁用"不同，本脚本直接删除 Defender 的服务注册表键、应用/COM/Shell 注册和实体文件目录，Defender 将从系统中消失。

| 部分 | 操作 |
|---|---|
| **Part 1** | 删除 17+ 个 Defender 服务的注册表键整键（MsSecCore、wscsvc、WdNisDrv/Svc、WdFilter、WdBoot、SgrmAgent/Broker、WinDefend、MsSecFlt/Wfp、whesvc、webthreatdefsvc/usersvc、Pluton 相关、Hsp 等）+ WebThreatDefense 的 WinRT/Svchost 注册 |
| **Part 2** | 删除 13 个 Defender CLSID + 1 个 WebThreatDefense CLSID（CLSID 与 WOW6432Node 两处）、Defender 日志器（Autologger）、AppUserModelId、Shell 关联（windowsdefender / WindowsDefender / AppX / ms-cxh / MrtCache）、WebThreatDefense ActivatableClassId、Ubpm 关键维护任务值、防火墙受限服务值、WTDS 策略键 |
| **Part 3** | takeown + icacls 授权后删除 4 个 Defender 文件目录：`ProgramData\Microsoft\Windows Defender`、`Program Files\Windows Defender`、`Program Files (x86)\Windows Defender`、`Program Files\Windows Defender Advanced Threat Protection` |

### 权限处理

受 TrustedInstaller 保护的键，脚本会先以**管理员**身份尝试删除，失败后收集起来以 **SYSTEM** 身份通过计划任务**批量重试**；仍被拒绝的键会如实报告 `[FAIL]`，如需彻底删除可借助 NSudo / PowerRun 等提权工具。文件删除使用 `takeown` + `icacls` 授予管理员权限后删除。

### 使用方法

```powershell
# 建议先运行主脚本选项 4（禁用），再运行本脚本（移除）
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

- **tweakbyjie.ps1 选项 1 优化**：BCDEdit 项可用 `bcdedit /deletevalue <名称>` 删除（如 `bcdedit /set nx OptIn`、`bcdedit /deletevalue testsigning`）；注册表项可将对应值改回 `0` 或删除；**虚拟化部分（hypervisorlaunchtype / vsmlaunchtype / isolatedcontext + Device Guard 注册表 + Hyper-V 功能）可直接用选项 9 一键还原**
- **tweakbyjie.ps1 选项 4**：删除 `HKLM\SOFTWARE\Policies\Microsoft\Windows Defender` 下的禁用值，将服务启动类型恢复为 `Manual`/`Automatic`，在 Windows 安全中心中重新开启实时保护；被移除的 SecHealthUI 可通过 `Get-AppxPackage -AllUsers Microsoft.SecHealthUI` 检查并重装应用
- **tweakbyjie.ps1 选项 8**：子选项 2 可删除一次性引导项并卸载 EFI 盘符；EFI 变量清除后如需恢复 Device Guard，可在 Windows 安全中心 → 内核隔离 中重新开启内存完整性（需硬件支持）
- **tweakbyjie.ps1 选项 1 的 MPO 部分**（`DisableMPO` / `OverlayTestMode`）**可直接用选项 10 → 4 一键还原**（删除全部 MPO 相关值，恢复系统默认）；如需换用其他方案（如 `DisableOverlays` 或 `OverlayMinFPS`），用选项 10 → 2 / 10 → 3 切换
- **defender-removal.ps1**：不可逆。需重装 Windows 或运行 `DISM /Online /Cleanup-Image /RestoreHealth` + `sfc /scannow` 修复系统组件

---

## 免责声明

本脚本按"原样"提供，仅供学习与个人使用。使用者需自行承担因使用本脚本造成的任何后果。

## 许可证

[MIT](./LICENSE)

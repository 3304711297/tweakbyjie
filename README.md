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

| 脚本 | 作用 | 可逆性 |
|---|---|---|
| `tweakbyjie.ps1` | 主优化脚本（菜单版） | ✅ 可逆（注册表值/服务启动类型可恢复） |
| `defender-removal.ps1` | Defender 物理移除（高级） | ❌ 不可逆（删键/删文件，需重装系统恢复） |

---

## tweakbyjie.ps1 — 功能菜单

| 选项 | 功能 | 说明 |
|---|---|---|
| **1** | 系统优化 | GameDVR、VBS/HVCI、多媒体调度（NetworkThrottlingIndex/SystemResponsiveness）、CPU 优先级分离、Meltdown/Spectre 缓解关闭、HAGS、MPO 关闭、Games 任务调度、Prefetch 关闭、DWM、NTFS 8.3、游戏模式、内存压缩、BITS→手动、TRIM、BCDEdit 优化（hypervisor/时钟节拍/NX/完整性检查等） |
| **2** | 开启测试模式 | `bcdedit` testsigning / debug / dbgsettings local / nointegritychecks，桌面右下角出现"测试模式"水印属正常 |
| **3** | 关闭测试模式 | 删除 testsigning / debug 启动项（保留 nointegritychecks），水印消失 |
| **4** | 关闭安全中心 | 写入 Windows Defender 策略注册表（父键 / Real-Time Protection / Spynet / Signature Updates / Scan / MpEngine / NIS / Exploit Guard / 通知抑制等）+ SmartScreen 全套关闭（系统级 / Explorer / Edge / Store 应用）。执行后可选择是否进行**删除类优化**（输入 `Y` 执行 / `N` 跳过）：停止并禁用 17 个 Defender 相关服务、删除 Defender 计划任务、删除 SecurityHealth 自启动项、移除安全中心界面 SecHealthUI |

每个选项执行完成后 **5 秒自动重启**（期间按 `Q` 取消）。

---

## tweakbyjie.ps1 — 使用方法

1. 按上方说明开启 **更改执行策略**（设置 → 系统 → 高级 → 终端 → PowerShell）
2. 右键"开始"→ **Windows 终端(管理员)** 或 PowerShell(管理员)
3. 运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tweakbyjie.ps1
```

4. 输入选项编号（1/2/3/4）并回车

---

## ⚠️ 警告

- **选项 1** 包含高风险 BCDEdit 设置（`nx AlwaysOff`、关闭驱动完整性检查、关闭 VBS），会显著降低系统安全性
- **选项 4** 会完全禁用 Windows Defender 实时保护与 SmartScreen，执行后系统将失去内置防病毒防护，请自行安装第三方安全软件或确认风险
- 删除类优化（选项 4 的 Y 分支）会移除安全中心界面和 Defender 服务，恢复需要重建相关组件
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

- **tweakbyjie.ps1 选项 1 优化**：BCDEdit 项可用 `bcdedit /deletevalue <名称>` 删除（如 `bcdedit /set nx OptIn`、`bcdedit /deletevalue testsigning`）；注册表项可将对应值改回 `0` 或删除
- **tweakbyjie.ps1 选项 4**：删除 `HKLM\SOFTWARE\Policies\Microsoft\Windows Defender` 下的禁用值，将服务启动类型恢复为 `Manual`/`Automatic`，在 Windows 安全中心中重新开启实时保护；被移除的 SecHealthUI 可通过 `Get-AppxPackage -AllUsers Microsoft.SecHealthUI` 检查并重装应用
- **defender-removal.ps1**：不可逆。需重装 Windows 或运行 `DISM /Online /Cleanup-Image /RestoreHealth` + `sfc /scannow` 修复系统组件

---

## 免责声明

本脚本按"原样"提供，仅供学习与个人使用。使用者需自行承担因使用本脚本造成的任何后果。

## 许可证

[MIT](./LICENSE)

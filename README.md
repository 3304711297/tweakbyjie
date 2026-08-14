# tweakbyjie

Windows 游戏优化脚本（菜单版）— 系统优化 / 测试模式开关 / 关闭安全中心，一键完成。

A menu-driven Windows optimization script: system tweaks, test-mode toggles, and Security Center disabling, all in one.

---

## 功能菜单 / Menu

| 选项 | 功能 | 说明 |
|---|---|---|
| **1** | 系统优化 | GameDVR、VBS/HVCI、多媒体调度（NetworkThrottlingIndex/SystemResponsiveness）、CPU 优先级分离、Meltdown/Spectre 缓解关闭、HAGS、MPO 关闭、Games 任务调度、Prefetch 关闭、DWM、NTFS 8.3、游戏模式、内存压缩、BITS→手动、TRIM、BCDEdit 优化（hypervisor/时钟节拍/NX/完整性检查等） |
| **2** | 开启测试模式 | `bcdedit` testsigning / debug / dbgsettings local / nointegritychecks，桌面右下角出现"测试模式"水印属正常 |
| **3** | 关闭测试模式 | 删除 testsigning / debug 启动项（保留 nointegritychecks），水印消失 |
| **4** | 关闭安全中心 | 写入 Windows Defender 策略注册表（父键 / Real-Time Protection / Spynet / Signature Updates / Scan / MpEngine / NIS / Exploit Guard / 通知抑制等）+ SmartScreen 全套关闭（系统级 / Explorer / Edge / Store 应用）。执行后可选择是否进行**删除类优化**（输入 `Y` 执行 / `N` 跳过）：停止并禁用 17 个 Defender 相关服务、删除 Defender 计划任务、删除 SecurityHealth 自启动项、移除安全中心界面 SecHealthUI |

每个选项执行完成后 **5 秒自动重启**（期间按 `Q` 取消）。
Each option auto-restarts after 5 seconds (press `Q` to cancel).

---

## 使用方法 / Usage

1. 右键"开始"→ **Windows 终端(管理员)** 或 PowerShell(管理员)
2. 运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tweakbyjie.ps1
```

3. 输入选项编号（1/2/3/4）并回车

---

## ⚠️ 警告 / Warnings

- **选项 1** 包含高风险 BCDEdit 设置（`nx AlwaysOff`、关闭驱动完整性检查、关闭 VBS），会显著降低系统安全性
- **选项 4** 会完全禁用 Windows Defender 实时保护与 SmartScreen，执行后系统将失去内置防病毒防护，请自行安装第三方安全软件或确认风险
- 删除类优化（选项 4 的 Y 分支）会移除安全中心界面和 Defender 服务，恢复需要重建相关组件
- **仅供了解风险的用户在个人设备上使用**；请勿在生产环境或受管理的公司设备上运行
- 建议运行前创建系统还原点

---

## 恢复方法 / How to restore

- **选项 1 优化**：BCDEdit 项可用 `bcdedit /deletevalue <名称>` 删除（如 `bcdedit /set nx OptIn`、`bcdedit /deletevalue testsigning`）；注册表项可将对应值改回 `0` 或删除
- **选项 4**：删除 `HKLM\SOFTWARE\Policies\Microsoft\Windows Defender` 下的禁用值，将服务启动类型恢复为 `Manual`/`Automatic`，在 Windows 安全中心中重新开启实时保护；被移除的 SecHealthUI 可通过 `Get-AppxPackage -AllUsers Microsoft.SecHealthUI` 检查并重装应用

---

## 免责声明 / Disclaimer

本脚本按"原样"提供，仅供学习与个人使用。使用者需自行承担因使用本脚本造成的任何后果。
This script is provided "AS IS", for educational and personal use only. Use at your own risk.

## License

[MIT](./LICENSE)

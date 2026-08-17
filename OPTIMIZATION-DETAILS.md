# 优化详情参考

> 本文档列出 `tweakbyjie.ps1` 和 `defender-removal.ps1` 的每一项优化操作，
> 包括注册表路径、值名、类型、写入值以及 BCDEdit 命令、服务操作、文件删除等。
> 仅供想了解具体优化内容的用户参考。

---

## 一、tweakbyjie.ps1

---

### Part 1：系统优化（选项 1）

#### 01 GameDVR 关闭

| 注册表路径 | 值名 | 类型 | 值 | 作用 |
|---|---|---|---|---|
| `HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR` | AppCaptureEnabled | DWORD | 0 | 关闭 GameDVR 游戏录制 |
| `HKCU:\System\GameConfigStore` | GameDVR_Enabled | DWORD | 0 | 关闭 GameDVR 配置 |

#### 02 GameBar 后台写入

通过 `reg.exe` 写入受保护键，管理员失败时自动以 SYSTEM 身份通过计划任务重试。

| 注册表路径 | 值名 | 类型 | 值 | 作用 |
|---|---|---|---|---|
| `HKLM:\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Windows.Gaming.Gamebar.PresenceServer.Internal.PresenceWriter` | ActivationType | DWORD | 0 | 禁止 GameBar 后台 Presence 写入 |

#### 03 GameBar Nexus

| 注册表路径 | 值名 | 类型 | 值 | 作用 |
|---|---|---|---|---|
| `HKCU:\Software\Microsoft\GameBar` | UseNexusForGameBarEnabled | DWORD | 0 | 关闭 GameBar Nexus |

#### 04 VBS / HVCI / Credential Guard 关闭（Device Guard）

| 注册表路径 | 值名 | 类型 | 值 | 作用 |
|---|---|---|---|---|
| `HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity` | Enabled | DWORD | 0 | 关闭 HVCI（基于虚拟化的代码完整性，即"内核隔离-内存完整性"） |
| `HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard` | EnableVirtualizationBasedSecurity | DWORD | 0 | 关闭 VBS（基于虚拟化的安全） |
| `HKLM:\SYSTEM\CurrentControlSet\Control\LSA` | LsaCfgFlags | DWORD | 0 | 关闭 Credential Guard（凭据保护） |
| `HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard` | EnableVirtualizationBasedSecurity | DWORD | 0 | 组策略层关闭 VBS（优先级高于 Control\DeviceGuard，防止组策略下发导致设置被无视） |
| `HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard` | RequirePlatformSecurityFeatures | DWORD | 0 | 组策略层清除 VBS 平台安全特性要求 |

> 这三项与上面两项需**同时**置 0（保持配置一致），只改一半可能造成状态不一致。若注册表全部关闭后安全中心/msinfo32 仍显示开启，属于 UEFI 锁定，需用选项 8 的 SecConfig.efi 方法清除 EFI 变量。

#### 05 多媒体调度

| 注册表路径 | 值名 | 类型 | 值 | 作用 |
|---|---|---|---|---|
| `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile` | NetworkThrottlingIndex | DWORD | 0xFFFFFFFF | 禁用网络节流（游戏时不停降低网络优先级） |
| `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile` | SystemResponsiveness | DWORD | 10 | 降低系统后台响应权重（10%，默认 20%） |

#### 06 CPU 优先级分离

| 注册表路径 | 值名 | 类型 | 值 | 作用 |
|---|---|---|---|---|
| `HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl` | Win32PrioritySeparation | DWORD | 38 (0x26) | 前台程序获得更高 CPU 优先级 |

#### 07 搜索（Bing / Cortana）

| 注册表路径 | 值名 | 类型 | 值 | 作用 |
|---|---|---|---|---|
| `HKCU:\Software\Microsoft\Windows\CurrentVersion\Search` | BingSearchEnabled | DWORD | 0 | 关闭 Bing 网络搜索 |
| `HKCU:\Software\Microsoft\Windows\CurrentVersion\Search` | AllowSearchToUseLocation | DWORD | 0 | 禁止搜索使用位置信息 |
| `HKCU:\Software\Microsoft\Windows\CurrentVersion\Search` | CortanaConsent | DWORD | 0 | 关闭 Cortana |

#### 08 Meltdown / Spectre 缓解关闭

| 注册表路径 | 值名 | 类型 | 值 | 作用 |
|---|---|---|---|---|
| `HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management` | FeatureSettingsOverride | DWORD | 3 | 关闭 Meltdown/Spectre 缓解措施 |
| `HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management` | FeatureSettingsOverrideMask | DWORD | 3 | 关闭缓解措施掩码 |

#### 09 HAGS（硬件加速 GPU 调度）

| 注册表路径 | 值名 | 类型 | 值 | 作用 |
|---|---|---|---|---|
| `HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers` | HwSchMode | DWORD | 2 | 开启 HAGS |

#### 10 MPO 关闭

| 注册表路径 | 值名 | 类型 | 值 | 作用 |
|---|---|---|---|---|
| `HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers` | DisableMPO | DWORD | 1 | 关闭多平面叠加（MPO），减少部分游戏的卡顿 |

> 更彻底的禁用方案（`DisableOverlays`）、G-Sync/FreeSync 视频卡顿修复（`OverlayMinFPS`）与一键还原见 **Part 10（选项 10）**。

#### 11 Games 任务调度

| 注册表路径 | 值名 | 类型 | 值 | 作用 |
|---|---|---|---|---|
| `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games` | Affinity | DWORD | 0 | 不限制 CPU 核心 |
| `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games` | Background Only | String | False | 允许前台运行 |
| `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games` | Clock Rate | DWORD | 10000 | GPU 时钟率最高 |
| `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games` | GPU Priority | DWORD | 8 | GPU 优先级最高 |
| `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games` | Priority | DWORD | 6 | 进程优先级高 |
| `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games` | Scheduling Category | String | High | 调度类别高 |
| `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games` | SFIO Priority | String | High | I/O 优先级高 |

#### 12 Prefetch 关闭

| 注册表路径 | 值名 | 类型 | 值 | 作用 |
|---|---|---|---|---|
| `HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters` | EnablePrefetcher | DWORD | 0 | 关闭预读取 |

#### 13 DWM

| 注册表路径 | 值名 | 类型 | 值 | 作用 |
|---|---|---|---|---|
| `HKLM:\SOFTWARE\Microsoft\Windows\Dwm` | OverlayTestMode | DWORD | 5 | DWM 层禁用 MPO（叠加测试模式） |

> 独立管理/还原见 **Part 10（选项 10）**。

#### 14 NTFS 8.3 短文件名

| 注册表路径 | 值名 | 类型 | 值 | 作用 |
|---|---|---|---|---|
| `HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem` | NtfsDisable8dot3NameCreation | DWORD | 1 | 禁止创建 8.3 短文件名，减少磁盘开销 |

#### 15 游戏模式关闭

| 注册表路径 | 值名 | 类型 | 值 | 作用 |
|---|---|---|---|---|
| `HKCU:\Software\Microsoft\GameBar` | AutoGameModeEnabled | DWORD | 0 | 关闭自动游戏模式 |
| `HKCU:\Software\Microsoft\GameBar` | AllowAutoGameMode | DWORD | 0 | 禁止自动切换游戏模式 |

#### 16 内存压缩

| 操作 | 命令 | 作用 |
|---|---|---|
| 系统命令 | `Disable-MMAgent -mc` | 关闭内存压缩（减少 CPU 和内存开销） |

#### 17 TRIM

| 操作 | 命令 | 作用 |
|---|---|---|
| 系统命令 | `fsutil behavior set DisableDeleteNotify 0` | 确保 SSD TRIM 已启用 |

#### 18 BCDEdit 优化

> 选项 1 完成后会回读部分关键注册表和 BCD 值，并报告 `[VERIFY OK]` 或 `[VERIFY FAIL]`。这只验证当前配置是否写入，不代表重启后的全部运行时效果；若关键验证失败，脚本会跳过自动重启。

| 命令 | 作用 | 风险等级 |
|---|---|---|
| `bcdedit /set hypervisorlaunchtype off` | 关闭 Hyper-V / VBS 虚拟机监控器 | 低 |
| `bcdedit /set isolatedcontext no` | 关闭隔离上下文 | 低 |
| `bcdedit /set vsmlaunchtype off` | 关闭 VSM（虚拟安全模式）启动 | 低 |
| `bcdedit /set useplatformclock no` | 关闭 HPET 平台时钟 | 低 |
| `bcdedit /set useplatformtick no` | 关闭平台计时器 | 低 |
| `bcdedit /set disabledynamictick yes` | 禁用动态时钟节拍 | 低 |
| `bcdedit /set tscsyncpolicy Enhanced` | TSC 同步策略设为 Enhanced | 低 |
| `bcdedit /set nx AlwaysOff` | 永久关闭 DEP（数据执行保护） | ⚠️ 高 |
| `bcdedit /set tpmbootentropy ForceDisable` | 禁用 TPM 启动熵 | ⚠️ 中 |
| `bcdedit /set nointegritychecks on` | 关闭驱动程序完整性检查 | ⚠️ 高 |
| `Disable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart`（检测到已启用才执行，未启用跳过） | 禁用 Hyper-V 功能本体（卸载虚拟机管理栈 vmms / vmcompute / HvHost 等），等效于控制面板"启用或关闭 Windows 功能"取消勾选 Hyper-V，或 `DISM /Online /Disable-Feature /FeatureName:Microsoft-Hyper-V-All`。**不影响** WSL2 / Docker 依赖的 VirtualMachinePlatform / HypervisorPlatform | 低 |

> Hyper-V 关闭的三个层次：① `hypervisorlaunchtype off` 阻止虚拟机监控器启动（bcdedit 层）；② 本表 DISM 行卸载功能本体（可选功能层）；③ 注册表关闭 VBS/HVCI/Credential Guard（见 04 节）。三层全部执行才彻底；如需还原，运行**选项 9**。

#### 19 视觉效果自定义

对应「系统属性 → 高级 → 性能设置 → 视觉效果 → 自定义」：仅开启**平滑屏幕字体边缘**与**任务栏中的动画**，其余项全部关闭；
另含「设置 → 辅助功能 → 视觉效果」四项：始终显示滚动条关 / 透明效果关 / 动画效果关 / 在此时间后关闭通知 5 秒。

| 注册表路径 | 值名 | 类型 | 值 | 对应设置项 | 状态 |
|---|---|---|---|---|---|
| `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects` | VisualFXSetting | DWORD | 3 | 视觉效果模式 | 自定义 |
| `HKCU:\Control Panel\Desktop` | FontSmoothing | SZ | 2 | 平滑屏幕字体边缘 | ✅ 开 |
| `HKCU:\Control Panel\Desktop` | FontSmoothingType | DWORD | 2 | 字体平滑类型（ClearType） | ✅ 开 |
| `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | TaskbarAnimations | DWORD | 1 | 任务栏中的动画 | ✅ 开 |
| `HKCU:\Control Panel\Desktop` | UserPreferencesMask | BINARY | `90,12,01,80,10,00,00,00` | 菜单/组合框/列表框/工具提示动画、单击后淡出菜单、指针阴影、窗口下阴影 | ❌ 关 |
| `HKCU:\Control Panel\Desktop\WindowMetrics` | MinAnimate | SZ | 0 | 在最大化/最小化时显示窗口动画 | ❌ 关 |
| `HKCU:\Control Panel\Desktop` | DragFullWindows | SZ | 0 | 拖动时显示窗口内容 | ❌ 关 |
| `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | ListviewAlphaSelect | DWORD | 0 | 显示亚透明的选择长方形 | ❌ 关 |
| `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | ListviewShadow | DWORD | 0 | 在桌面上为图标标签使用阴影 | ❌ 关 |
| `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | IconsOnly | DWORD | 1 | 显示缩略图而不是图标（1=只显示图标） | ❌ 关 |
| `HKCU:\Software\Microsoft\Windows\DWM` | AlwaysHibernateThumbnails | DWORD | 0 | 保存任务栏缩略图预览 | ❌ 关 |
| `HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize` | EnableTransparency | DWORD | 0 | 透明效果（想保留透明改回 1） | ❌ 关 |
| `HKCU:\Control Panel\Accessibility` | DynamicScrollbars | DWORD | 1 | 始终显示滚动条（1=自动隐藏=关，0=始终显示） | ❌ 关 |
| `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects` | AnimationEffects | DWORD | 0 | 辅助功能「动画效果」 | ❌ 关 |
| `HKCU:\Control Panel\Accessibility` | MessageDuration | DWORD | 5 | 在此时间后关闭通知（秒） | 5 秒 |

> `UserPreferencesMask` 为「最佳性能」基线掩码（`90,12,01,80,10,00,00,00`）；若想保留「在窗口下显示阴影」，把第 3 字节 `01` 改回 `03` 即可。
> 视觉效果均为 HKCU 当前用户设置，需注销 / 重启（或重启资源管理器）后完全生效。

---

### Part 2：开启测试模式（选项 2）

| 命令 | 作用 |
|---|---|
| `bcdedit /set testsigning on` | 开启测试签名模式（允许加载未签名驱动） |
| `bcdedit /set debug on` | 开启内核调试 |
| `bcdedit /dbgsettings local` | 调试类型设为本地（NT调试） |
| `bcdedit /set nointegritychecks on` | 关闭驱动完整性检查 |

> 开启后桌面右下角显示"测试模式"水印属正常现象。

---

### Part 3：关闭测试模式（选项 3）

| 命令 | 作用 |
|---|---|
| `bcdedit /deletevalue testsigning` | 删除测试签名启动项（水印消失） |
| `bcdedit /deletevalue debug` | 删除调试启动项 |

> 注意：`nointegritychecks` 不会被删除，需手动运行 `bcdedit /set nointegritychecks off` 恢复。

---

### Part 4：关闭安全中心（选项 4）

#### Defender 策略 — 父键

| 注册表路径 | 值名 | 类型 | 值 | 作用 |
|---|---|---|---|---|
| `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender` | DisableAntiSpyware | DWORD | 1 | 禁用反间谍软件 |
| `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender` | DisableAntiVirus | DWORD | 1 | 禁用反病毒 |
| `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender` | DisableRealtimeMonitoring | DWORD | 1 | 禁用实时监控 |
| `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender` | DisableRoutinelyTakingAction | DWORD | 1 | 禁用定期扫描 |
| `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender` | DisableSpecialRunningModes | DWORD | 1 | 禁用特殊运行模式 |
| `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender` | ServiceKeepAlive | DWORD | 0 | 禁止服务自动重启 |
| `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender` | PUAProtection | DWORD | 0 | 关闭 PUAs 检测 |
| `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender` | AllowFastServiceStartup | DWORD | 0 | 禁止服务快速启动 |
| `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender` | DisableLocalAdminMerge | DWORD | 1 | 禁止本地管理员合并策略 |
| `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender` | RandomizeScheduleTaskTimes | DWORD | 0 | 关闭计划任务时间随机化 |

#### Defender 策略 — Real-Time Protection（实时保护）

| 注册表路径 | 值名 | 类型 | 值 | 作用 |
|---|---|---|---|---|
| `...\Windows Defender\Real-Time Protection` | DisableAntivirus | DWORD | 1 | 禁用实时杀毒 |
| `...\Windows Defender\Real-Time Protection` | DisableBehaviorMonitoring | DWORD | 1 | 禁用行为监控 |
| `...\Windows Defender\Real-Time Protection` | DisableOnAccessProtection | DWORD | 1 | 禁用访问保护 |
| `...\Windows Defender\Real-Time Protection` | DisableScanOnRealtimeEnable | DWORD | 1 | 禁用实时扫描 |
| `...\Windows Defender\Real-Time Protection` | DisableRealtimeMonitoring | DWORD | 1 | 禁用实时监控 |
| `...\Windows Defender\Real-Time Protection` | DisableIOAVProtection | DWORD | 1 | 禁用 IE/Office 下载保护 |
| `...\Windows Defender\Real-Time Protection` | DisableScriptScanning | DWORD | 1 | 禁用脚本扫描 |
| `...\Windows Defender\Real-Time Protection` | LocalSettingOverrideDisableOnAccessProtection | DWORD | 0 | 禁止本地覆盖访问保护 |
| `...\Windows Defender\Real-Time Protection` | LocalSettingOverrideRealtimeScanDirection | DWORD | 0 | 禁止本地覆盖扫描方向 |
| `...\Windows Defender\Real-Time Protection` | LocalSettingOverrideDisableIOAVProtection | DWORD | 0 | 禁止本地覆盖 IOAV 保护 |
| `...\Windows Defender\Real-Time Protection` | LocalSettingOverrideDisableBehaviorMonitoring | DWORD | 0 | 禁止本地覆盖行为监控 |
| `...\Windows Defender\Real-Time Protection` | LocalSettingOverrideDisableIntrusionPreventionSystem | DWORD | 0 | 禁止本地覆盖 IPS |
| `...\Windows Defender\Real-Time Protection` | LocalSettingOverrideDisableRealtimeMonitoring | DWORD | 0 | 禁止本地覆盖实时监控 |
| `...\Windows Defender\Real-Time Protection` | RealtimeScanDirection | DWORD | 2 | 扫描方向设为双向 |
| `...\Windows Defender\Real-Time Protection` | DisableInformationProtectionControl | DWORD | 1 | 禁用信息保护控制 |
| `...\Windows Defender\Real-Time Protection` | DisableIntrusionPreventionSystem | DWORD | 1 | 禁用入侵防护系统 |
| `...\Windows Defender\Real-Time Protection` | DisableRawWriteNotification | DWORD | 1 | 禁用原始写入通知 |

> 路径前缀均为 `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender`

#### Defender 策略 — Spynet（云保护）

| 注册表路径 | 值名 | 类型 | 值 | 作用 |
|---|---|---|---|---|
| `...\Windows Defender\Spynet` | DisableBlockAtFirstSeen | DWORD | 1 | 禁用首次发现即拦截 |
| `...\Windows Defender\Spynet` | LocalSettingOverrideSpynetReporting | DWORD | 0 | 禁止本地覆盖云保护报告 |
| `...\Windows Defender\Spynet` | SpynetReporting | DWORD | 0 | 关闭 Microsoft 活动样本上报 |
| `...\Windows Defender\Spynet` | SubmitSamplesConsent | DWORD | 2 | 样本提交设为"始终提示后发送" |

#### Defender 策略 — Signature Updates（签名更新）

| 注册表路径 | 值名 | 类型 | 值 | 作用 |
|---|---|---|---|---|
| `...\Windows Defender\Signature Updates` | SignatureDisableNotification | DWORD | 1 | 禁用签名过期通知 |
| `...\Windows Defender\Signature Updates` | RealtimeSignatureDelivery | DWORD | 0 | 关闭实时签名分发 |
| `...\Windows Defender\Signature Updates` | ForceUpdateFromMU | DWORD | 0 | 关闭强制从 Microsoft Update 更新 |
| `...\Windows Defender\Signature Updates` | DisableScheduledSignatureUpdateOnBattery | DWORD | 1 | 禁止电池供电时更新签名 |
| `...\Windows Defender\Signature Updates` | UpdateOnStartUp | DWORD | 0 | 关闭启动时签名更新 |
| `...\Windows Defender\Signature Updates` | SignatureUpdateCatchupInterval | DWORD | 2 | 签名追补间隔 2 天 |
| `...\Windows Defender\Signature Updates` | DisableUpdateOnStartupWithoutEngine | DWORD | 1 | 无引擎时禁止启动更新 |
| `...\Windows Defender\Signature Updates` | ScheduleTime | DWORD | 1440 | 签名更新计划设为 1440 分钟 |
| `...\Windows Defender\Signature Updates` | DisableScanOnUpdate | DWORD | 1 | 更新签名后不执行扫描 |

#### Defender 策略 — Scan（扫描）

| 注册表路径 | 值名 | 类型 | 值 | 作用 |
|---|---|---|---|---|
| `...\Windows Defender\Scan` | LowCpuPriority | DWORD | 1 | 扫描使用低 CPU 优先级 |
| `...\Windows Defender\Scan` | DisableRestorePoint | DWORD | 1 | 扫描前不创建还原点 |
| `...\Windows Defender\Scan` | DisableArchiveScanning | DWORD | 0 | 关闭压缩包扫描 |
| `...\Windows Defender\Scan` | DisableScanningNetworkFiles | DWORD | 0 | 关闭网络文件扫描 |
| `...\Windows Defender\Scan` | DisableCatchupFullScan | DWORD | 0 | 关闭追赶式全盘扫描 |
| `...\Windows Defender\Scan` | DisableCatchupQuickScan | DWORD | 1 | 关闭追赶式快速扫描 |
| `...\Windows Defender\Scan` | DisableEmailScanning | DWORD | 0 | 关闭邮件扫描 |
| `...\Windows Defender\Scan` | DisableHeuristics | DWORD | 1 | 关闭启发式扫描 |
| `...\Windows Defender\Scan` | DisableReparsePointScanning | DWORD | 1 | 关闭重解析点扫描 |

#### Defender 策略 — 其他子键

| 注册表路径 | 值名 | 类型 | 值 | 作用 |
|---|---|---|---|---|
| `...\Windows Defender\UX Configuration` | SuppressRebootNotification | DWORD | 1 | 禁止重启通知弹窗 |
| `...\Windows Defender\Reporting` | DisableEnhancedNotifications | DWORD | 1 | 禁用增强通知 |
| `...\Windows Defender\Reporting` | DisableGenericRePorts | DWORD | 1 | 禁用通用报告 |
| `...\Windows Defender\Reporting` | WppTracingLevel | DWORD | 0 | 关闭 WPP 跟踪 |
| `...\Windows Defender\Reporting` | WppTracingComponents | DWORD | 0 | 关闭 WPP 跟踪组件 |
| `...\Windows Defender\MpEngine` | MpEnablePus | DWORD | 0 | 关闭 PUS 云查询 |
| `...\Windows Defender\MpEngine` | MpCloudBlockLevel | DWORD | 0 | 云阻止级别设为低 |
| `...\Windows Defender\MpEngine` | MpBafsExtendedTimeout | DWORD | 0 | 关闭 BAFS 扩展超时 |
| `...\Windows Defender\MpEngine` | EnableFileHashComputation | DWORD | 0 | 关闭文件哈希计算 |
| `...\Windows Defender\NIS\Consumers\IPS` | ThrottleDetectionEventsRate | DWORD | 0 | 关闭检测事件节流 |
| `...\Windows Defender\NIS\Consumers\IPS` | DisableSignatureRetirement | DWORD | 1 | 禁用签名退役 |
| `...\Windows Defender\NIS\Consumers\IPS` | DisableProtocolRecognition | DWORD | 1 | 禁用协议识别 |
| `...\Windows Defender\Policy Manager` | DisableScanningNetworkFiles | DWORD | 1 | 策略管理器禁用网络文件扫描 |
| `...\Windows Defender\Exclusions` | DisableAutoExclusions | DWORD | 1 | 禁用自动排除项 |
| `...\Windows Defender\Windows Defender Exploit Guard\Controlled Folder Access` | EnableControlledFolderAccess | DWORD | 0 | 关闭受控文件夹访问 |
| `...\Windows Defender\Windows Defender Exploit Guard\Network Protection` | EnableNetworkProtection | DWORD | 0 | 关闭网络保护 |

> 路径前缀均为 `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender`

#### Defender 策略 — Legacy（Microsoft Antimalware）

| 注册表路径 | 值名 | 类型 | 值 | 作用 |
|---|---|---|---|---|
| `HKLM:\SOFTWARE\Policies\Microsoft\Microsoft Antimalware` | ServiceKeepAlive | DWORD | 0 | 禁止服务自动重启 |
| `HKLM:\SOFTWARE\Policies\Microsoft\Microsoft Antimalware` | AllowFastServiceStartup | DWORD | 0 | 禁止服务快速启动 |
| `HKLM:\SOFTWARE\Policies\Microsoft\Microsoft Antimalware` | DisableRoutinelyTakingAction | DWORD | 1 | 禁用定期扫描 |
| `HKLM:\SOFTWARE\Policies\Microsoft\Microsoft Antimalware` | DisableAntiSpyware | DWORD | 1 | 禁用反间谍软件 |
| `HKLM:\SOFTWARE\Policies\Microsoft\Microsoft Antimalware` | DisableAntiVirus | DWORD | 1 | 禁用反病毒 |
| `...\Microsoft Antimalware\SpyNet` | SpyNetReporting | DWORD | 0 | 关闭云保护报告 |
| `...\Microsoft Antimalware\SpyNet` | LocalSettingOverrideSpyNetReporting | DWORD | 0 | 禁止本地覆盖云保护报告 |

#### WOW6432Node（32 位兼容）

| 注册表路径 | 值名 | 类型 | 值 | 作用 |
|---|---|---|---|---|
| `HKLM:\SOFTWARE\WOW6432Node\Policies\Microsoft\Windows Defender` | DisableRoutinelyTakingAction | DWORD | 1 | 32 位兼容层禁用定期扫描 |

#### Smart App Control

| 注册表路径 | 值名 | 类型 | 值 | 作用 |
|---|---|---|---|---|
| `HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy` | VerifiedAndReputablePolicyState | DWORD | 0 | 关闭智能应用控制 |

#### SmartScreen 全套关闭

| 注册表路径 | 值名 | 类型 | 值 | 作用 |
|---|---|---|---|---|
| `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen` | Enabled | DWORD | 0 | 关闭 Defender SmartScreen |
| `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen` | EnableSmartScreenInShell | DWORD | 0 | 关闭 Shell 中 SmartScreen |
| `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen` | ConfigureAppInstallControlEnabled | DWORD | 1 | 允许安装任意来源应用 |
| `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen` | ConfigureAppInstallControl | String | Anywhere | 应用安装来源设为任意 |
| `HKLM:\SOFTWARE\Policies\Microsoft\Windows\System` | EnableSmartScreen | DWORD | 0 | 关闭系统级 SmartScreen |
| `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer` | SmartScreenEnabled | String | Off | 关闭 Explorer SmartScreen |
| `HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\PhishingFilter` | EnabledV9 | DWORD | 0 | 关闭 Edge SmartScreen |
| `HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\PhishingFilter` | PreventOverride | DWORD | 0 | 允许绕过 Edge 警告 |
| `HKCU:\Software\Microsoft\Edge` | SmartScreenEnabled | DWORD | 0 | 关闭 Edge 用户级 SmartScreen |
| `HKCU:\Software\Microsoft\Windows\CurrentVersion\AppHost` | EnableWebContentEvaluation | DWORD | 0 | 关闭 Store 应用 SmartScreen |
| `HKCU:\Software\Microsoft\Windows\CurrentVersion\AppHost` | PreventOverride | DWORD | 0 | 允许绕过 Store 应用警告 |
| `HKLM:\SOFTWARE\Microsoft\PolicyManager\default\Browser\AllowSmartScreen` | value | DWORD | 0 | 策略管理器关闭浏览器 SmartScreen |
| `HKLM:\SOFTWARE\Microsoft\PolicyManager\default\SmartScreen\EnableSmartScreenInShell` | value | DWORD | 0 | 策略管理器关闭 Shell SmartScreen |
| `HKLM:\SOFTWARE\Microsoft\PolicyManager\default\SmartScreen\EnableAppInstallControl` | value | DWORD | 0 | 策略管理器关闭应用安装控制 |
| `HKLM:\SOFTWARE\Microsoft\PolicyManager\default\SmartScreen\PreventOverrideForFilesInShell` | value | DWORD | 0 | 策略管理器允许绕过 Shell 警告 |

#### 安全中心通知抑制

| 注册表路径 | 值名 | 类型 | 值 | 作用 |
|---|---|---|---|---|
| `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications` | DisableEnhancedNotifications | DWORD | 1 | 禁用增强通知 |
| `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications` | DisableNotifications | DWORD | 1 | 禁用所有安全中心通知 |
| `HKLM:\SOFTWARE\Microsoft\Security Center` | FirstRunDisabled | DWORD | 1 | 禁用首次运行提示 |
| `HKLM:\SOFTWARE\Microsoft\Security Center` | AntiVirusOverride | DWORD | 1 | 覆盖杀毒软件状态显示 |
| `HKLM:\SOFTWARE\Microsoft\Security Center` | FirewallOverride | DWORD | 1 | 覆盖防火墙状态显示 |
| `HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.SecurityAndMaintenance` | Enabled | DWORD | 0 | 禁用安全和维护 Toast 通知 |

#### WinDefend 服务

| 服务名 | 操作 | 作用 |
|---|---|---|
| WinDefend | 停止并禁用 | 停止 Windows Defender 服务并设为禁用 |

#### Y 删除分支（输入 Y 执行）

**17 个服务停止并禁用**

| 服务名 | 显示名称 |
|---|---|
| WinDefend | Windows Defender |
| WdNisSvc | Microsoft Defender 防火墙网络实时检查服务 |
| WdNisDrv | Microsoft Defender 防火墙网络实时检查驱动程序 |
| WdBoot | Microsoft Defender 防火墙启动驱动程序 |
| WdFilter | Microsoft Defender 防火墙迷你筛选器驱动程序 |
| wscsvc | 安全中心 |
| SgrmAgent | System Guard 运行时监视器代理 |
| SgrmBroker | System Guard 运行时监视器代理程序 |
| MsSecCore | Microsoft 安全核心 |
| MsSecFlt | Microsoft 安全核心迷你筛选器驱动程序 |
| MsSecWfp | Microsoft 安全核心 WFP 驱动程序 |
| whesvc | Windows Hello 生物特征服务 |
| webthreatdefsvc | Web 威胁防御服务 |
| webthreatdefusersvc | Web 威胁防御用户服务（通配符匹配） |
| PlutonHsp2 | Pluton HSP 服务 |
| PlutonHeci | Pluton HECI 服务 |
| Hsp | 硬件传感器平台 |

**计划任务删除**

删除 `Microsoft\Windows\Windows Defender\` 路径下的所有计划任务。

**自启动项移除**

| 注册表路径 | 值名 | 作用 |
|---|---|---|
| `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run` | SecurityHealth | 移除安全中心自启动 |
| `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run` | SecurityHealth | 移除安全中心启动审批 |
| `HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run` | Windows Defender | 移除 Defender 自启动 |
| `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run` | WindowsDefender | 移除 WindowsDefender 自启动 |

**SecHealthUI 卸载**

通过 `Remove-AppxPackage` 卸载 `Microsoft.SecHealthUI`（Windows 安全中心界面应用）。

---

### Part 5：优化服务项（选项 5）

> 选项 5 会在修改后回读目标服务的启动类型；服务不存在显示为跳过，实际类型不符显示 `[VERIFY FAIL]`。出现写入或验证失败时不会自动重启。

#### 30 个服务分组停止并禁用

> **A 组（21 个）：** 通常可在不需要对应功能时禁用。**B 组（9 个）：** 按需禁用，可能影响诊断、兼容性、打印、搜索或预读等系统功能。A/B 只是风险分类，不是交互式选择；当前选项 5 仍会执行两组全部服务。服务不存在时跳过，修改后逐项回读启动类型；验证失败不会自动重启。

| 分组 | 服务名 | 显示名称 | 处理建议 |
|---|---|---|---|
| B | DPS | 诊断策略服务 | 按需禁用，可能影响 Windows 诊断 |
| B | WdiServiceHost | 诊断服务主机 | 按需禁用，可能影响 Windows 诊断 |
| B | WdiSystemHost | 诊断系统主机 | 按需禁用，可能影响 Windows 诊断 |
| B | diagsvc | Diagnostic Execution Service | 按需禁用，可能影响 Windows 诊断 |
| A | DialogBlockingService | DialogBlockingService | 不需要对应升级对话框功能时通常可禁用 |
| A | TrkWks | 分布式链接跟踪客户端 | 单机环境通常可禁用 |
| A | AppVClient | Microsoft App-V 客户端 | 不使用企业 App-V 时可禁用 |
| A | MsKeyboardFilter | Microsoft 键盘筛选器 | 非网吧/展示/锁键场景通常可禁用 |
| A | NetTcpPortSharing | Net.Tcp 端口共享服务 | 不使用相关 WCF 功能时可禁用 |
| A | CscService | 脱机文件 | 不使用域/脱机文件时可禁用 |
| A | ssh-agent | OpenSSH 认证代理 | 不使用 SSH 密钥代理时可禁用 |
| B | PhoneSvc | 电话服务 | 按需禁用，可能影响蜂窝/电话相关功能 |
| B | PcaSvc | 程序兼容性助手 | 按需禁用，可能影响兼容性提示/修复 |
| A | RemoteRegistry | 远程注册表 | 通常可禁用；远程注册表管理将不可用 |
| A | RemoteAccess | 路由和远程访问 | 不使用 RRAS/相关远程访问功能时可禁用 |
| A | SensorDataService | 传感器数据服务 | 无相关传感器设备时通常可禁用 |
| A | SensrSvc | 传感器监视服务 | 无相关传感器/自适应功能时通常可禁用 |
| A | shpamsvc | 共享电脑账户管理器 | 不使用共享电脑模式时可禁用 |
| A | UevAgentService | 用户体验虚拟化 | 不使用企业 UE-V 时可禁用 |
| A | WalletService | WalletService | 不使用相关功能时可禁用 |
| A | wisvc | Windows 预览体验成员服务 | 不参与 Windows Insider 时可禁用 |
| A | WSAIFabricSvc | WSAIFabricSvc | 不使用对应本地 AI/集成能力时可禁用 |
| A | dmwappushservice | WAP 推送消息路由服务 | 不使用企业 MDM/推送能力时可禁用 |
| A | DusmSvc | 数据使用量 | 不需要流量统计时可禁用 |
| A | tzautoupdate | 自动时区更新程序 | 不需要自动时区更新时可禁用 |
| B | Spooler | Print Spooler | 按需禁用，不打印时可禁用；需要打印时必须启用 |
| B | WSearch | Windows Search | 按需禁用，可能影响开始菜单/资源管理器搜索 |
| B | SysMain | SysMain | 按需禁用，可能影响系统预读/应用启动行为 |
| A | edgeupdate | Microsoft Edge 更新服务 | 不需要 Edge 自动更新时可禁用 |
| A | edgeupdatem | Microsoft Edge 更新服务 (Machine) | 不需要 Edge 自动更新时可禁用 |

#### 7 个服务改成手动

| 服务名 | 显示名称 | 改为手动的原因 |
|---|---|---|
| XboxGipSvc | Xbox 配件管理服务 | Xbox 手柄/方向盘等配件需要 |
| XblAuthManager | Xbox Live 身份验证管理器 | Game Pass / 微软商店游戏登录必需 |
| XboxNetApiSvc | Xbox Live 网络服务 | Xbox Live 多人联机/匹配需要 |
| XblGameSave | Xbox Live 游戏保存 | 云存档同步 |
| bthserv | 蓝牙支持服务 | 蓝牙耳机/手柄/键鼠需要 |
| embeddedmode | 嵌入模式 | Store 应用和开始菜单后台任务依赖 |
| BITS | 后台智能传输服务 | Windows 更新和后台下载需要 |

---

### Part 6：应用超性能电源计划（选项 6）

不修改注册表，通过 `powercfg` 导入并应用仓库自带的 `ultimate-performance.pow` 电源计划文件。

| 子选项 | 操作 | 说明 |
|---|---|---|
| 1 | 备份 + 导入并应用 | 先将当前正在使用的电源计划用 `powercfg /export` 备份到脚本所在目录的 `power-backup.pow`（已存在则不覆盖，保护最初备份），再用 `powercfg /import` 导入 `ultimate-performance.pow` 并 `powercfg /setactive` 设为当前计划 |
| 2 | 恢复备份 | 用 `powercfg /import` 导入 `power-backup.pow` 并 `powercfg /setactive` 恢复原先使用的电源计划 |

> 涉及的命令：`powercfg /getactivescheme`（读取当前计划 GUID）、`powercfg /export <文件> <GUID>`、`powercfg /import <文件>`、`powercfg /setactive <GUID>`

#### ultimate-performance.pow 电源计划内容

该计划源自作者本机正在使用的计划（名称 "kirby"，基于高性能模板深度调校），共 177 项设置。以下按子组列出全部内容（交流 = 接通电源，直流 = 电池供电）。

**常规（不属于任何子组）**

| 设置 | 交流 | 直流 | 说明 |
|---|---|---|---|
| 唤醒时需要密码 | 否 | 否 | 唤醒后不锁屏 |
| 电源计划类型 | 高性能 | 高性能 | 计划基于高性能模板 |
| 设备空闲策略 | 性能 | 性能 | 设备空闲时优先性能 |
| 断开连接待机模式 | 正常 | 正常 | 现代待机保持正常模式 |
| 待机状态下的网络连接性 | 启用 | 启用 | 待机时保持网络连接 |

**硬盘**

| 设置 | 交流 | 直流 | 说明 |
|---|---|---|---|
| AHCI 链路电源管理 (HIPM/DIPM) | Active | Active | 禁用 SATA 链路节电，硬盘始终全速 |
| 最大电量水平 | 100% | 100% | 硬盘可用功耗不设限 |
| 在此时间后关闭硬盘 | 30 秒 | 30 秒 | 30 秒空闲后关闭硬盘 |
| Secondary NVMe 空闲超时 | 2000 ms | 2000 ms | 副 NVMe 进入低功耗前的空闲时间 |
| Primary NVMe 空闲超时 | 200 ms | 200 ms | 主 NVMe 进入低功耗前的空闲时间 |
| AHCI 链路电源管理 - 自适应 | 0 ms | 0 ms | 关闭自适应链路节电 |
| NVMe NOPPME | 关闭 | 关闭 | 禁用 NVMe 非操作电源状态许可 |

**Internet Explorer / 桌面背景 / 无线适配器**

| 设置 | 交流 | 直流 | 说明 |
|---|---|---|---|
| JavaScript 计时器频率 | 最高性能 | 最高性能 | IE 内核计时器不节流 |
| 幻灯片放映 | 可用 | 可用 | 桌面背景幻灯片正常播放 |
| 无线适配器节能模式 | 最高性能 | 最高性能 | WiFi 不节电，保持满速 |

**睡眠**

| 设置 | 交流 | 直流 | 说明 |
|---|---|---|---|
| 在此时间后睡眠 | 从不 | 从不 | 永不自动睡眠 |
| 在此时间后休眠 | 从不 | 从不 | 永不自动休眠 |
| 允许混合睡眠 | 关 | 关 | 关闭混合睡眠 |
| 允许使用唤醒定时器 | 启用 | 启用 | 允许定时器唤醒 |
| 允许待机状态 | 关 | 关 | 禁止进入待机状态 |
| 无人参与系统睡眠超时 | 120 秒 | 120 秒 | 无人参与唤醒后 2 分钟回睡 |

**USB / PCI Express**

| 设置 | 交流 | 直流 | 说明 |
|---|---|---|---|
| USB 选择性暂停 | 已禁用 | 已禁用 | USB 设备不挂起（外设不延迟） |
| USB 3 链路电源管理 | 关闭 | 关闭 | USB3 链路不节电 |
| PCI Express 链接状态电源管理 | 关闭 | 关闭 | PCIe ASPM 关闭，显卡/扩展卡全速 |

**处理器电源管理（核心项，节选关键设置）**

| 设置 | 交流 | 直流 | 说明 |
|---|---|---|---|
| 最小处理器状态 | 100% | 100% | CPU 不降频，全程满速 |
| 最大处理器状态 | 100% | 100% | CPU 频率上限不限制 |
| 处理器性能提升模式 | 积极 | 积极 | 睿频激进拉升 |
| 处理器性能提升阈值 | 1% | 1% | 1% 负载即触发升频 |
| 处理器性能降低阈值 | 10% | 10% | 负载降到 10% 以下才降频 |
| 处理器性能提升时间 | 1 | 1 | 立即升频（最小延迟） |
| 处理器性能下降时间 | 1 | 1 | 立即降频响应 |
| 允许节流状态 | 关 | 关 | 禁用 CPU 节流状态 |
| 处理器闲置禁用 | 否 | 否 | 允许处理器闲置状态 |
| 处理器能源性能首选项策略 | 0% | 0% | 完全偏向性能（0% 节能） |
| 处理器资源优先级 | 100% | 100% | 延迟敏感任务最高优先级 |
| 系统散热方式 | 主动 | 主动 | 风扇主动散热（先加速风扇再降频） |
| 处理器最大频率 | 0 (不限制) | 0 (不限制) | 不限制最高频率 |
| 异类线程调度策略 | 所有处理器 | 所有处理器 | 线程可调度到任意核心 |
| 异类短运行线程调度策略 | 偏性能处理器 | 0x5（系统预设） | 短时线程交流下偏向性能核 |
| 处理器性能核心放置最小核心数 | 100% | 100% | 所有核心保持在线不关闭 |

> 处理器电源管理子组共 90+ 项，除上表外其余均为配套的核心放置/休止/异构调度微调，整体思路：性能核优先、升频激进、禁用节能闲置。

**显示**

| 设置 | 交流 | 直流 | 说明 |
|---|---|---|---|
| 在此时间后关闭显示 | 从不 | 从不 | 永不自动关闭显示器 |
| 显示器变暗时间 | 585 秒 | 225 秒 | 交流约 10 分钟/直流约 4 分钟后变暗 |
| 显示器亮度 | 100% | 100% | 亮度最高 |
| 启用自适应亮度 | 关 | 关 | 关闭自动亮度 |
| 自适应显示 | 关 | 关 | 关闭自适应显示 |
| 控制台锁定显示关闭超时 | 30 秒 | 30 秒 | 锁屏后 30 秒关闭显示 |

**其他**

| 子组 | 设置 | 交流 | 直流 |
|---|---|---|---|
| 电源按钮和盖子 | 电源按钮操作 | 关机 | 关机 |
| 电源按钮和盖子 | 睡眠按钮操作 | 不操作 | 不操作 |
| 电源按钮和盖子 | 合上盖子操作 | 不操作 | 不操作 |
| 电源按钮和盖子 | 「开始」菜单电源按钮 | 关机 | 关机 |
| 多媒体 | 播放视频时 | 优化视频质量 | 优化视频质量 |
| 多媒体 | 共享媒体时 | 阻止睡眠 | 阻止睡眠 |
| 节能模式设置 | 节能模式策略 | 关 | 关 |
| 电池 | 低电量操作 | 不操作 | 不操作 |
| 电池 | 关键级别电池操作 | 休眠 | 休眠 |
| 电池 | 关键电池电量水平 | 5% | 5% |
| 电池 | 低电池电量水平 | 6% | 6% |

**整体特征**：CPU 全程满频（最小/最大处理器状态均 100%）、升频激进（1% 负载即触发）、禁用 CPU 节流、PCIe/USB/硬盘/无线全链路不节电、永不睡眠/关屏、风扇主动散热。适合台式游戏机追求最低延迟和最高响应速度，代价是功耗和发热增加，笔记本电池续航会明显缩短。

---

### Part 7：启用原生 NVMe 驱动（选项 7）

通过 Windows Velocity 功能覆盖，提前启用微软原生 NVMe 磁盘驱动 `nvmedisk.sys`（仅作用于 NVMe 磁盘，USB 等其他总线磁盘仍使用 `disk.sys`）。

> 实现机制与 ViVeTool 等效：本节写入的注册表项正是 `ViVeTool /enable /id:735209102 /id:1853569164 /id:156965516` 底层写入的内容，无需额外下载工具；子选项 2 删除覆盖值，等效于回到"未配置"状态（比 ViVeTool `/disable` 写 0 更干净）。

**前提**：系统 25H2（build 26200）及以上 + 存在 NVMe 磁盘；无 NVMe 磁盘时自动跳过，低版本时提示确认。

**子选项 0：只读状态检查**（不做任何修改）：显示 3 个 Velocity 覆盖值写入情况、安全模式加固有无、`nvmedisk.sys` 文件是否已分发（含版本）、驱动加载状态，并给出结论（已启用运行中 / 已写入待重启 / 未启用 / 该版本无法启用）。适用于启用后确认是否生效（设备管理器"驱动程序文件"列表中 `nvmedisk.sys` 取代 `disk.sys` 即生效）。

**子选项 1：启用**

| 注册表路径 | 值名 | 类型 | 值 | 作用 |
|---|---|---|---|---|
| `HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides` | 735209102 | DWORD | 1 | Velocity 功能覆盖 |
| `HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides` | 1853569164 | DWORD | 1 | Velocity 功能覆盖 |
| `HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides` | 156965516 | DWORD | 1 | Velocity 功能覆盖 |
| `HKLM:\SYSTEM\CurrentControlSet\Control\SafeBoot\Minimal\{75416E63-5912-4DFA-AE8F-3EFACCAFFB14}` | (默认) | SZ | Storage Disks | 安全模式加固：nvmedisk 设备类加入最小安全模式加载列表 |
| `HKLM:\SYSTEM\CurrentControlSet\Control\SafeBoot\Network\{75416E63-5912-4DFA-AE8F-3EFACCAFFB14}` | (默认) | SZ | Storage Disks | 安全模式加固：带网络的安全模式加载列表 |

**子选项 2：还原**：删除上述 3 个 Velocity 覆盖值（安全模式加固保留，无副作用），重启后 NVMe 磁盘恢复使用 `disk.sys`。

**验证方式**：设备管理器 → 磁盘驱动器 → NVMe 磁盘属性 → 驱动程序 → 驱动程序文件，列表中出现 `nvmedisk.sys`（占据原 `disk.sys` 位置）即已生效。

> 实测版本数据：26200.5516 / 5601 / 5641 / 5651 / 5691 / 7623 均启用成功；**26100.2454（24H2 十月更新批次）无法启用**；个别 26100.7xxx 用户反馈未操作即已生效（疑似该版本已默认启用）。微软可能在部分版本移除或调整该灰度功能，无法启用属正常现象，脚本无法绕过。

---

### Part 8：清除 Device Guard EFI 锁定（选项 8）

应对 **UEFI 锁定**场景：选项 1 已通过注册表关闭 VBS/HVCI/Credential Guard，但 Windows 安全中心或 `msinfo32`（系统摘要 → 基于虚拟化的安全性）仍显示"内核隔离-内存完整性"或"凭据保护"处于开启状态——此时 Device Guard 配置被锁在 EFI 变量里，注册表改不动，需用本选项的"硬手段"清除。

> 等效替代：微软官方 DG_Readiness_Tool（`DG_Readiness_Tool_v3.5.ps1 -Disable -AutoReboot`，重启后按 Win+F3 确认）。

**BitLocker 预检查**：清除 EFI 变量会改变 TPM 度量值，若 BitLocker 保护已开启，下次开机可能被要求输入 48 位恢复密钥（即"进入 BitLocker 恢复模式"，防篡改保护被触发，并非数据丢失，但没备份恢复密钥会被锁在门外）。子选项 1 执行前会查询 `Get-BitLockerVolume`，检测到任一分区 `ProtectionStatus=On` 即拒绝执行并提示先暂停保护（`Suspend-BitLocker`，可维持数次重启）或解密。BitLocker 未开启的机器无此风险。

**子选项 1：执行**

| 步骤 | 命令/操作 | 作用 |
|---|---|---|
| 1 | `Get-BitLockerVolume` 检查 | 任一分区保护开启则拒绝执行（防触发恢复模式） |
| 2 | 从 X/Y/Z/V/W/U 取空闲盘符，`mountvol <盘符>: /s` | 挂载 EFI 分区 |
| 3 | 复制 `%SystemRoot%\System32\SecConfig.efi` 到 `<盘符>:\EFI\Microsoft\Boot\` | 放置 EFI 变量清除工具 |
| 4 | `bcdedit /delete {0cb3b571-2f2e-4343-a879-d86a476d7215} /f` | 先删除可能残留的旧引导项（保证可重复执行） |
| 5 | `bcdedit /create {0cb3b571-2f2e-4343-a879-d86a476d7215} /d DebugTool /application osloader` | 创建引导项 |
| 6 | `bcdedit /set {0cb3b571-2f2e-4343-a879-d86a476d7215} path \EFI\Microsoft\Boot\SecConfig.efi` | 引导项指向 SecConfig.efi |
| 7 | `bcdedit /set {0cb3b571-2f2e-4343-a879-d86a476d7215} device partition=<盘符>:` | 引导项设备分区 |
| 8 | `bcdedit /set {0cb3b571-2f2e-4343-a879-d86a476d7215} loadoptions DISABLE-LSA-ISO` | 清除 Credential Guard（LSA 隔离）EFI 变量 |
| 9 | `bcdedit /set {bootmgr} bootsequence {0cb3b571-2f2e-4343-a879-d86a476d7215}` | 设为**下次开机一次性**引导（bootsequence 自动消耗，不会永久占用引导顺序） |
| 10 | `mountvol <盘符>: /d` | 卸载 EFI 分区 |

执行后脚本 5 秒自动重启（按 Q 取消）。**重启开机会出现确认界面，需按屏幕提示按键（通常为 F3）确认禁用**；错过或拒绝则本次不生效（一次性引导项不会再次出现，可重跑本选项）。

**子选项 2：清理**：删除上述 BCD 引导项、清空 `{bootmgr}` 的 bootsequence、卸载残留的 EFI 分区盘符；无需重启。适用于执行过子选项 1 但尚未重启就想撤销，或配置中途失败后的收拾。

**验证方式**：重启确认后，`msinfo32` → 系统摘要 → 基于虚拟化的安全性，应显示"未启用"；Windows 安全中心 → 内核隔离 → 内存完整性应显示"关"。

---

### Part 9：虚拟化还原 / Hyper-V 启用（选项 9）

与选项 1（关闭 VBS / Hyper-V）互为还原，补齐虚拟化开关的另一半。选项 1 覆盖 bcdedit、可选功能和注册表层面的关闭操作；本选项提供恢复虚拟化并尝试启用 Hyper-V 功能的入口。Windows Home 官方不支持 Hyper-V 角色，DISM 是否能找到并启用相关组件取决于系统版本和映像。

**关闭 Hyper-V 的三种方法与本脚本的对应关系**

| 方法 | 命令 / 操作 | 本脚本对应 |
|---|---|---|
| 方法一：bcdedit 关闭虚拟机监控器 | `bcdedit /set hypervisorlaunchtype off` | 选项 1（另有 `vsmlaunchtype` / `isolatedcontext`） |
| 方法二：控制面板卸载功能 | 程序和功能 → 启用或关闭 Windows 功能 → 取消勾选 Hyper-V | 选项 1（DISM 等效执行，检测到已启用才禁用） |
| 方法三：DISM 卸载功能 | `DISM /Online /Disable-Feature /FeatureName:Microsoft-Hyper-V-All /norestart` | 选项 1（`Disable-WindowsOptionalFeature` 即其 PowerShell 封装） |
| 配套：关闭内存完整性 / 凭据保护 | Windows 安全中心 → 内核隔离 手动关闭 | 选项 1 注册表层（更彻底）+ 选项 8 EFI 锁定清除 |

**子选项 0：只读状态检查**（不做任何修改）：显示 bcdedit 三个引导项的当前值、Device Guard 注册表关闭值有无、Hyper-V 功能组件状态（附带显示 VirtualMachinePlatform / HypervisorPlatform——WSL2 / Docker 依赖，本脚本从不改动），并给出结论（已被本脚本关闭 / 系统默认状态）。

**子选项 1：还原**——对应选项 1 的虚拟化关闭部分：

| 操作 | 命令 / 对象 | 作用 |
|---|---|---|
| bcdedit 还原 | `bcdedit /deletevalue hypervisorlaunchtype` | 恢复虚拟机监控器默认启动（Auto，随需启动） |
| bcdedit 还原 | `bcdedit /deletevalue vsmlaunchtype` | 恢复 VSM 默认启动 |
| bcdedit 还原 | `bcdedit /deletevalue isolatedcontext` | 恢复隔离上下文默认 |
| 注册表还原 | 删除下表 5 个值 | 恢复"未配置"（跟随系统默认），比写回 1（强制开启）更干净 |

| 注册表路径 | 值名 | 选项 1 写入值 | 还原操作 |
|---|---|---|---|
| `HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity` | Enabled | 0 | 删除值 |
| `HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard` | EnableVirtualizationBasedSecurity | 0 | 删除值 |
| `HKLM:\SYSTEM\CurrentControlSet\Control\LSA` | LsaCfgFlags | 0 | 删除值 |
| `HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard` | EnableVirtualizationBasedSecurity | 0 | 删除值 |
| `HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard` | RequirePlatformSecurityFeatures | 0 | 删除值 |

**子选项 2：完整还原 + 启用 Hyper-V 功能**：先做子选项 1 的全部内容，再执行：

| 命令 | 作用 |
|---|---|
| `Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All -NoRestart` | 启用 Hyper-V 功能本体（`-All` 连带全部依赖子功能），重启后生效 |

> **Windows Home 限制**：Microsoft 官方不支持在家庭版提供 Hyper-V 角色。脚本仍可能尝试调用 `Enable-WindowsOptionalFeature`，但是否存在 `Microsoft-Hyper-V-All` 以及能否启用完全取决于系统版本和映像；失败时应以脚本输出为准，不能将其视为等价于专业版控制面板中的 Hyper-V。

**注意事项**：

- 本选项只启用/禁用 Hyper-V 本体（`Microsoft-Hyper-V-All`），从不改动 `VirtualMachinePlatform` / `HypervisorPlatform` / Windows 沙盒等功能：WSL2、Docker Desktop 依赖的是后两者，单独还原虚拟化（子选项 1）后它们即可恢复。
- 选项 1 的 `hypervisorlaunchtype off` 会连带使 WSL2 / Docker / Windows 沙盒 / 部分安卓模拟器不可用——需要这些功能时用本选项还原。
- Meltdown/Spectre 缓解关闭（`FeatureSettingsOverride`）、NX / 驱动完整性检查等其余 BCDEdit 项**不在**本选项还原范围（与虚拟化无关，恢复方法见 README）。
- 若之前执行过选项 8 清除了 EFI 变量，Device Guard 相关开关会回到"未配置"；如需重新开启 VBS/内存完整性，还原后在 Windows 安全中心 → 内核隔离 中手动开启。

**验证方式**：子选项 2 重启后，开始菜单搜索"Hyper-V 管理器"可打开即启用成功；`msinfo32` → 系统摘要 → 基于虚拟化的安全性 可查看 Hyper-V 服务状态；WSL2 可用 `wsl --status` 确认。

---

### Part 10：MPO 设置管理（选项 10）

MPO（Multi-Plane Overlay，多平面叠加）是 Windows/DWM 使用的硬件多平面合成路径，可让视频或其他内容独立于主画面合成；具体收益和行为取决于系统、显卡驱动、显示器与应用。MPO 相关异常在社区中常被报告为闪屏、切屏黑屏、副屏冻结或视频卡顿，但这些注册表值不是微软或显卡厂商公开保证的稳定 API。本选项把社区排障中常见的四个值收拢为**三个互斥方案 + 查看 + 还原**，切换方案时自动清除其他方案的值，并在首次修改前保存 `mpo-backup.json`。

**两类方案的本质区别**——“OverlayMinFPS 比禁用 MPO 效果更好”的说法**只能作为 VRR 视频卡顿场景的社区经验，不能视为普遍结论**；两者并非同一问题的两种解法，而是方向相反的两个操作：

| | 禁用 MPO（方案 A / B） | OverlayMinFPS=0（方案 C） |
|---|---|---|
| 本质 | 尝试关闭 MPO，让画面退回 DWM 组合输出 | 尝试避免低帧率时撤下 MPO；实际行为取决于 Windows 和驱动 |
| 解决的问题 | 可用于排查 MPO 相关的多屏闪屏、切屏黑屏、Chromium 残影或副屏冻结；不保证适用于所有系统 | 社区常用于排查 G-Sync/FreeSync 下视频播放卡顿；对 MPO 本身故障不一定有效 |
| 代价 | 可能影响窗口化游戏 VRR、视频呈现、叠加层并增加 DWM 负载；方案 B 还可能影响个别 DX12 游戏 | 通常比禁用 MPO 保守，但不保证有效或完全没有副作用 |

**按症状选择**：

| 症状 | 推荐 |
|---|---|
| 闪屏 / 切屏黑屏 / Chromium 残影 / 副屏冻结（N 卡多屏高发） | 先记录现状并测试 10 → 1；无效再谨慎测试 10 → 2 |
| 仅 G-Sync/FreeSync 开启时视频播放全屏卡顿，游戏画面正常 | 可测试 10 → 3；它是社区排障方案，不保证有效 |
| 禁用 MPO 后窗口化游戏丢失 VRR / 变卡 | 10 → 4 恢复原状态；若仍需排查视频卡顿，再单独测试 10 → 3 |
| 恢复首次修改前状态 | 10 → 4（需要有效的 `mpo-backup.json`） |
| 恢复系统默认但没有备份 | 删除 `mpo-backup.json` 后再运行 10 → 4（不可恢复原自定义值） |

**四个受管理的注册表值**

| 注册表路径 | 值名 | 写入值 | 作用 | 备注 |
|---|---|---|---|---|
| `HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers` | DisableMPO | 1 | 社区常用的 MPO 禁用尝试 | 不同 Windows/驱动版本可能无效；选项 1 会写入本值 |
| `HKLM:\SOFTWARE\Microsoft\Windows\Dwm` | OverlayTestMode | 5 | 社区常用的 DWM 层 MPO 禁用尝试 | 未公开配置，效果和兼容性取决于系统、驱动与应用 |
| `HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers` | DisableOverlays | 1 | 更激进的社区 MPO/叠加层禁用尝试 | 仅在方案 A 无效时测试；可能影响个别 DX12 游戏或其他叠加层 |
| `HKLM:\SOFTWARE\Microsoft\Windows\Dwm` | OverlayMinFPS | 0 | 社区用于排查低帧率时 MPO 撤下行为 | 常用于 G-Sync/FreeSync 视频卡顿排查；实际效果不保证，不能声称完全无兼容性问题 |

**子选项**

| 子选项 | 内容 |
|---|---|
| 0 | 只读查看四个值当前状态（值 + 含义 + 结论），并打印 dxdiag 辅助判断方法；不做任何修改、不重启 |
| 1 | **方案 A**：清除 `DisableOverlays` / `OverlayMinFPS`，写入 `OverlayTestMode=5` + `DisableMPO=1`（社区使用较广，但可能影响窗口化 VRR/视频呈现） |
| 2 | **方案 B**：清除 `OverlayTestMode` / `OverlayMinFPS` / `DisableMPO`，写入 `DisableOverlays=1`（更激进，仅在方案 A 无效时测试；可能影响 DX12 游戏或其他叠加层） |
| 3 | **方案 C**：清除 `OverlayTestMode` / `DisableOverlays` / `DisableMPO`，写入 `OverlayMinFPS=0`（社区用于排查 G-Sync/FreeSync 视频卡顿；实际效果取决于系统和驱动） |
| 4 | **还原**：优先按 `mpo-backup.json` 恢复首次修改前状态；没有备份时才删除全部四个值并恢复系统默认 |

首次执行子选项 1–3 或 Part 1 相关 MPO 修改前，脚本会在脚本目录创建 `mpo-backup.json`，已有备份不会覆盖。子选项 1–4 修改后均 5 秒自动重启（按 `Q` 取消）；MPO 设置需重启才生效。备份文件损坏或无法读取时，脚本会阻止新的 MPO 修改。

**验证方式**：重启后 `Win+R` 运行 `dxdiag` → 保存所有信息 → 打开保存的 txt 搜索 `MPO`。`MPO` 条目消失或 `MPO MaxPlanes` 为 0 在部分系统上可作为禁用的辅助信号；不同 Windows/驱动版本的输出可能不同，不能证明所有应用的运行时状态。最终应结合浏览器/视频、G-Sync/FreeSync、多显示器、窗口化游戏、DX12、HDR、录屏和 Steam/Discord 等覆盖层实测。方案 C 不禁用 MPO，不能用 MaxPlanes 消失判断其是否“生效”。

**参考与证据边界**：社区 MPO 修复仓库 [RedDot-3ND7355/MPO-GPU-FIX](https://github.com/RedDot-3ND7355/MPO-GPU-FIX) 和 [dnpu.com/853.html](https://dnpu.com/853.html) 可作为排障经验参考，但没有提供微软/显卡厂商对这些注册表值的公开稳定性保证；仓库中的“仍有效”“更好”等结论主要来自用户反馈，不能替代逐机测试。

---

## 二、defender-removal.ps1

> ⚠️ 以下所有操作均为**物理移除**（删除键/文件），不可逆。

---

### Part 1：删除服务注册表键

先停止 16 个命名服务 + `webthreatdefusersvc*` 通配符匹配的按用户实例。

**删除的服务注册表整键**（路径前缀 `HKLM:\SYSTEM\CurrentControlSet\Services\`）

| 服务名 | 对应组件 |
|---|---|
| MsSecCore | Microsoft 安全核心 |
| wscsvc | 安全中心 |
| WdNisDrv | Defender 防火墙网络实时检查驱动 |
| WdNisSvc | Defender 防火墙网络实时检查服务 |
| WdFilter | Defender 迷你筛选器驱动 |
| WdBoot | Defender 启动驱动 |
| SgrmAgent | System Guard 运行时监视器代理 |
| SgrmBroker | System Guard 运行时监视器代理程序 |
| WinDefend | Windows Defender 主服务 |
| MsSecFlt | 安全核心迷你筛选器驱动 |
| MsSecWfp | 安全核心 WFP 驱动 |
| whesvc | Windows Hello 生物特征服务 |
| webthreatdefsvc | Web 威胁防御服务 |
| webthreatdefusersvc* | Web 威胁防御用户服务（通配符） |
| PlutonHsp2 | Pluton HSP 服务 |
| PlutonHeci | Pluton HECI 服务 |
| Hsp | 硬件传感器平台 |

**删除的 WinRT / Svchost 注册**

| 注册表路径 | 类型 |
|---|---|
| `HKLM:\SOFTWARE\Microsoft\WindowsRuntime\Server\WebThreatDefSvc` | 整键删除 |
| `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Svchost\WebThreatDefense` | 整键删除 |
| `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Svchost` 中的值 `WebThreatDefense` | 单值删除 |

---

### Part 2：删除应用 / COM / Shell 注册

#### CLSID 删除（14 个 GUID × 2 位置 = 28 个键）

每个 GUID 在以下两个位置均被删除：
- `HKLM:\SOFTWARE\Classes\CLSID\<GUID>`
- `HKLM:\SOFTWARE\Classes\WOW6432Node\CLSID\<GUID>`

| GUID |
|---|
| `{2781761E-28E0-4109-99FE-B9D127C57AFE}` |
| `{2781761E-28E2-4109-99FE-B9D127C57AFE}` |
| `{195B4D07-3DE2-4744-BBF2-D90121AE785B}` |
| `{361290c0-cb1b-49ae-9f3e-ba1cbe5dab35}` |
| `{45F2C32F-ED16-4C94-8493-D72EF93A051B}` |
| `{6CED0DAA-4CDE-49C9-BA3A-AE163DC3D7AF}` |
| `{8a696d12-576b-422e-9712-01b9dd84b446}` |
| `{8C9C0DB7-2CBA-40F1-AFE0-C55740DD91A0}` |
| `{A2D75874-6750-4931-94C1-C99D3BC9D0C7}` |
| `{A7C452EF-8E9F-42EB-9F2B-245613CA0DC9}` |
| `{DACA056E-216A-4FD1-84A6-C306A017ECEC}` |
| `{E3C9166D-1D39-4D4E-A45D-BC7BE9B00578}` |
| `{F6976CF5-68A8-436C-975A-40BE53616D59}` |
| `{E48B2549-D510-4A76-8A5F-FC126A6215F0}` |

#### Autologger 删除

| 注册表路径 |
|---|
| `HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\DefenderAuditLogger` |
| `HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\DefenderApiLogger` |

#### AppUserModelId 删除

| 注册表路径 |
|---|
| `HKLM:\SOFTWARE\Classes\AppUserModelId\Windows.Defender` |
| `HKLM:\SOFTWARE\Classes\AppUserModelId\Microsoft.Windows.Defender` |

#### Shell 关联 / Class 删除

| 注册表路径 | 位置 |
|---|---|
| `HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\windowsdefender` | HKCU |
| `HKLM:\SOFTWARE\Classes\WindowsDefender` | HKLM |
| `HKLM:\SOFTWARE\Classes\AppX9kvz3rdv8t7twanaezbwfcdgrbg3bck0` | HKLM |
| `HKCU:\Software\Classes\AppX9kvz3rdv8t7twanaezbwfcdgrbg3bck0` | HKCU |
| `HKCU:\Software\Classes\ms-cxh` | HKCU |
| `HKCR:\Local Settings\MrtCache\C:%5CWindows%5CSystemApps%5CMicrosoft.Windows.AppRep.ChxApp_cw5n1h2txyewy%5Cresources.pri` | HKCR |

#### WebThreatDefense ActivatableClassId 删除

| 注册表路径 |
|---|
| `HKLM:\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Microsoft.OneCore.WebThreatDefense.Service.UserSessionServiceManager` |
| `HKLM:\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Microsoft.OneCore.WebThreatDefense.ThreatExperienceManager.ThreatExperienceManager` |
| `HKLM:\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Microsoft.OneCore.WebThreatDefense.ThreatResponseEngine.ThreatDecisionEngine` |
| `HKLM:\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Microsoft.OneCore.WebThreatDefense.Configuration.WTDUserSettings` |

#### 策略键删除

| 注册表路径 |
|---|
| `HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WebThreatDefense` |
| `HKLM:\SOFTWARE\Policies\Microsoft\Windows\WTDS` |

#### Ubpm 值删除

在 `HKLM:\SYSTEM\CurrentControlSet\Control\Ubpm` 中删除以下值：

| 值名 | 作用 |
|---|---|
| CriticalMaintenance_DefenderCleanup | Defender 清理关键维护任务 |
| CriticalMaintenance_DefenderVerification | Defender 验证关键维护任务 |

#### 防火墙受限服务值删除

在 `...\FirewallPolicy\RestrictedServices\Static\System` 中删除以下值：

| 值名 |
|---|
| WindowsDefender-1 |
| WindowsDefender-2 |
| WindowsDefender-3 |
| WebThreatDefSvc_Allow_In |
| WebThreatDefSvc_Allow_Out |
| WebThreatDefSvc_Block_In |
| WebThreatDefSvc_Block_Out |

在 `...\FirewallPolicy\RestrictedServices\Configurable\System` 中删除以下值：

| 值名 |
|---|
| `{2A5FE97D-01A4-4A9C-8241-BB3755B65EE0}` |
| `72e33e44-dc4c-40c5-a688-a77b6e988c69` |
| `b23879b5-1ef3-45b7-8933-554a4303d2f3` |

> 路径前缀：`HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy`

---

### Part 3：删除实体文件目录

通过 `takeown` 取得所有权 → `icacls` 授予管理员权限 → `Remove-Item` 递归删除。

| 目录路径 | 说明 |
|---|---|
| `C:\ProgramData\Microsoft\Windows Defender` | Defender 数据和签名目录 |
| `C:\Program Files\Windows Defender` | Defender 主程序目录 |
| `C:\Program Files (x86)\Windows Defender` | Defender 32 位兼容目录 |
| `C:\Program Files\Windows Defender Advanced Threat Protection` | ATP 高级威胁防护目录 |

---

### SYSTEM 重试机制

脚本首先以管理员身份执行所有删除操作。被 TrustedInstaller 保护的键如果失败，会收集起来以 **SYSTEM** 身份通过临时计划任务批量重试：
1. 在 `%TEMP%` 创建临时 `.cmd` 文件，包含所有失败的 `reg.exe delete` 命令
2. 创建计划任务，以 `SYSTEM` 身份、最高权限运行该 `.cmd`
3. 等待 5 秒后验证删除结果
4. 自动清理临时计划任务和 `.cmd` 文件

仍被拒绝的键会如实报告 `[FAIL]`，需借助 NSudo / PowerRun 等提权工具手动处理。

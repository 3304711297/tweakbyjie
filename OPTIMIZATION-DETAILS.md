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

#### 04 VBS / HVCI 关闭

| 注册表路径 | 值名 | 类型 | 值 | 作用 |
|---|---|---|---|---|
| `HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity` | Enabled | DWORD | 0 | 关闭 HVCI（基于虚拟化的代码完整性） |
| `HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard` | EnableVirtualizationBasedSecurity | DWORD | 0 | 关闭 VBS（基于虚拟化的安全） |

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
| `HKLM:\SOFTWARE\Microsoft\Windows\Dwm` | OverlayTestMode | DWORD | 5 | DWM 叠加测试模式优化 |

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

#### 29 个服务停止并禁用

| 服务名 | 显示名称 | 说明 |
|---|---|---|
| DPS | 诊断策略服务 | 诊断向导依赖，日常无用 |
| WdiServiceHost | 诊断服务主机 | 诊断向导依赖，日常无用 |
| WdiSystemHost | 诊断系统主机 | 诊断向导依赖，日常无用 |
| diagsvc | Diagnostic Execution Service | 执行诊断操作，日常无用 |
| DialogBlockingService | DialogBlockingService | 系统升级对话框，平时不触发 |
| TrkWks | 分布式链接跟踪客户端 | 单机无用的 NTFS 链接跟踪 |
| AppVClient | Microsoft App-V 客户端 | 企业应用虚拟化 |
| MsKeyboardFilter | Microsoft 键盘筛选器 | 网吧/展示环境的按键锁定 |
| NetTcpPortSharing | Net.Tcp 端口共享服务 | WCF 开发者功能 |
| CscService | 脱机文件 | 域环境功能，单机无用 |
| ssh-agent | OpenSSH 认证代理 | 不用 SSH 密钥就无影响 |
| PhoneSvc | 电话服务 | 电话/蜂窝链接，桌面端无用 |
| PcaSvc | 程序兼容性助手 | 仅弹兼容性提示 |
| RemoteRegistry | 远程注册表 | 禁用反而更安全 |
| RemoteAccess | 路由和远程访问 | 禁用更安全 |
| SensorDataService | 传感器数据服务 | 台式机无传感器 |
| SensrSvc | 传感器监视服务 | 自适应亮度等，台式机无用 |
| shpamsvc | 共享电脑账户管理器 | 共享电脑模式，个人设备无用 |
| UevAgentService | 用户体验虚拟化 | 企业设置漫游 |
| WalletService | WalletService | 基本废弃的钱包服务 |
| wisvc | Windows 预览体验成员服务 | Insider 计划专用 |
| WSAIFabricSvc | WSAIFabricSvc | 本地 AI（Copilot+）通信 |
| dmwappushservice | WAP 推送消息路由服务 | 企业 MDM 设备管理 |
| DusmSvc | 数据使用量 | 流量统计，宽带无用 |
| tzautoupdate | 自动时区更新程序 | 手动设时区即可 |
| Spooler | Print Spooler | 打印后台处理，不打印可禁用 |
| WSearch | Windows Search | 开始菜单/资源管理器搜索 |
| SysMain | SysMain | 内存预读服务，SSD 上可禁用 |
| edgeupdate | Microsoft Edge 更新服务 | Edge 自动更新 |
| edgeupdatem | Microsoft Edge 更新服务 (Machine) | Edge 自动更新（计算机级） |

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

# XOS Playbook 全量项目清单（人工审查 + 未采纳标注）

- **审计对象**：`imribiy/xos-playbook`，基准分支 **dev @ 0ed60c3**（不是 main ca69d82）
- **基准文件**：`Configuration/custom.yml`（1750 行）、`Executables/`（13 个脚本，含 dev 新增 `ReservedStorage.ps1`）、`playbook.conf`（v0.816）
- **本地对照**：本仓库（PowerShell 调优工具）
- **性质**：只读审计。未修改任何仓库、未 comment/close、未 push
- **日期**：2026-11-20

> **文件性质与维护方式**：第 0–5 节是**人工审查结论**，只在人复核后手工修改；顶部「上游变动」区块由 `tools/check-xos-inventory.ps1 -Apply`（人工显式执行）写入，CI 的 upstream-watch 只跑同一脚本的**只读核查**并把结论贴到 issue，**不改文档、不改基线、不提交**。动作级指纹基线见 `tools/xos-playbook-inventory.json`（dev @0ed60c3，808 条）。

> 行号口径：`custom.yml:行号` 指动作**起始行**；多行块（`!powerShell`/`!cmd` 的 `command: >-`）内引用的具体语句可能相差数行，按值名/命令名检索为准。

<!-- XOS-INVENTORY:DELTA:START -->
## 上游变动（由 `-Apply` 生成，勿手改）

> 本节由 `tools/check-xos-inventory.ps1 -Apply` 在人工确认后刷新：对比 `tools/xos-playbook-inventory.json` 基线与上游 `dev` 当前 `Configuration/custom.yml`。CI 只核查、不写文件；人工结论请写在区块之外的章节。

| 项目 | 值 |
| --- | --- |
| 基准 head（人工审阅） | `0ed60c309495`（2026-11-20） |
| 本次 head | `0ed60c309495` |
| 检测时间 | `2026-11-20T07:39:58Z` |
| 动作总数 | 808 |
| 新增 / 删除 / 变更 | 0 / 0 / 0 |

**结论**：上游 `dev` 相对基准无动作级变动，808 条动作的类型与指纹全部一致。
<!-- XOS-INVENTORY:DELTA:END -->

## 0. 计数口径（先读这段再看表）

1. **1 个动作** = `custom.yml` 顶层 `actions:` 里的一条 `- !type:`；多行 `powerShell` 块算 1 条。
2. **脚本内部子项**（`laptop-desktop.bat`、`network.bat`、`DisableScheduledTasks.ps1`、`RemoveEdge.ps1`、`ReservedStorage.ps1` 等）**不额外计数**，跟随所在的那 1 条动作归组；拆开列出时标「子项」，避免总数膨胀。
3. **注册表按功能域聚合**，每行给「条数 + 代表键值 + 行号」，行号范围即覆盖范围。
4. 六分组：`已采纳/已覆盖`、`A 破坏性`、`B 安全削弱`、`C 范围外`、`D 无依据/重复/无效`、`E 本轮未选`。六组之和 = 808。

### 0.1 dev 相对 main 的全部差异（`gh api compare/main...dev`）

dev 只改了 3 个文件：`Configuration/custom.yml` +9/−4、`Executables/ReservedStorage.ps1` +66（新增）、`playbook.conf` +3/−3。落到动作层面是 **4 条新增**，本清单已全部按「未采纳」收录：

| dev 新增项 | 位置(dev) | 性质 | 本清单归组 |
|---|---|---|---|
| `WaitToKillServiceTimeout=2000`（REG_SZ） | `custom.yml:325` | 服务停止超时调低，缩短关机等待；有丢数据风险 | **D**（可评估但未批准） |
| `HiberbootEnabled=0`（快速启动默认关闭） | `custom.yml:342` | 与本仓 Hibernate.ps1（Part 14）等价覆盖；上游无快照硬写 | **D**（等价覆盖/冲突） |
| `writeStatus 'Disabling Reserved Storage'` | `custom.yml:779` | AME 进度文案 | **C**（随 writeStatus 计） |
| `ReservedStorage.ps1 -Mode Apply` + 脚本本体 | `custom.yml:780` → `Executables/ReservedStorage.ps1:1-66` | DISM 关 Reserved Storage + 开机重试任务 | **A**（有破坏面） |
| `playbook.conf` 版本 0.812→0.816；BCD 描述同步改 `XOS-Playbook-V0.816` | `playbook.conf:5,7,10`；`custom.yml:837` | 版本号/品牌 | **C**（范围外，不单列动作） |

> 已采纳项已按 dev 复核：TdrDelay 在 dev 仍是 **12**（`custom.yml:463`），与本轮已采纳口径一致；其余 4 个机制值未变。

## 1. 总览计数

### 1.1 动作类型枚举（dev 实测 vs 预给 main 统计）


| 动作类型 | 预给统计(main) | dev 实测 | 差异 | 差异来源 |
|---|---|---|---|---|
| writeStatus | 58 | 59 | +1 | +1 Disabling Reserved Storage |
| powerShell | 83 | 84 | +1 | +1 ReservedStorage.ps1 |
| registryValue | 473 | 475 | +2 | +2 WaitToKillServiceTimeout、HiberbootEnabled |
| taskKill | 17 | 17 | 0 | — |
| cmd | 17 | 17 | 0 | — |
| run | 50 | 50 | 0 | — |
| registryKey | 42 | 42 | 0 | — |
| service | 50 | 50 | 0 | — |
| file | 13 | 13 | 0 | — |
| appx | 1 | 1 | 0 | — |
| **合计** | **804** | **808** | **+4** | dev 的 4 条新增动作 |


解析方式：逐行匹配 `^\s*-\s*!(\w+):`，块内缩进归属该动作。**main 804** 与预给统计逐项相等；**dev 808 = 804 + 4**，4 条增量与 0.1 节完全对应。`xos_reg.json` 的 473 条对应 main；dev 的 registryValue 为 **475**。

### 1.2 判定分布（六组之和 = 808）


| 分组 | 条数 | 占全量 | 说明 |
|---|---|---|---|
| 已采纳/已覆盖 | 33 | 4.1% | 字面同名同值、等价路径，或本仓已有同机制模块 |
| A 破坏性修改 | 431 | 53.3% | 关安全/删组件/批量禁服务与任务/全关遥测/停更新 |
| B 安全削弱 | 27 | 3.3% | UAC、DMA remapping、HVCI、MitigationOptions、审计日志 |
| C 范围外 | 123 | 15.2% | 品牌 OEM、壁纸、AME 机制、维护流程、个性化、writeStatus |
| D 无依据/重复/无效 | 191 | 23.6% | 含写法错误、写默认值、HKCU 重复副本、玄学值、收益未量化 |
| E 本轮未选 | 3 | 0.4% | 任务栏悬停 250ms ×2、SmoothScroll=0 |
| **合计** | **808** | 100% | |

> 2026-11-20 增补：B 组 27 条已按用户要求落地为菜单 20（见 3.2.1）。本表保留审计当时的六组口径，不再回算分组；A/C/D/E 组结论不变。


### 1.3 类型 × 判定 交叉表


| 类型 | 已采纳 | A 破坏性 | B 安全 | C 范围外 | D 无据/无效 | E 未选 | 合计 |
|---|---|---|---|---|---|---|---|
| writeStatus | 0 | 0 | 0 | 59 | 0 | 0 | 59 |
| powerShell | 2 | 61 | 2 | 17 | 2 | 0 | 84 |
| registryValue | 15 | 230 | 19 | 21 | 187 | 3 | 475 |
| taskKill | 0 | 7 | 0 | 10 | 0 | 0 | 17 |
| cmd | 4 | 5 | 0 | 7 | 1 | 0 | 17 |
| run | 2 | 36 | 6 | 5 | 1 | 0 | 50 |
| registryKey | 0 | 40 | 0 | 2 | 0 | 0 | 42 |
| service | 10 | 40 | 0 | 0 | 0 | 0 | 50 |
| file | 0 | 11 | 0 | 2 | 0 | 0 | 13 |
| appx | 0 | 1 | 0 | 0 | 0 | 0 | 1 |
| **合计** | 33 | 431 | 27 | 123 | 191 | 3 | 808 |


### 1.4 未采纳合计

未采纳 = 808 − 33 = **775 条**（A 431 + B 27 + C 123 + D 191 + E 3）。真正"优化项"性质的未采纳集中在 A（删/禁类）与 D（无效/玄学类）；dev 新增的 4 条已全部落在 A（ReservedStorage）/ C（进度文案）/ D（WaitToKillServiceTimeout、HiberbootEnabled）。

## 2. 已采纳/已覆盖（33 条，不计入未采纳）


| 项目/值 | 位置 | 具体内容 | 本地证据（file:line） |
|---|---|---|---|
| TimerCoalescing=0 | custom.yml:314 | `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows` | Registry.ps1:165 同名同值 + :192 回读校验 + 快照回滚 |
| DisablePageCombining=1 | custom.yml:320 | `Session Manager\Memory Management` | Registry.ps1:179 同值；另优先 `Disable-MMAgent -PageCombining`（:175），口径更严 |
| TdrDelay=12 | custom.yml:463 | `Control\GraphicsDrivers` | Registry.ps1:98（现为 10，**2026-11-20 拍板跟随上游改为 12，待在 tweakbyjie 落改**），含 :108 回读校验 |
| MousewheelAnimationDurationMs=0 | custom.yml:414 | `HKLM\SOFTWARE\Microsoft\Windows\Dwm` | Registry.ps1:182 |
| MSISupported=1 + 删 Affinity Policy\DevicePriority | custom.yml:894（脚本内 897-901） | 对 IDE/Video/Network 三类设备写 MSISupported=1，并删 DevicePriority | Msi.ps1:58（写 1 + 回读）、Msi.ps1:75 `Remove-MsiAffinityDevicePriority`（本轮新增清理） |
| 每接口 TcpAckFrequency/TCPNoDelay=1 + 网卡/PCI/USB 节能关闭 | custom.yml:1001 → network.bat:61-68,72-127 | `Tcpip\Parameters\Interfaces\*`；`Class\{4d36e972}\*`；`USBHUB3/usbccgp/pci\Parameters` | Network.ps1:101（每接口 + 先快照 + 回滚删值）—— **本轮新落地** |
| SystemResponsiveness=10 | custom.yml:317 | `Multimedia\SystemProfile` | Registry.ps1:86 |
| Win32PrioritySeparation=38 | custom.yml:319 | `Control\PriorityControl` | Registry.ps1:87 + :102 Verify |
| HwSchMode=2（HAGS） | custom.yml:461 | `Control\GraphicsDrivers` | Registry.ps1:88 + :105 Verify |
| CoalescingTimerInterval=0 | custom.yml:323 | `Session Manager\Power` | Registry.ps1:166 |
| DisableTriggerCoalescing=1 | custom.yml:340 | `Services\BrokerInfrastructure\Parameters` | Registry.ps1:167（上游另有 `DefaultTriggerCoalescingTime=0`，未吸收，见 D03） |
| OverlayTestMode=5（MPO 关） | custom.yml:823 | `HKLM\SOFTWARE\Microsoft\Windows\Dwm` | Mpo.ps1:83（作排障方案 A，需用户选择） |
| EnableTransparency=0 | custom.yml:49 | `HKCU\...\Themes\Personalize` | Registry.ps1:153 |
| fsutil disable8dot3=1 / disabledeletenotify=0 / disablelastaccess=1 | custom.yml:773-775 | fsutil 三项 | Registry.ps1:120（NtfsDisable8dot3NameCreation=1）、:137（TRIM）、:164（NtfsDisableLastAccessUpdate） |
| bcdedit /deletevalue useplatformclock、useplatformtick | custom.yml:832-833 | bcdedit | Bcd.ps1:22,45（本仓为可选模块，带 BCD 快照） |
| GameBar/GameDVR：AllowAutoGameMode、AutoGameModeEnabled、UseNexusForGameBarEnabled、AppCaptureEnabled、GameDVR_Enabled | custom.yml:799,800,802,803,806 | `HKCU\Software\Microsoft\GameBar`、`...\GameDVR` | Registry.ps1:58,59,84,96,97 |
| 10 个同名服务禁用：dmwappushservice / WdiSystemHost / WdiServiceHost / diagsvc / DPS / PcaSvc / dusmsvc / wisvc / WSAIFabricSvc / Spooler | custom.yml:705,712,713,715,719,722,723,725,727,731 | `HKLM\SYSTEM\CurrentControlSet\Services\*` | Backup.Service.ps1:7-17 同一批 A/B 组名单，带 service-backup.json 快照与恢复 |


**「已覆盖」判定标准**：本仓存在对应写入点（`Set-RegDword` / `Set-Service` 等）+ 回读校验 + 快照回滚。只有"思路相同但本仓没写"的不算已覆盖（TdrDelay 原本 10 对 12 属差异，本轮已按用户要求统一为 12）。

### 2.1 已采纳项的实现注意（不是未采纳，是落地时要改的写法）

- `network.bat:123` 把网卡节能值一律写成 `REG_SZ "0"`，而这些值原本是 `REG_DWORD`。本仓落地必须写 `REG_DWORD`，否则改的是类型不是值。
- `network.bat:125` 的 `PnPCapabilities=24` 是 DWORD，写法正确，可一并纳入（关闭"允许计算机关闭此设备以节约电源"）。
- `network.bat:126-127` 的 `WakeOnMagicPacketFromS5` / `WolShutdownLinkSpeed` 写 `REG_SZ "2"`，同属类型错误，建议跳过（与本次目标无关）。



## 3. 未采纳项目（775 条，按原因分组）

### 3.1 A. 破坏性修改（431 条）

> 判据（本仓铁律）：关 Defender/安全中心/防火墙、删 Edge 等系统组件、批量禁服务与计划任务、全关遥测、停 Windows Update。


| 项目/值 | 位置(file:line) | 具体内容 | 未采纳原因 |
|---|---|---|---|
| A00 DefenderOFF.ps1 主脚本 / 日志 / 等待引擎（5 条） | custom.yml:83,86,106,117,186 | `DefenderOFF.ps1`（AveYo LeanAndMean 改写）+ MDCoreSvc Start=4 + 写日志 + 等 MsMpEng 退出 + DefenderRunBackup.ps1 | 关 Defender 主体；本仓 Part 5 只做策略层且带策略快照 |
| A01 Defender 服务/驱动 Start=4（22 条） | custom.yml:96-100,124,134,135,196-202,212-218 | WinDefend / WdFilter / WdBoot / WdNisDrv / WdNisSvc / SecurityHealthService / wscsvc / Sense / MsSecCore / MsSecWfp / MsSecFlt / SgrmBroker / wtd / webthreatdef* | 删安全组件、不可回滚 |
| A02 Defender 实时防护/云保护策略（13 条） | custom.yml:101-104,174-182 | DisableAntiSpyware / DisableAntiVirus / DisableRealtimeMonitoring / DisableBehaviorMonitoring / DisableIOAVProtection / DisableOnAccessProtection / SpyNetReporting / DisableBlockAtFirstSeen | 关实时防护；251-256 的 keep-defender 分支仍写 SubmitSamplesConsent=0（见 B04） |
| A03 SmartScreen / AppHost / Aic 关闭（11 条） | custom.yml:150-159,161 | SmartScreenEnabled=Off、EnableSmartScreen=0、AppHost Enabled=0 / PreventOverride=0、EnableWebContentEvaluation=0、AicEnabled=Anywhere、IFEO smartscreen.exe→taskkill | 关 Web 信誉拦截 |
| A03b WTDS（Web 威胁防御）全关（12 条） | custom.yml:138-149 | ServiceEnabled=0、CaptureThreatWindow=0、NotifyMalicious / NotifyPasswordReuse / NotifyUnsafeApp=0（HKLM 与 Policies 各 5 条）+ FeatureFlags BlockUxDisabled=1 / TelemetryCallsEnabled=0 | 关 Web 威胁防护 |
| A04 Defender 运行项 / 日志 / 设置页隐藏（7 条） | custom.yml:187-189,245-247,301 | 删 Run\SecurityHealth、Run\WindowsDefender；StartupApproved 写 03 00…；DefenderApiLogger / DefenderAuditLogger Start=0；SettingsPageVisibility=hide:windowsdefender；HideSystray=1 | 抹掉安全中心入口与日志 |
| A05 Defender 开机自愈任务（3 条） | custom.yml:221,235,242 | 生成 `%SystemRoot%\XOS-DD.ps1` + `schtasks /sc ONSTART /tn XOS-DefenderDisable` + 禁 Defender 计划任务 | 重启后自动重关，用户无法自行恢复 |
| A06 OneDrive 移除（7 条） | custom.yml:59,60,68-72 | onedrive.bat + 删 Appx/Provisioned + 删 CLSID NameSpace（HKLM 与每用户） | 删组件 |
| A07 遥测/诊断数据全关（31 条） | custom.yml:481-508,550-552 | AllowTelemetry=0、AllowDeviceNameInTelemetry=0、DisableOneSettingsDownloads=1、WER Disabled / DisableArchive / DisableWerUpload、setx *_TELEMETRY_OPTOUT | 「全关遥测」按铁律属破坏性；WER 全关后没有崩溃转储 |
| A08 AI / Recall / Copilot 移除（10 条） | custom.yml:509-515,523,537,538 | DisableAIDataAnalysis、TurnOffWindowsCopilot、AllowRecallEnablement=0、ShowCopilotButton=0、WidgetsPolicy.ps1 | 功能删除（remove-ai） |
| A09 输入个性化/墨迹/手写/语音数据（13 条） | custom.yml:516-519,522,524,532-536,548,549 | AllowInputPersonalization=0、RestrictImplicitInkCollection=1、TIPC Enabled=0、HasAccepted=0、HarvestContacts=0 | 隐私类关闭，非性能项 |
| A10 广告 ID / 推荐内容 / 活动历史 / 位置 / 查找设备 / 地图（17 条） | custom.yml:520,521,526-531,539-547 | AdvertisingInfo Enabled=0、SubscribedContent-*=0、ContentDeliveryAllowed=0、EnableActivityFeed / PublishUserActivities / UploadUserActivities=0、AllowFindMyDevice=0、Maps AllowUntriggered*=0 | 功能删除，收益不可测 |
| A11 设置同步 / 跨设备全关（22 条） | custom.yml:555-576 | SettingSync 22 项（DisableSettingSync=2、SyncPolicy=5、各组 *SettingSync=2/1） | 删云同步能力 |
| A12 Cortana / 云搜索 / 网络搜索全关（27 条） | custom.yml:579-590,592-606 | CortanaEnabled=0、AllowCortana=0、AllowCloudSearch=0、BingSearchEnabled=0、ConnectedSearchUseWeb=0、DisableSearchBoxSuggestions=1 | 功能删除（搜索仍在，只是没有网络结果） |
| A13 Windows Update 关闭 / 版本锁定 / 驱动更新阻断（16 条） | custom.yml:615,653-662,668,669,677,678,988 | NoAutoUpdate=1、DisableDualScan=1、ExcludeWUDriversInQualityUpdate=1、SearchOrderConfig=0、DontSearchWindowsUpdate=1、DisableOSUpgrade=1、TargetReleaseVersionInfo=当前版本 | 停止安全更新；TargetReleaseVersionInfo 把功能更新钉死在当前版本 |
| A14 删除 Update Health Tools（1 条） | custom.yml:686 → UPDHEALTH.bat | UPDHEALTH.bat | 删系统健康组件 |
| A15 Hyper-V / 打印等可选功能删除（2 条） | custom.yml:689,694 → OptionalFeatures.ps1:28-35 | Disable-WindowsOptionalFeature：Microsoft-Hyper-V-*(7 项)、SMBDirect、MSRDC、Workfolders、WCF*、Printing-*（disable-printing 分支） | 删 Hyper-V 会连带 WSL2/VM/VBS/沙盒不可用 |
| A16 批量禁用服务（38 条） | custom.yml:706-711,714,716-718,720,721,724,726,728-730,732-746,765-770 | （不含已覆盖的 10 个同名服务）diagnosticshub / MapsBroker / CSC / CSCSERVICE / Telemetry / diagtrack / wercplsupport / GraphicsPerfSvc / Ndu / DSSvc / InventorySvc / amdfendr* / McpManagementService / TermService / UmRdpService / SessionEnv / gencounter / hyper* / vmgid / vid / dam / GpuEnergyDrv / UCPD / MSDTC / midisrv / bam | 无差别批量禁服务，含 RDP（TermService/UmRdpService/SessionEnv）；本仓只禁 30 个白名单服务 |
| A17 阻止应用自动安装 / 推荐内容（14 条） | custom.yml:783-796 | SilentInstalledAppsEnabled=0、PreInstalledAppsEnabled=0、OemPreInstalledAppsEnabled=0、RotatingLockScreen*=0、SubscribedContent-* | 消费级内容全关 |
| A18 GameBar 残余 + IFEO 劫持（11 条） | custom.yml:801,804,805,807-814 | ShowStartupPanel=0、AudioCapture/CursorCapture=0、AllowGameDVR=0、7 个 IFEO Debugger→systray.exe | IFEO 劫持进程启动，属 hack 写法 |
| A19 CEIP / SQM 关闭（4 条） | custom.yml:826-829 | CEIPEnable=0、UploadDisableFlag=1、NoCloudApplicationNotification=1 | 遥测类，随 A07 |
| A20 禁用 ACPI / HPET / AMD Crash Defender 设备（1 条） | custom.yml:876 | Win32_PnPEntity Disable()：ACPI Processor Aggregator、ACPI Wake Alarm、AMD Crash Defender、High Precision Event Timer、Intel PMT | 禁 HPET/ACPI 可致计时异常；AMD Crash Defender 是防崩驱动 |
| A21 关闭全部事件通道（1 条） | custom.yml:905 | 遍历 `WINEVT\Channels`，把所有 Enabled=1 的通道写 0 | 排障证据归零 |
| A22 laptop-desktop.bat 整包（1 条） | custom.yml:953 → laptop-desktop.bat（子项见 3.1.1） | 电源计划/超时/设备节能/服务/内存压缩/诊断通道等 18 组 | 内含禁用 acpiex/Cmbatt 等危险动作 |
| A23 计划任务批量禁用（117 条）+ 更新编排删除（5 条） | custom.yml:983-987 → DisableScheduledTasks.ps1:12-136 | Core 104 / AI 5 / Printing 3 / Defender 5 + 删 UScheduler_Oobe\OutlookUpdate、DevHomeUpdate | 含 WindowsUpdate / UpdateOrchestrator / WaaSMedic / Data Integrity Scan |
| A24 移除 PC Health Check（1 条） | custom.yml:1004 → PCHealthCheck.ps1 | PCHealthCheck.ps1 | 删组件 |
| A25 Appx 批量卸载（82 + WSL/AI/Edge/Teams/OneDrive）（17 条） | custom.yml:1007-1009,1096,1122,1128-1130,1138,1143,1157,1169,1182,1195,1207,1222,1228 | RemoveAppx 78 项（:1014-1092）+ 4 项（:1100-1105）+ WSL / AI / Edge / Teams / OneDrive + Outlook 快捷方式 | 批量删应用 |
| A26 Photos 移除 + 关联重建（5 条） | custom.yml:1236,1245,1262,1278,1286 | 删 Photos Appx + 重建 PhotoViewer.FileAssoc / OpenWithProgids（5 段脚本） | 删组件（默认勾选） |
| A27 Xbox 应用移除（1 条） | custom.yml:1294 | 7 个 xbox appx（默认不勾选） | 删组件 |
| A28 SecHealthUI 清缓存并重注册（4 条） | custom.yml:701,702,1312,1313 | Deprovisioned 键删除 + appx clearCache + Add-AppxPackage -Register | 配合 Defender 拆除 |
| A29 禁用 CBS 后台组件（1 条） | custom.yml:1324 | BackgroundAccessApplications\MicrosoftWindows.Client.CBS Disabled=1 | 禁后台组件 |
| A30 阻断 DeviceCensus / 跨设备续传（4 条） | custom.yml:1385,1408-1410 | DisallowRun 加 DeviceCensus.exe + IFEO Debugger=taskkill + DisableCrossDeviceResume=1 | IFEO 劫持 + 功能删除 |
| A31 Edge 全量移除（95 条） | custom.yml:19,1422-1426,1442-1460,1468,1475-1538,1549-1553 | 4 个 taskkill、RemoveEdge.ps1（SpoofRegion/BlockUpdater）、EdgeUpdate 13 项策略、9 个文件删除、34 个键删除、7 个 OpenWithProgIds 删值 | 删浏览器（默认勾选 remove-edge）；含地区伪装 |
| A32 PendingFileRenameOperations 强删组件目录（5 条） | custom.yml:1579,1604,1626,1650,1675 | 5 段脚本把 WindowsApps 下 HEVC / Solitaire / Terminal / Skype / Widgets / WSL / Teams / Edge / StartMenu 目录塞进待删队列 | 开机前强删，不可回滚 |
| A33 删 Edge 开机自启（1 条） | custom.yml:1740 → RemoveEdgeStartup.ps1 | RemoveEdgeStartup.ps1 | 随 Edge 移除 |
| A34 Win10 新闻和兴趣开机脚本（1 条） | custom.yml:969 | feeds-home.bat 复制到 Startup（含 Default 用户） | 启动项注入 + 功能删除 |
| A16b 把 bam（后台活动管理器）改为手动启动（1 条） | custom.yml:952 → laptop-desktop.bat:123 先禁后改 | `HKLM\SYSTEM\CurrentControlSet\Services\bam` 的 `Start`：脚本里置 4（禁用），随后这一行改回 3（手动） | 自相矛盾：同一 playbook 内先禁后改，说明上游对 bam 的处理没有定论；本仓不碰 bam |
| A35 关闭系统预留存储（Reserved Storage）（1 条） | custom.yml:779-780 → Executables/ReservedStorage.ps1 | `dism /Online /Set-ReservedStorageState /State:Disabled`；失败则把脚本复制到 `%SystemRoot%\XOS-RS.ps1` 并建 ONSTART 计划任务 `XOS-ReservedStorage`（SYSTEM + ExecutionPolicy Bypass），每次启动重试 10×60s、最多 5 次启动 | **A 破坏面**：Reserved Storage 是功能更新/组件安装的空间保障，关掉后更新易因空间不足失败；且用开机自愈任务 + 落盘脚本，失败时 `XOS-RS.ps1` 与计划任务会留在系统里（无卸载路径） |


#### 3.1.1 A22 内部拆解：`Executables/laptop-desktop.bat`（custom.yml:953 这 1 条 run 动作）

> 下表是脚本内部子项，**计数已归入 A22 的 1 条**，不重复计入总数。


| 子项 | 位置 | 具体内容 | 判定 |
|---|---|---|---|
| 电源计划导入 + 设为活动 | laptop-desktop.bat:62,92（→ ApplyPowerPlan.bat） | 导入 GUID `31693169-3169-3169-3169-316931693169` 的 XOS 计划 | D：本仓 Power.ps1 用系统自带「卓越性能」，不引入第三方 GUID 计划 |
| 桌面超时全 0 | laptop-desktop.bat:63-68,88-91 | VIDEOIDLE / STANDBYIDLE / HIBERNATEIDLE 的 AC+DC 全 0 | D：使用习惯，不是性能项 |
| 关闭休眠 | laptop-desktop.bat:87 | `powercfg -h off` | 已覆盖：Hibernate.ps1 同功能（可选 + 可恢复 hiberfil） |
| 禁用动态 tick | laptop-desktop.bat:86 | `bcdedit /set disabledynamictick yes` | 已覆盖：Bcd.ps1:47（可选模块，带 BCD 快照） |
| 全设备节能值清零 | laptop-desktop.bat:69-85 | 遍历 `Enum`，把 EnhancedPowerManagementEnabled / AllowIdleIrpInD3 / EnableSelectiveSuspend / WdfDirectedPowerTransitionEnable / IdleInWorkingState 等 12 个值写 0，并生成 restore 脚本 | 部分采纳：本轮「网卡/PCI/USB 节能关闭」覆盖同类目标，但只改已存在值 + 先快照；上游是 Enum 全量扫（含未知设备） |
| 核心停车 / 处理器性能 | laptop-desktop.bat:96-117 | 4 个 PowerSettings GUID 的 Attributes=2 解锁 + 值写 100/0 | D：核心停车 100% 抬高待机功耗与温度，收益不可测 |
| 禁用 Cmbatt / acpiex / acpipagr / acpipmi / acpitime / bam | laptop-desktop.bat:118-123 | `Start=4` 写 6 个服务/驱动 | **A 高危**：`acpiex` 是 ACPI 扩展驱动（Boot 级），置 4 极可能直接无法启动；`bam` 随后又被 custom.yml:952 改回 3，自相矛盾 |
| EnergyEstimationEnabled=0 | laptop-desktop.bat:124 | `Control\Power` | E 未选（候选③，桌面门禁、默认不勾） |
| PowerThrottlingOff=1 | laptop-desktop.bat:125（笔记本分支 :168 写回 0） | `Control\Power\PowerThrottling` | E 未选（候选③）；只在台式分支生效，行为不一致 |
| USBHUB3 / usbccgp / pci 节能参数 | laptop-desktop.bat:133-139 | DisableLPM / D3ColdSupported / Ceip / DisableSelectiveSuspendUI | 部分采纳：本轮已覆盖 USB/PCI 节能；上游笔记本分支又 delete 这些值（:169-171），逻辑割裂 |
| 关闭移动中心 | laptop-desktop.bat:140 | `Policies\MobilityCenter\NoMobilityCenter=1` | D：无性能依据 |
| Teredo 低功耗关闭 | laptop-desktop.bat:141 | `iphlpsvc\Teredo\AllowLowPowerMode=0` | D：无据 |
| 关闭 3 个电源诊断通道 | laptop-desktop.bat:142-144 | `wevtutil sl ... /e:false`：SleepStudy、Kernel-Processor-Power、UserModePowerService | D：关日志不提升性能，抹掉排障证据 |
| 存储空闲超时 | laptop-desktop.bat:145-147 | `0012ee47...\0b2d69d7...` 写 0 | D：与 Nvme.ps1 的电源策略模块重复且更粗暴 |
| 关内存压缩 | laptop-desktop.bat:149 | `Disable-MMAgent -MemoryCompression` | 已覆盖：Registry.ps1:121-133（带 Verify） |
| 全设备 MSPower_DeviceEnable=false | laptop-desktop.bat:150 | WMI `root\wmi` 批量关设备节能 | D：与本轮「只改已存在注册表值 + 回滚」口径冲突，WMI 批量改无快照 |
| InsightsEnabled=0 | laptop-desktop.bat:151 | 遍历 HKU 写输入洞察 | D：隐私项，非性能 |
| 桌面右键电源计划菜单 | laptop-desktop.bat:9-28,126-132 | 写 `HKCR\DesktopBackground\Shell\PowerPlan` 五级菜单 | C 范围外：UI 定制 |
| 笔记本分支恢复逻辑 | laptop-desktop.bat:157-180 | 恢复超时 / 服务 / PowerThrottlingOff=0 / 删 USB 参数 | C：上游自己也知道要回滚，但只对笔记本做 |


### 3.2 B. 安全削弱（27 条）

> **2026-11-20 增补（用户拍板）：本组 27 条已全部吸纳，落地为菜单 20「安全削弱」。**
> 实现：`Modules/SecurityWeakening.ps1`（13 个独立项 B01–B13 的写入表与执行器）+ `Modules/Backup.SecurityWeakening.ps1`（逐值快照、进程缓解 XML 快照与恢复）。
> 约束：默认什么都不做；每项单独执行；逐项 `I-UNDERSTAND-RISK`（B13 另用 `I-UNDERSTAND-MITIGATIONS-OFF`）；写入前落 `security-weakening-backup.json`，可整体恢复。
> 下表保留审计当时的「未采纳原因」作为风险记录，落地位置与取舍见 3.2.1。


| 项目/值 | 位置(file:line) | 具体内容 | 未采纳原因 |
|---|---|---|---|
| TamperProtection = 0（1 条） | custom.yml:82 | XSudo/TrustedInstaller 改 `HKLM\SOFTWARE\Microsoft\Windows Defender\Features` | 关防篡改后 Defender 可被任意改写；本仓 Defender 模块从不关 TamperProtection |
| CI Policy VerifiedAndReputablePolicyState = 0（1 条） | custom.yml:160 | `HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy` | 关代码完整性 / 信誉策略 |
| HVCI / SystemGuard 关闭（3 条） | custom.yml:183-185 | HypervisorEnforcedCodeIntegrity\Enabled=0、DeviceGuard\ConfigureSystemGuardLaunch=2、Scenarios\SystemGuard\Enabled=0 | 关虚拟化安全（VBS/HVCI）；本仓 Virtualization.ps1 是带 SecConfig.efi 哈希校验的正规模块，不会静默关 |
| 保留 Defender 时仍关云保护/上报（8 条） | custom.yml:251-256,299,300 | SubmitSamplesConsent=0、SpyNetReporting=0、DefenderApiLogger / AuditLogger Start=0、DisableGenericRePorts=1、DisableScheduledSignatureUpdateOnBattery=1、ConfigureAppInstallControl=Anywhere | 即使用户选 Keep Defender，样本上报与云保护仍被削弱 |
| UAC 关闭（3 条） | custom.yml:307-309 | EnableLUA=0、PromptOnSecureDesktop=0、ConsentPromptBehaviorAdmin=0（playbook.conf:47 自注 "may break Microsoft login"） | 关 UAC = 进程默认管理员全权；上游自己标注会破坏微软账号登录 |
| ValidateAdminCodeSignatures = 0（1 条） | custom.yml:310 | `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System` | 允许未签名管理代码运行 |
| FeatureSettingsOverride / Mask = 3（2 条） | custom.yml:321,322 | Session Manager\Memory Management 两值同时写 3 | 关 CPU 侧信道缓解；本仓 Registry.ps1:221-226 有同名开关但强制高危确认 + 快照 |
| EnableSvchostMitigationPolicy = 0（1 条） | custom.yml:331 | `HKLM\SYSTEM\CurrentControlSet\Control\SCMConfig` | 关 svchost 的缓解策略（CFG 等） |
| KeyGuard DisableTelemetry = 1（1 条） | custom.yml:376 | DeviceGuard\Scenarios\KeyGuard | 弱化该安全场景可观测性 |
| PowerShell Unrestricted + 关脚本审计（3 条） | custom.yml:467-469 | ExecutionPolicy=Unrestricted、ModuleLogging=0、ScriptBlockLogging=0 | 无策略限制 + 抹掉脚本审计痕迹 |
| ProtectedEventLogging = 0（1 条） | custom.yml:525 | Policies\Microsoft\Windows\EventLog\ProtectedEventLogging | 关受保护事件日志 |
| DMA Remapping 关闭（1 条） | custom.yml:840 | DmaGuard\DeviceEnumerationPolicy 写 value=2 + 遍历所有服务 Parameters 写 DmaRemappingCompatible=0（跳过网卡） | 关内核 DMA 保护（KDP）；上游另建 XOSToolkit\DmaRemappingBackup，说明自知风险 |
| 关全部进程缓解 + MitigationOptions=0x22（1 条） | custom.yml:926 | Set-ProcessMitigation -SYSTEM -Disable 全部；对 fontdrvhost / dwm / lsass / svchost / WmiPrvSE / winlogon / csrss / ntoskrnl / services 与 kernel 写 MitigationOptions / MitigationAuditOptions = 0x22 | 系统性关 CFG/EAF/ACG，lsass 也在名单内；全清单最严重一处 |


#### 3.2.1 菜单 20 落地映射（2026-11-20）

| 上游 B 组行 | 动作数 | 菜单 20 | 落地内容与取舍 |
|---|---:|---|---|
| TamperProtection = 0 | 1 | B01 | 写 `HKLM\SOFTWARE\Microsoft\Windows Defender\Features\TamperProtection=0`；该键受 TrustedInstaller 保护，写入失败如实报错，不做提权绕过 |
| CI 信誉策略 | 1 | B02 | `Control\CI\Policy\VerifiedAndReputablePolicyState=0` |
| HVCI / SystemGuard（3） | 3 | B03（2）+ 菜单 10（1） | SystemGuard 的 `ConfigureSystemGuardLaunch=2` 与 `Scenarios\SystemGuard\Enabled=0` 由 B03 写；`HypervisorEnforcedCodeIntegrity\Enabled=0` 已由菜单 10 的 `vbs-backup.json` 管理，不重复写，避免两份快照争同一值 |
| 保留 Defender 仍关云保护/上报（8） | 8 | B04（10 个值） | 运行时与策略两条 Spynet 路径都写；`DefenderApiLogger`/`DefenderAuditLogger` 的 `Start` 写 **4（Disabled）** —— 上游写 0 是 boot-start，达不到关闭目的，且服务键不存在时跳过（不凭空创建服务项）；`ConfigureAppInstallControl` 同时写 Enabled=0 与 `Anywhere` |
| UAC 关闭（3） | 3 | B05 | 三条全写，`EnableLUA` 放最后，前面失败不会留下“安全桌面已关但 UAC 还在”的半状态 |
| ValidateAdminCodeSignatures=0 | 1 | B06 | 同名同值 |
| FeatureSettingsOverride / Mask = 3 | 2 | B07（参考） | 已由菜单 1 → 3 提供，带 `security-mitigation-backup.json` 与回读；菜单 20 只显示状态与跳转，不重复写 |
| EnableSvchostMitigationPolicy=0 | 1 | B08 | `Control\SCMConfig` |
| KeyGuard DisableTelemetry=1 | 1 | B09 | `DeviceGuard\Scenarios\KeyGuard` |
| PowerShell Unrestricted + 关审计（3） | 3 | B10（4 个值） | 机器策略与本地机器两处 `ExecutionPolicy=Unrestricted`；关 `EnableModuleLogging` / `EnableScriptBlockLogging` |
| ProtectedEventLogging=0 | 1 | B11 | 值名按 ADMX 为 `EnableProtectedEventLogging`（上游写的 `ProtectedEventLogging` 不是策略值名） |
| DMA Remapping 关闭 | 1 | B12 | 用文档化策略键 `Software\Policies\Microsoft\Windows\Kernel DMA Protection\DeviceEnumerationPolicy=2`；服务侧只把已存在的 `DmaRemappingCompatible` REG_DWORD 改 0，非 DWORD 记 skip（不硬改类型） |
| 进程缓解全关 + MitigationOptions=0x22 | 1 | B13 | 系统级用 `Set-ProcessMitigation -System -Disable`（DEP/SEHOP/CFG/ACG 等 14 项）并回读 DEP=OFF；逐进程按上游 9 个镜像写 `MitigationOptions`/`MitigationAuditOptions=0x22`；快照存 `Get-ProcessMitigation -RegistryConfigFilePath` 的完整 XML，恢复走 `Set-ProcessMitigation -PolicyFilePath` |

**口径**：上游 27 条动作 → 13 个可执行项（B07 为参考、B03 部分由菜单 10 覆盖）。写入目标合并去重后由同一份计划同时喂给快照与应用，保证“快照覆盖范围 = 实际写入范围”。

**已知风险（不因落地而消失）**：B05 关 UAC 后微软账号登录可能失效；B13 关闭的是系统级 DEP/ASLR/CFG/SEHOP 与 lsass 等关键进程的缓解，属于本清单最严重的一处；B12 只对物理接触者有效，但会关闭 Thunderbolt/PCIe DMA 防护。以上均由逐项确认与快照回滚兜底，不做默认开启。

### 3.3 C. 范围外（123 条）

> 判据：品牌 OEM、壁纸、AME Wizard 机制、安装/维护流程、UI 个性化。**不是"坏"，而是不该进调优清单。**


| 项目/值 | 位置(file:line) | 具体内容 | 未采纳原因 |
|---|---|---|---|
| writeStatus 进度提示（59 条） | custom.yml:3,8,41,58,81,85,116,123,137,195,220,241,244,250,303,312,346,375,412,456,460,466,480,554,578,614,685,688,696,700,704,772,779,782,798,822,825,831,839,875,893,904,926,944,956,960,982,1000,1003,1006,1421,1555,1575,1578,1693,1696,1727,1739,1742 | 全部是 AME Wizard 的进度文案（含 dev 新增的 Disabling Reserved Storage） | 无任何系统改动；AME 机制，不入调优清单 |
| AME 机制脚本（6 条） | custom.yml:4-7,21,24 | InstallDiagnostics.ps1 -Phase Start、StockValueCapture.ps1、XOSToolkit\StockHardware 删值、`xcopy "Windows" "%windir%"`（覆盖系统文件）、DeviceStateBackup.ps1 | AME 打包/还原机制，不是调优项；xcopy 覆盖 windir 属危险但为运行前提 |
| 结束冲突进程（10 条） | custom.yml:9-18 | taskKill explorer / ShellExperienceHost / StartMenuExperienceHost / SearchApp / SearchHost / SearchUI / RuntimeBroker / TextInputHost / backgroundTaskHost / Widgets | AME 应用前常规清场，非调优 |
| OEM 品牌信息 + 壁纸（4 条） | custom.yml:34,35,37,38 | OEMInformation Manufacturer=XOS、SupportURL=github.com/imribiy/XOS、SetWallpaper.ps1 桌面/锁屏 | 品牌 OEM 与壁纸，明确范围外 |
| 视觉 / 任务栏偏好（9 条） | custom.yml:42-48,50,55 | ShowTaskViewButton=0、TaskbarMn=0、Hidden=1、HideFileExt=0、SearchboxTaskbarMode=1、深色主题、ShowRecommendations=0、重启 explorer | UI 个性化偏好（EnableTransparency=0 已单列采纳） |
| UAC 默认分支（3 条） | custom.yml:304-306 | EnableLUA=1、PromptOnSecureDesktop=1、ConsentPromptBehaviorAdmin=5 | playbook.conf:40 默认就是 enable-uac，这三条只是保持默认 |
| Defender 恢复脚本（1 条） | custom.yml:257 | enable-defender 分支：OFFmeansOFF.exe 改回 MpCmdRun.exe + 删 DisableAntiSpyware 等值 | 属撤销上游自己破坏的补偿逻辑，不是调优项 |
| PowerShell 文件关联修复（9 条） | custom.yml:470-478 | ftype + HKCR\Microsoft.PowerShellScript.1\Shell(\RunAs)\Command + .psm1 关联 + 两个 OpenWithProgids 建键 | 修复 AME 精简后丢失的 .ps1 关联，安装流程维护 |
| 启动菜单 / 卷标 / BCD 描述（4 条） | custom.yml:834-837 | bootmenupolicy legacy、timeout 10、`label %SystemDrive% XOS`、bcdedit description "XOS-Playbook-V0.816" | 品牌与开机菜单外观；legacy 菜单还关掉新版启动 UI |
| 事件通道备份（1 条） | custom.yml:903 | EventChannelBackup.ps1 | 为 A21（关全部通道）做备份的机制脚本 |
| XOS Toolkit 安装（2 条） | custom.yml:945,949 | taskkill XOS-CpuService.exe + 静默安装 XOS-Toolkit-Setup.exe | 安装自家配套工具，范围外 |
| 版本检测（1 条） | custom.yml:980 | detect-windows-build.ps1 | 按版本分发的机制脚本 |
| WinX 开始菜单定制（1 条） | custom.yml:1108 | 改 Users\*\WinX\Group3：删 Terminal 项、重建 PowerShell/CMD 快捷方式并改 lnk 字节 0x15 | 开始菜单定制，范围外 |
| 快捷方式清理（2 条） | custom.yml:1220,1221 | 删 `Outlook (new).lnk` / `Outlook.lnk` | 任务栏清理，范围外 |
| TakeOwnership / XSudo 右键菜单（4 条） | custom.yml:1336,1337,1349,1369 | 导入 TakeOwnership.reg、写 AppliesTo、清旧 RunAsTI、`XSudo --ContextMenu=On` 注册 7 类文件右键 | 第三方工具集成，范围外 |
| 开始菜单脚本注入（3 条） | custom.yml:1568,1569,1576 | W10STARTMENU.ps1 / W11STARTMENU.ps1 / 把 taskbar.bat 复制到 Startup | 开始菜单与任务栏定制（含启动项注入） |
| 时间同步重配（1 条） | custom.yml:1694 | `w32tm /unregister` + 换 NTP 池 + `/reliable:yes` | 维护动作；对游戏无收益，且 /reliable:yes 改变域环境时间层级 |
| 默认用户配置预写（1 条） | custom.yml:1697 | 挂载 Default\NTUSER.DAT 写 10 个值（ToastEnabled、Clipboard、GameBar、GameDVR） | 「新账户默认值」机制；GameBar/GameDVR 部分与已采纳项重复 |
| 收尾清理（2 条） | custom.yml:1743,1750 | 清 TEMP / Windows\Temp + `wevtutil cl` 清空所有事件日志 + InstallDiagnostics Finish | 维护流程；清空全部事件日志（叠加 A21 后几乎无日志） |


### 3.4 D. 无依据/重复/无效（191 条，含写法错误）

> 这一组是"看着像调优但抄了没用"的部分。**三条硬错误**见本节末，其中两条建议反馈上游。


| 项目/值 | 位置(file:line) | 具体内容 | 未采纳原因 |
|---|---|---|---|
| 电源超时全 0（1 条） | custom.yml:26 | `powercfg /x monitor-timeout-ac 0` / disk / standby / hibernate | 使用习惯，不是性能项；本仓 Power 模块不碰超时 |
| Shell Extensions Blocked 两个未知 CLSID（4 条） | custom.yml:51-54 | `{e2bf9676-5f8f-435c-97eb-11607a5bedf7}`、`{596AB062-B4D2-4215-9F74-E9109B0A8153}` 写空串，HKLM + WOW6432Node 各 2 条 | 两个 CLSID 未注明来源与对应组件，属黑盒屏蔽第三方 shell 扩展 |
| Kernel / 内存 玄学值（21 条） | custom.yml:313,315,316,318,324,326-330,332-339,341,343,344 | `DesktopHeapLogging=0`、**`NetworkThrottlingIndex=10`（写的是默认值，等于没关；本仓 Registry.ps1:85 用 0xFFFFFFFF）**、`Psched\TimerResolution=10`、`SvcHostSplitThresholdInKB=3670016`、**`Segment Heap=1`（值名含空格，系统不识别；正确名 SegmentHeap）**、`BackgroundLoadKnownDlls=1`、`BootExecuteNoPnpSync=1`、`TaskhostTimeout=2000`、`EnableCpuQuota=0`、`ParallelFiringTimeoutEnabled=1`、`AudioHealthMonitorLimit=0`、`ComServerShutdownDelayMs=1000`、`DelayedDesktopSwitchTimeout=0`、`RunLogonScriptSync=0`、`RunStartupScriptSync=0`、`CopyFileBufferedSynchronousIo=1`、`DefaultTriggerCoalescingTime=0`、`SleepStudyDisabled=1`、`TokenLeakDetectDelaySecs=30`、`AllowAutomaticAppArchiving=0`、`NoLazyMode=1` | 三类问题：①写法错误（NetworkThrottlingIndex 写默认值、Segment Heap 值名错位）；②无公开文档依据（BootExecuteNoPnpSync / TaskhostTimeout / Psched\TimerResolution / AudioHealthMonitorLimit 等）；③有依据但收益未量化（SvcHostSplitThresholdInKB 反而扩大单点故障面） |
| 输入 / 触控 / 输入法（27 条） | custom.yml:347-373 | `IsInputAppPreloadEnabled=0`、`BluebirdDTWMultiplier=0`、`DisablePersonalizationGTKM=1`、`AUTOCORRECTIONTRIGGERS=0`、`PERIODSHORTCUT*`、`COMMONEMOJITERMINATORS=0`、CursorMagnetism 三个搜索边界=0；覆盖 Input\Settings / proc_1 / loc_0409 / im_1 四级 | 整块是关输入法自学习/自动更正/emoji 联想，属输入体验裁剪，无帧率收益；写 HKLM 的 proc_1 模板会污染所有输入法配置 |
| 关日志 / ETW（18 条） | custom.yml:377-394 | `CatalogDB\EnablePerformanceCounters=0`、MediaFoundation `CallStackTracingEnabled/Noisy=0`、`Schedule\Configuration\AdapterLoggingEnabled/EnableAt=0`、`SecEdit\PolicyDebugLevel=0`、`GDIEnableReferenceStackTraces=0`、`USERExtraInstrumentations / USERPostMortemLogging=0`、`Winlogon\NoDebugThread=1 / RsopLogging=0`、`UIPI\EnableMessageSQM=0`、`Lsa\Audit\EtwDirect=0`、`Lsa\Tracing\TracingDisabled=1`、`Wdf\WdfGlobalLogsDisabled / WdfGlobalSleepStudyDisabled=1`、`Diagnostics\Performance\DisableDiagnosticTracing=1` | 关日志不提升帧率，只会让 DPC/驱动问题无法定位；`Lsa\Tracing\TracingDisabled=1` 还削弱审计 |
| Start 追踪 + Explorer 策略（14 条） | custom.yml:396-403,405-410 | 8 个 `Start_Track*`=0、`Start_NotifyNewApps=0`、`NoLowDiskSpaceChecks=1`、`NoNetCrawling=1`、`NoRemoteChangeNotify=1`、`NoRemoteRecursiveEvents=1`、`TurnOffSPIAnimations=1`、`DisableThumbsDBOnNetworkFolders=1` | Start 追踪值是开始菜单遥测计数，收益不可测；`NoRemote*` 只对局域网共享有效 |
| 视觉 / 推送 / 剪贴板 杂项（14 条） | custom.yml:413,415-423,425-428 | `DisableProjectedShadows=1`、`XAML\DisableGlobalAnimations=1`、`DisableLogonBackgroundImage=1`、`PushNotifications\InitializePlatformOnStartup=0`、`ToastEnabled=1`、`AllowClipboardHistory=1`、`ViewHiddenTasks=1`、`PenVisualization=0`、`AutoColorization=0`、`PrintScreenKeyForSnippingEnabled=0`、`Desktop Slideshow\AnimationDuration=0`、`CloudClipboardAutomaticUpload=0`、`CloudClipRDPOverride=0` | 单条都是关动画/关云剪贴板级别的小改动，叠起来也测不出收益；AutoColorization / PrintScreen 属纯偏好（见第 4 节） |
| 输入追踪（HKCU）（3 条） | custom.yml:429-431 | `Microsoft\Input\IsInputAppPreloadEnabled=0`、`Input\Settings\Insights=0`、`UserStatsEnabled=0` | 与 D04 重复（HKLM 已写同一批），HKCU 侧属冗余 |
| 预览窗格 / NoNetCrawling（3 条） | custom.yml:432-434 | `DisablePreviewDesktop=1`、`DisablePreviewWindow=1`、`NoNetCrawling=1` | 关预览窗格是功能裁剪；与 :406 的 HKLM 版重复 |
| HKCU 重复副本（13 条） | custom.yml:435-441,444-449 | `Start_Track*` 7 条 + `NoNetCrawling`、`NoRecentDocsMenu`、`NoRemoteChangeNotify`、`NoRemoteRecursiveEvents`、`NoSMHelp`、`TurnOffSPIAnimations` | 同一批值在 HKLM 已写过（见本表 Start 追踪那行），HKCU 再写一遍只有 `NoRecentDocsMenu` / `NoSMHelp` 是新增；纯重复 |
| Taskbar / BAM / 拼写错值（3 条） | custom.yml:442,443,450 | `TaskbarFlashOverrideBreatheCount=0`、`BamThrottling\DisableWindowHinting=1`、**`HourlyTelemetyThreshold=0`（Telemety 拼写错误，应为 Telemetry）** | 前两条无文档依据；第三条值名拼错，系统不会读，等于无效写入 |
| EdgeUI / ThumbsDB / SkipNetworkShield（4 条） | custom.yml:451-454 | `DisableCharms=1`、`DisableRecentApps=1`（HKCU Policies\EdgeUI）、`DisableThumbsDBOnNetworkFolders=1`、`SkipNetworkShieldCheck=1` | Charms 是 Win8 时代设置，Win10/11 无对象；`SkipNetworkShieldCheck` 无公开语义，名似安全绕过 |
| DNS 负缓存 / BFE 采集（2 条） | custom.yml:457,458 | `DNSClient\MaxNegativeCacheTtl=5`（默认即 5）、`BFE\Parameters\Policy\Options\CollectNetEvents=0` | 前者写默认值等于没改；后者关 BFE 采集，无性能收益 |
| Miracast / WARP（2 条） | custom.yml:462,464 | `MiracastForceDisable=1`、`WarpSupportsResourceResidency=1` | Miracast 关闭是功能裁剪（无线投屏）；WARP 是软件光栅器，对独显无影响 |
| 搜索索引策略（7 条） | custom.yml:591,607-612 | `IsDynamicSearchBoxEnabled=1`、**`Windows Search\SetupCompletedSuccessfully=0`（状态位，置 0 会让搜索重做首次配置）**、`PreventIndexingLowDiskSpaceMB=2048`、`DisableBackoff=0`、`DisableRemovableDriveIndexing=1`、`PreventIndexOnBattery=1`、`PreventIndexingOutlook=1` | 索引裁剪让搜索变慢；`SetupCompletedSuccessfully=0` 是状态位不是开关，属写法错误 |
| Windows Update 周边（12 条） | custom.yml:663-667,670-676 | `PreventDeviceMetadataFromNetwork=1`、`SYSTEM\Maps\AutoUpdateEnabled=0`、`WindowsStore\WindowsUpdate\AutoDownload=2`、`Policies\WindowsStore\AutoDownload=2`、`DODownloadMode=0`、PreviewBuilds 三项=0、`HideInsiderPage=1`、`AllowExperimentation(value)=0` | 多数是关商店自动更新/关预览版，与游戏性能无关 |
| AU 冗余 / HKCU 无效（5 条） | custom.yml:679-683 | `NoAUShutdownOption=1`（HKLM+HKCU）、`AlwaysAutoRebootAtScheduledTime=0`、`AutoInstallMinorUpdates=0`、`UseWUServer=0` | AU 策略只认 HKLM，:680 的 HKCU 那条无效；`UseWUServer=0` 是默认值 |
| FTH 关闭（2 条） | custom.yml:697,698 | `HKLM\SOFTWARE\Microsoft\FTH\Enabled=0` + `rundll32 fthsvc.dll,FthSysprepSpecialize` | **其实是真调优**（Fault Tolerant Heap 是公认卡顿源），本仓未覆盖 → 已移入第 4 节候选，此处仅计数 |
| encryptpagingfile / LongPaths（2 条） | custom.yml:776,777 | `fsutil behavior set encryptpagingfile 0`、`LongPathsEnabled=1` | 前者默认就是 0；后者是开发向的好改动但非游戏性能 → LongPaths 移入第 4 节候选 |
| 删 GameConfigStore 旧值（6 条） | custom.yml:815-820 | delete `GameDVR_DSEBehavior`、`GameDVR_FSEBehavior`、`GameDVR_FSEBehaviorMode`、`GameDVR_DXGIHonorFSEWindowsCompatible`、`GameDVR_EFSEFeatureFlags`、`GameDVR_HonorUserFSEBehaviorMode` | 属清掉旧工具写的值，本身不产生优化；本仓不做全屏优化强制（与 Flip Model 冲突） |
| 后台应用策略（2 条） | custom.yml:1322,1323 | `AppPrivacy\LetAppsRunInBackground=2`、`BackgroundAccessApplications\GlobalUserOverride=1` | 这两条是"允许用户自己控制后台应用"，与 A29 的强制禁用相互矛盾 |
| FeatureManagement override（6 条） | custom.yml:1411-1416 | `Policies\Microsoft\FeatureManagement\Overrides\1387020943=0` + `Control\...\Overrides\8\1387020943` 的 EnabledState / Options / Variant / VariantPayload / Kind | 用未公开 feature ID 硬关功能，无文档、无法验证影响面 |
| 辅助功能 / 关机超时（9 条） | custom.yml:1556-1561,1564-1566 | Narrator `WinEnterLaunchEnabled=0`、StickyKeys Flags=506、Keyboard Response Flags=2、ToggleKeys Flags=34、MouseKeys Flags=130、HighContrast Flags=4194、`HKU\.DEFAULT\Control Panel\Desktop` 三个超时=5000 | 辅助功能 Flags 是关快捷键的偏好；三个关机超时在 Win10/11 默认就是 5000，写默认值等于没改 |
| dontdisplaylastusername=0（2 条） | custom.yml:1571,1572 | `Policies\System` 与 `Policies\Microsoft\Windows\System` 各写 0 | 写的是默认值（显示上次登录用户），无改动效果 |
| SvcHostSplitDisable=1（27 个服务）（1 条） | custom.yml:1728 | 对 BFE / DcomLaunch / mpssvc / PlugPlay / Power / SamSs / EventSystem / CryptSvc / Dhcp / Dnscache / … 写 `SvcHostSplitDisable=1` | 把 27 个关键服务塞回单 svchost，省内存但扩大单点故障与提权面；与 `SvcHostSplitThresholdInKB` 重复 |
| 鼠标加速关闭（3 条） | custom.yml:1381-1383 | `HKCU\Control Panel\Mouse` 的 `MouseSpeed=0`、`MouseThreshold1=0`、`MouseThreshold2=0`（REG_SZ） | **这条是真的、可感知的 FPS 调优**，本仓未覆盖 → 已移入第 4 节候选，此处仅计数 |
| DeliveryOptimization / SettingSync 残留（3 条） | custom.yml:1417-1419 | `HKEY_USERS\S-1-5-20\...\DeliveryOptimization\Settings\DownloadMode=0`、`HKCU\...\DeliveryOptimization\SystemSettingsDownloadMode=0`、`SettingSync\Groups\Language\Enabled=0` | 与 A11（设置同步）及 :673-674（DO 策略）重复 |
| WaitToKillServiceTimeout = 2000（REG_SZ）（1 条） | custom.yml:325 | `HKLM\SYSTEM\CurrentControlSet\Control`，值类型 REG_SZ（默认 5000，REG_SZ） | **可评估但未批准**：把服务停止等待从默认 5000ms 压到 2000ms，能缩短关机/重启时间；代价是服务没写完就被杀，可能丢数据（尤其数据库/同步类服务）。dev 新增项，用户未批准 |
| HiberbootEnabled = 0（快速启动关闭）（1 条） | custom.yml:342 | `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power` | **与本仓模块等价覆盖/冲突**：Hibernate.ps1:243 已能写 `HiberbootEnabled`（Part 14「休眠与快速启动管理」，带 hibernate-backup.json 快照）。本项未采纳；若要做应复用该模块，而不是在 playbook 里无快照硬写 0。dev 新增项，用户未批准 |


**D 组三条硬错误（可复核）**

1. `custom.yml:316` `NetworkThrottlingIndex=10` —— 10 是 Windows 默认值（每毫秒 10 个包），写它等于**没有关闭网络节流**；要关闭应写 `0xFFFFFFFF`（本仓 `Registry.ps1:85` 即如此）。上游「Optimizing Kernel & Memory」这段实际空转。
2. `custom.yml:326` `Session Manager\Segment Heap=1` —— 值名含空格，系统不识别；正确值名是 `SegmentHeap`（这也是「Segment Heap 检测」只做只读、不照抄的原因）。
3. `custom.yml:450` `HourlyTelemetyThreshold=0` —— `Telemety` 拼写错误（应为 `Telemetry`），写入后无人读取。

> 另有 `custom.yml:607` `SetupCompletedSuccessfully=0` 属状态位误当开关；`custom.yml:680` HKCU 下的 AU 策略系统不读；`custom.yml:457`、`custom.yml:1569-1571`、`custom.yml:1576-1577` 都是写默认值。

### 3.5 E. 本轮用户未选（3 条 + 2 项说明）


| 项目/值 | 位置(file:line) | 具体内容 | 状态 |
|---|---|---|---|
| DesktopLivePreviewHoverTime=250 / ThumbnailLivePreviewHoverTime=250（2 条） | custom.yml:395,404 | `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | 本轮未选（候选④「任务栏悬停 250ms」）。技术上有效：把任务栏缩略图预览延迟从默认 400ms 降到 250ms |
| SmoothScroll=0（1 条） | custom.yml:424 | `HKCU\Control Panel\Desktop` | 本轮未选（与候选④同批）。滚动体验偏好，非帧率项 |
| PowerThrottlingOff=1（子项，不单独计数） | laptop-desktop.bat:125（笔记本分支 :168 写回 0） | `HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling` | 本轮未选（候选③，与 `EnergyEstimationEnabled=0` 同批，桌面门禁、默认不勾） |
| Segment Heap 只读检测（未实现，0 条动作） | 上游写法见 custom.yml:326（错误） | 只读检测 `Session Manager\SegmentHeap` 是否存在并报告，不写入 | 本轮未选；上游写法本身错误，不能照抄 |


## 4. 未覆盖但可考虑的候选（本轮新发现）

> 从 D 组里挑出的**真调优项**：有明确系统行为依据、可回滚、与本仓定位（PowerShell 调优工具，带快照与回读）一致。均已用 `rg` 确认本仓无对应写入点（`Modules/` + `tweakbyjie.ps1` 0 命中）。


| 候选 | 上游位置 | 为什么值得做 | 本仓现状与落地建议 |
|---|---|---|---|
| 关闭鼠标加速（MouseSpeed / Threshold1 / Threshold2 = 0） | custom.yml:1381-1383 | FPS 玩家最常用的可感知项：去掉「提高指针精确度」的加速度曲线，指针位移与手移动 1:1。三项都是 HKCU 偏好，改错只影响当前用户 | `rg MouseSpeed / MouseThreshold` 0 命中。建议做成菜单 1 的可选项（HKCU 写入 + 原值快照），提示需重新登录或重启 explorer |
| 关闭 Fault Tolerant Heap（FTH Enabled=0） | custom.yml:697-698 | FTH 会在进程反复崩溃后被强制启用，注入 shim 拖慢启动与运行，是公认的「越用越卡」来源之一 | `rg FTH / fthsvc` 0 命中。建议只写 `HKLM\SOFTWARE\Microsoft\FTH\Enabled=0`（`rundll32 fthsvc.dll,FthSysprepSpecialize` 可省），带原值快照；风险低 |
| LongPathsEnabled=1（长路径支持） | custom.yml:777 | 解除 260 字符路径限制，对开发/大型游戏目录实用，零副作用，微软官方支持 | `rg LongPathsEnabled` 0 命中。属系统能力开关而非性能项，建议放系统行为类，默认不勾选 |
| PrintScreen 直接截屏（PrintScreenKeyForSnippingEnabled=0） | custom.yml:425 | 恢复 PrtSc 直接把全屏放进剪贴板（而不是弹截图工具），做对比图/贴图高频使用 | `rg PrintScreenKeyForSnipping` 0 命中。纯 HKCU 偏好，建议放「可选偏好」 |
| 关闭输入应用预加载（IsInputAppPreloadEnabled=0） | custom.yml:347,429 | 输入法/输入应用预加载会常驻内存；关掉对低内存机器有实际收益，且不影响正常输入 | `rg IsInputAppPreload` 0 命中。建议只写 HKCU 侧（:429），HKLM 侧会影响所有用户 |
| 关闭壁纸主色自动提取（AutoColorization=0） | custom.yml:423 | 换壁纸时系统会算主色并刷新强调色，属一次性卡顿源；关掉后强调色固定 | `rg AutoColorization` 0 命中。收益小但零风险，可并入「视觉」可选组 |


**明确不建议纳入的"疑似候选"**（本轮已核，属无效或负收益）：

- `SvcHostSplitThresholdInKB=3670016`（custom.yml:324）与 `SvcHostSplitDisable=1`（custom.yml:1728）：省内存但扩大单点故障面，与「服务隔离」的现代默认相悖。
- `MiracastForceDisable=1`（custom.yml:462）、`WarpSupportsResourceResidency=1`（custom.yml:464）：前者砍无线投屏，后者对独显无效。
- `DisableProjectedShadows` / `XAML\DisableGlobalAnimations`（custom.yml:413,415）：视觉裁剪，收益不可测且影响观感。
- `NoLazyMode=1`（custom.yml:315）：MMCSS 调度细节，社区争议大，建议只做只读观测，不写值。

## 5. 附：与既有审查的衔接、上游可反馈项、自检

### 5.1 与 `tools/upstream-sources.json` 的 `candidates_pending` 对照

| 既有候选 | 本轮状态 |
|---|---|
| ① 每接口 TcpAckFrequency/TCPNoDelay | **已落地**（本轮，Network.ps1:101） |
| ② 网卡/PCI/USB 节能关闭 | **已落地**（本轮，仅改已存在值 + 先快照） |
| ③ PowerThrottlingOff + EnergyEstimationEnabled=0 | 仍未选（E 组，laptop-desktop.bat:124-125） |
| ④ 任务栏悬停 250ms + SmoothScroll=0 | 仍未选（E 组，custom.yml:395,404,424） |
| ⑤ Segment Heap 只读检测 | 仍未做（上游写法错误，见 D 组硬错误 2） |

### 5.2 本轮结论变化

- **TdrDelay**：由「本仓保留 10、不跟随上游 12」改为**跟随上游取 12**（2026-11-20 用户拍板，待在本仓落改）；已从「未采纳/不跟随」移入第 2 节「已采纳」。
- 其余已采纳机制（TimerCoalescing、PageCombining、DWM 滚轮、MSISupported）在上游仍存在且值一致，无变化。

### 5.3 建议反馈给上游的 3 个问题（只读审计发现，未提 issue）

1. `custom.yml:316` `NetworkThrottlingIndex=10` 写的是默认值，网络节流并未关闭（应为 `0xFFFFFFFF`）。
2. `custom.yml:326` `Segment Heap` 值名含空格，系统不识别（应为 `SegmentHeap`）。
3. `custom.yml:450` `HourlyTelemetyThreshold` 拼写错误（应为 `HourlyTelemetryThreshold`）。
   另有 `Executables/laptop-desktop.bat:118-123` 把 `acpiex` 置 `Start=4`，与 `custom.yml:952` 把 `bam` 改回 `3` 自相矛盾，属高风险误写。

### 5.4 自检

- 动作总数：dev 逐行解析得 **808**；main 804 与预给 10 类统计逐项相等（见 1.1），增量 4 条与 0.1 节一一对应。
- 六组分区：脚本对每条动作求唯一归属，无归属 0 条、重复归属 0 条；六组之和 **808**。
- 注册表：**475** 条全部落组，分布见下表；按功能域合并为 40 余行，每行标注条数与行号范围。
- 基准分支：所有行号均为 **dev @ 0ed60c3**，已用 main→dev 偏移映射逐条校验（每行动作类型一致）。
- 本地证据：所有「已覆盖」给出 `Modules/*.ps1` 行号；候选给出 `rg` 0 命中的检索词。
- 只读：未修改 `xos-playbook` 与 `tweakbyjie` 任何文件，未执行任何 playbook 动作。

| registryValue 归组 | 条数 |
|---|---|
| adopted | 15 |
| destructive | 230 |
| security | 19 |
| out_of_scope | 21 |
| unfounded | 187 |
| unselected | 3 |
| **合计** | 475 |
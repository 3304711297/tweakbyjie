# 隔离 Windows VM 集成验证清单

> 本文只定义验证流程，不在开发机执行。BCD、EFI、Defender、VBS、服务和注册表高权限测试必须在可丢弃的隔离 Windows VM 中完成。

## 0. 安全边界与准备

- 使用 Hyper-V/VMware/VirtualBox 的独立 Windows VM；网络按测试需要最小化，禁止连接生产凭据、公司 VPN 和共享目录。
- 在开始前创建“干净基线”快照，并记录 VM 的 Windows 版本、构建号、UEFI/Legacy 启动模式、BitLocker 状态和管理员账户。
- 为每组测试创建独立检查点；测试失败或恢复不完整时，直接关闭 VM 并回滚检查点，不在故障状态继续执行下一组。
- 开发机禁止执行下列命令：`bcdedit` 写入/删除、`mountvol /s`、`SecConfig.efi` 引导、Defender 删除、VBS/HVCI 关闭、批量服务禁用和生产注册表修改。
- 记录每次运行的脚本版本、Git commit、快照文件内容（脱敏后的 Binding）、命令输出、重启次数和回滚结果。

## 1. 只读基线

1. 运行 `bcdedit /enum {current}`、`bcdedit /enum {bootmgr}`，保存测试相关项：`testsigning`、`debug`、`nointegritychecks`、`hypervisorlaunchtype`、`vsmlaunchtype`、`isolatedcontext`。
2. 保存 VBS/HVCI/Credential Guard 注册表值和 `Get-WindowsOptionalFeature -Online` 的 Hyper-V 状态。
3. 保存受管注册表值、服务启动类型/延迟启动属性、NVMe SafeBoot 项和 MPO 项。
4. 确认 `Get-BackupMachineId` 可运行，记录 Binding 的 64 位散列，不记录原始 MachineGuid。

## 2. BCD 测试模式往返

- 在快照 A 上执行菜单 3；确认 `testmode-backup.json` 写入当前 VM Binding，且备份失败时没有任何 BCD 写入。
- 重启并确认水印/BCD 状态变化；执行菜单 4；确认 `testsigning` 和 `debug` 按备份前 Present/Value 恢复，`nointegritychecks` 不被隐式改写。
- 删除备份文件后只验证明确的降级提示，不把“删除值”当作精确恢复。
- 回滚快照 A，确认测试前后 VM 可启动。

## 3. VBS/Hyper-V 往返

- 在快照 B 上执行菜单 10→1；确认 `vbs-backup.json` 同时包含 5 个注册表值、3 个 BCD 值、3 个功能状态。
- 重启后执行菜单 10→3；确认注册表、BCD 和功能状态恢复到快照前；UEFI 锁定仍明确标注“不在快照范围”。
- 让备份文件 Binding 改成另一台 VM 的散列，确认恢复被拒绝且没有写入。
- 回滚快照 B。

## 4. EFI Device Guard 清理（高风险）

- 仅在禁用 BitLocker 保护、有可用恢复介质且已创建快照的 VM 执行菜单 9→1。
- 检查 EFI 分区挂载盘符、`SecConfig.efi` 的来源哈希、一次性 BCD 项和 boot sequence；任何复制/配置失败都必须清理临时项。
- 重启时记录确认界面、`msinfo32` 的 VBS 状态和引导项是否自动清理。
- 执行菜单 9→2，确认只卸载脚本创建的 EFI 挂载，不影响其他卷；回滚快照并确认 VM 可启动。

## 5. Defender、服务和普通注册表

- Defender：先验证策略快照、机器 Binding 和失败中止，再在快照后执行恢复；不要在连接企业安全管理的 VM 测试。
- 服务：选择至少一个存在服务、一个不存在服务、一个受保护服务，确认停止失败不会声称“已停止”，启动类型恢复仅修改白名单服务。
- 菜单 1：分别验证核心和系统优化的 `registry-backup.json`，包含 DWORD、String、Binary 和原本不存在值；恢复后逐项检查类型和值。
- MPO：验证方案 A/B/C 互斥切换、首次快照保留和无备份时的明确降级提示。

## 6. 跨机器绑定

1. 在 VM-1 生成任一备份并复制到 VM-2。
2. 在 VM-2 尝试恢复，预期 schema 校验失败、失败计数增加、目标注册表/BCD/服务无变化。
3. 在 VM-1 恢复原备份，预期成功。
4. 删除 Binding 字段或填入错误长度/错误散列，预期同样拒绝。

## 7. 通过标准

- 每个测试组均有基线、修改、重启后观察、恢复、二次观察和检查点回滚记录。
- 任何未预期的写入、跨机恢复成功、恢复后类型变化、EFI 残留或 VM 无法启动均判失败。
- 通过标准不是“命令返回 0”，而是状态快照与恢复后状态逐项一致；未覆盖的 UEFI/运行时状态必须在报告中单独列出。

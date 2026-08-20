# 模块化整理路线

## 当前状态（2026-08-20）

已完成第一阶段模块化（详见 `CODE-REFACTOR-STATUS.md`）：

- `Common.ps1` — 通用注册表/BCD/验证/重启
- `Backup.Mpo/Bcd/Service/SecurityMitigation/Nvme` — 5 套备份闭环
- `Menu.ps1` — 菜单调度（`Show-TweakMenu`，11 个 Part）

`tweakbyjie.ps1` 已精简为 81 行 Loader，通过 `. "$PSScriptRoot/Modules/X.ps1"` 点源保持分发兼容。

## 后续方向

### Core（已落地部分）

- 权限检查 — `tweakbyjie.ps1` 头部
- 备份/恢复 — `Backup.*.ps1`（5 套 Schema 校验）
- 环境检测 — `Backup.Nvme.ps1`（`Test-NativeNvme*`）、`Common.ps1`（`Verify-*`）

### 后续 Modules（待增量拆分）

按独立度排序，不影响已发布 Loader：

- Power（Part 7，`powercfg`）
- Bcd（Part 2/3/4）
- Mpo（Part 11）
- Service（Part 6）
- 剩余：Registry(Core Part 1)、Virtualization(Part 9/10)、Defender(Part 5)、Nvme 执行(Part 8)

高风险 `defender-removal.ps1` 保持独立，不纳入 Modules。

### 待补充能力

- 日志统一 — `LOGGING-DESIGN.md` 已规划，暂不替换 `Write-Host`
- 检测只读化 — `DETECTION-MODULE-PLAN.md` 规划的 `已优化/未优化/不适用` 状态机待接入菜单
- 索引化 — `OPTIMIZATION-INDEX-DESIGN.md` 的每项 `分类|状态|模块|文档|恢复` 索引待落地

## 原则

1. 优先兼容已有用户配置。
2. 不改变成熟优化目标。
3. 模块拆分必须可回退（`git checkout` 恢复单文件）。

## youshouldknow 联动

知识库 `项目导航/tweakbyjie-optimization-mapping.md` 与 `tweakbyjie全量执行参考.md` 已与 `Modules/` 结构同步，定位方式改为 `Modules/函数名`，详见 `youshouldknow/项目导航/tweakbyjie关联说明.md`。

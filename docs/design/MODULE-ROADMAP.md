# 模块化整理路线

## 当前状态（2026-08-25，模块化已全部完成）

- `Common.ps1` — 通用注册表/BCD/验证/重启
- `Backup.Mpo/Bcd/Service/SecurityMitigation/Nvme/Defender` — 6 套备份闭环
- `Bcd/Defender/Mpo/Nvme/Power/Registry/Service/Virtualization` — Part 1–11 执行逻辑全部迁出
- `Menu.ps1` — 菜单调度（`Show-TweakMenu`，约 105 行纯调度链）

`tweakbyjie.ps1` 为约 127 行 Loader，通过 `. "$PSScriptRoot/Modules/X.ps1"` 点源全部 16 个模块文件，保持分发兼容。历史基线：2026-08-20 第一阶段为 81 行 Loader + 7 个文件、5 套备份。

## 后续方向

### Core（已落地）

- 权限检查 — `tweakbyjie.ps1` 头部
- 备份/恢复 — `Backup.*.ps1`（6 套 Schema 校验，旁车输入按白名单/固定路径收紧）
- 环境检测 — `Backup.Nvme.ps1`（`Test-NativeNvme*`）、`Common.ps1`（`Verify-*`）
- 退出码 — `Get-TweakExitCode`（0 成功 / 2 参数无效 / 4 全部失败 / 5 部分失败）

### 待补充能力

- 依赖注入适配器 — 将 BCD/注册表/服务/可选功能等外部命令封装为可注入接口，高危路径可无副作用测试
- 日志统一 — `LOGGING-DESIGN.md` 已规划，暂不替换 `Write-Host`
- 检测只读化 — `DETECTION-MODULE-PLAN.md` 规划的 `已优化/未优化/不适用` 状态机待接入菜单
- 索引化 — `OPTIMIZATION-INDEX-DESIGN.md` 的每项 `分类|状态|模块|文档|恢复` 索引待落地

## 原则

1. 优先兼容已有用户配置。
2. 不改变成熟优化目标。
3. 模块拆分必须可回退（`git checkout` 恢复单文件）。

## youshouldknow 联动

知识库 `项目导航/tweakbyjie-optimization-mapping.md` 与 `tweakbyjie全量执行参考.md` 已与 `Modules/` 结构同步，定位方式改为 `Modules/函数名`，详见 `youshouldknow/项目导航/tweakbyjie关联说明.md`。

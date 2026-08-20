# 开发维护说明

## 当前结构（2026-08-20）

`tweakbyjie.ps1`（81 行 Loader）+ `Modules/`（7 个文件）：

| 模块 | 文件 | 职责 |
|---|---|---|
| 通用 | `Common.ps1` | `Convert-RegExePath`/`Set-Reg*`/`Invoke-BcdEdit`/`Verify-*`/`Request-Restart` |
| 备份 | `Backup.Mpo/Bcd/Service/SecurityMitigation/Nvme.ps1` | 5 套 `Test/Ensure/Restore` 闭环 |
| 菜单 | `Menu.ps1` | `Show-TweakMenu`（11 个 Part 调度） |

`defender-removal.ps1`（357 行）保持独立，不参与模块化。

```powershell
# 入口（保持兼容）
powershell -ExecutionPolicy Bypass -File .\tweakbyjie.ps1

# 测试（点源不触发菜单）
. .\tweakbyjie.ps1
```

## 后续维护方向

### 日志统一

`LOGGING-DESIGN.md` 已规划统一 `Write-Log`，当前保持 `Write-Host [OK]/[FAIL]/[SKIP]` 不替换。

### 备份统一

`bcd-backup.json` 等 6 个备份文件继续由 `Backup.*.ps1` 管理，位置保持 `$PSScriptRoot`，不迁移到 `docs/`。后续可考虑集中到 `backup/` 子目录，但需保证旧备份兼容。

### 模块独立

新增功能优先以独立 `Modules/X.ps1` 加入并在 Loader 中点源，避免动 `Menu.ps1` 的 `while` 嵌套。拆分优先级见 `MODULE-ROADMAP.md`。

## 修改原则

- 先文档，后代码
- 先验证（`Parse OK`/`dot-source OK`/`PSScriptAnalyzer 0 Error`），后合并
- 不随意改变已有目标值（如 `Win32PrioritySeparation 38`）
- 高风险项目（Part 5/9 与 `defender-removal.ps1`）保持独立入口
- 行号引用改为 `Modules/函数名` 定位，避免漂移

# 超性能电源计划来源与校验

本文说明 `ultimate-performance.pow` 的来源、用途、校验方法与复现路径，解决二进制文件“无法复现、无法校验”的可追溯性问题。

## 文件信息

| 项目 | 值 |
|---|---|
| 文件 | `ultimate-performance.pow` |
| 大小 | 16384 bytes |
| 方案名称 | `kirby` |
| 基准模板 | Windows 高性能（High Performance）深度调校 |
| 设置总数 | 177 项（`powercfg /query` 完整输出） |
| SHA256 | `2EADB1A9A297C985A79100B1F1DBE994A2639D53C2D6A701CA019E5012868C7B` |
| SHA1 | `59015BD7662A085F0401531F768D3150838CA5AE` |

> 哈希基于仓库当前 `ultimate-performance.pow` 计算，更新文件后请同步更新此处与 `README.md`。

## 来源

该计划由作者在本机通过 `powercfg` 从高性能模板复制并逐项调校后导出，非系统内置方案。调校思路见 [优化详情 - Part 7](./reference/OPTIMIZATION-DETAILS.md#part-7应用超性能电源计划选项-7)。

## 校验

下载后请先校验完整性，再执行 `tweakbyjie.ps1` 的菜单 7：

```powershell
Get-FileHash .\ultimate-performance.pow -Algorithm SHA256
# 预期：2EADB1A9A297C985A79100B1F1DBE994A2639D53C2D6A701CA019E5012868C7B

# 可选：导入后检查方案名称
powercfg /import .\ultimate-performance.pow
powercfg /list
# 应出现 "kirby"，导入后可用 powercfg /delete <GUID> 清理验证导入
```

若哈希不一致，说明文件在传输或存储中被篡改或损坏，请重新下载仓库完整压缩包，不要单独替换单个 `.pow`。

## 导出与复现

如需基于当前系统重新导出或对比现有方案：

```powershell
# 查看当前活动方案
powercfg /getactivescheme

# 导出当前活动方案到文件（替换为实际 GUID）
powercfg /export .\my-export.pow <GUID>

# 导入并对比（导入会返回新 GUID）
powercfg /import .\ultimate-performance.pow
powercfg /query <新GUID> > kirby-query.txt
powercfg /query <当前方案GUID> > current-query.txt
# 对比两个 query 输出即可定位差异项
```

## 使用边界

- 该方案为 CPU 全程满频、升频激进（1% 负载即触发）、禁用节流与多链路节电的取向，适合台式游戏机追求最低延迟。
- 笔记本、电池供电或对功耗/发热敏感的设备不建议长期使用，详见 Part 7 的“整体特征”与代价说明。
- 菜单 7 会先将当前方案导出为 `power-backup.pow`（已存在则不覆盖，保护最初备份），再导入 `.pow` 并激活；导入后方案会被统一改名为 **ultimate-performance**（`kirby` 只是 `.pow` 文件的内嵌名，`powercfg /getactivescheme` 显示的是改名后的名字）；恢复时通过 `7 -> 2` 导入 `power-backup.pow` 并激活。

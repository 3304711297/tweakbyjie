# tweakbyjie 文档导航

## 给使用者

- [项目根目录 README](../README.md)：下载、运行、风险和恢复入口
- [优化详情](./reference/OPTIMIZATION-DETAILS.md)：菜单项目、目标值和执行边界
- [CPU 覆盖状态](./coverage/CPU-COVERAGE-STATUS.md)：tweakbyjie 与 youshouldknow 的 CPU 逐项核对
- [覆盖目录](./coverage/)：跨项目映射、覆盖矩阵和追踪规范

## 给开发者

- [设计文档](./design/)：模块接口、检测、日志、备份、命名和路线图
- 设计文档描述当前规划或实现边界，不是用户运行入口。

## 运行目录约定

PowerShell 主脚本仍在仓库根目录，并通过 `$PSScriptRoot` 读取模块与资源。不要把 `ultimate-performance.pow`、`ViVeTool.exe` 或 `Modules/` 移动到 `docs/`；运行生成的旁车备份文件必须按对应模块提示保管。

## 模块化状态（拆分已完成）

`tweakbyjie.ps1` 已精简为 Loader，功能拆至 `Modules/`：当前共 22 个 `.ps1`（10 个 `Backup.*`、`Common`/`Adapters`、9 个功能脚本、`Menu`；`Bcd.ps1` 同时承载菜单 2/3/4，`GameQos.ps1` 承载菜单 12）。详见 `design/CODE-REFACTOR-STATUS.md`。

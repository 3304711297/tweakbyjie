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

PowerShell 主脚本仍在仓库根目录，并通过 `$PSScriptRoot` 读取/生成旁车文件。不要把 `ultimate-performance.pow`、`ViVeTool.exe`、`Modules/` 或运行后生成的备份文件移动到 `docs/`；它们必须和 `tweakbyjie.ps1` 保持同一运行目录。

## 模块化状态（拆分已完成）

`tweakbyjie.ps1` 已精简为 Loader，功能拆至 `Modules/`：`Common`（含 `Adapters` 可注入副作用边界）+ 8 个 `Backup.*` 备份闭环 + 9 个功能模块（Registry、Bcd、Nvme、Mpo、Service、Power、Virtualization、Defender）+ `Menu` 纯调度链，共 19 个文件。详见 `design/CODE-REFACTOR-STATUS.md`。

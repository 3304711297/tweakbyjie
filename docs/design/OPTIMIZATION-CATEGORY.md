# 优化项目分类索引

用于快速了解 `tweakbyjie` 各功能模块定位。

## 01 核心游戏优化

目标：减少游戏运行时不必要的后台干扰。

包含：
- GameDVR / GameBar 调整
- Multimedia SystemProfile 调度
- Games 任务优先级
- 搜索相关后台行为

## 02 CPU 与系统调度

目标：调整前台程序响应和系统资源分配。

包含：
- Win32PrioritySeparation
- SystemResponsiveness
- CPU 安全缓解配置管理

## 03 GPU 与显示管线

目标：管理 Windows 图形调度相关功能。

包含：
- HAGS
- MPO 独立测试方案
- DWM 相关设置

## 04 存储优化

目标：优化 SSD/NVMe 与文件系统行为。

包含：
- NVMe 驱动配置
- TRIM
- NTFS 参数
- Prefetch 管理

## 05 系统服务与电源

目标：减少不必要后台服务并优化性能模式。

包含：
- 服务启动类型调整
- 超性能电源计划

## 06 高级系统配置

目标：处理测试环境或高级用户配置。

包含：
- BCD 启动参数
- VBS / Hyper-V
- Device Guard

## 使用原则

高风险模块保持独立，不与普通游戏优化混合执行。

详细原理请参考 `youshouldknow`。

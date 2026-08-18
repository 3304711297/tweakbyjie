# Detection Module Plan

## 目标

为 tweakbyjie 增加只读检测能力，让用户在修改前了解当前系统状态。

## 设计原则

- 检测不修改系统
- 检测结果可解释
- 高风险项目明确提示

## 计划模块

### 游戏相关

- GameDVR 状态
- Game Mode 状态
- Multimedia 调度设置

### CPU 与安全

- Win32PrioritySeparation
- 安全缓解状态
- VBS/HVCI 状态

### GPU

- HAGS 状态
- MPO 覆盖状态

### 存储

- NVMe 驱动状态
- TRIM 状态

## 后续实现

优先增加检测函数，再逐步接入菜单显示。

不自动执行修改，避免检测过程改变系统状态。

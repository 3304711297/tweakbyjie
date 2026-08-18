# Detection Function Plan

## 目标

建立统一检测函数，为后续状态检查提供基础。

## 设计原则

- 检测与修改分离
- 只读取当前状态
- 输出可理解结果
- 不自动改变用户配置

## 规划接口

- Registry value check
- Service status check
- BCD configuration check
- Hardware feature check

## 工作流程

检测 -> 展示状态 -> 用户决定 -> 执行修改 -> 生成报告

# CPU 优化覆盖检查

## 目标

确认 tweakbyjie 中 CPU 相关优化是否全部在 youshouldknow 有对应说明。

## 当前检查项目

|编号|项目|执行方向|知识说明状态|
|-|-|-|-|
|CPU-001|Win32PrioritySeparation|线程调度/优先级|检查中|
|CPU-002|Multimedia SystemProfile|多媒体调度|检查中|
|CPU-003|SystemResponsiveness|低优先级任务资源分配|检查中|
|CPU-004|NetworkThrottlingIndex|网络节流机制|检查中|
|CPU-005|Tasks\\Games|游戏任务调度|检查中|

## 检查要求

每个项目需要对应：

- Windows 原理
- 修改目的
- 适用环境
- 潜在影响
- 恢复方式

完成 CPU 类后继续检查 GPU、Memory、Storage 等分类。

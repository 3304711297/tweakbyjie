# youshouldknow Coverage Check

目标：确保 tweakbyjie 中的每一个优化项目都有对应的 youshouldknow 说明。

## 对应原则

```
tweakbyjie 优化项
        ↓
知识说明
        ↓
作用原理 / 适用场景 / 影响 / 恢复方式
```

## 检查分类

- CPU 调度
  - Win32PrioritySeparation
  - Multimedia SystemProfile
  - Games Task

- GPU
  - HAGS
  - MPO / Overlay
  - 图形调度相关设置

- 内存
  - Memory Compression
  - Prefetch

- 存储
  - TRIM
  - NTFS 参数

- 系统安全
  - VBS
  - HVCI
  - 安全缓解相关设置

- 游戏功能
  - GameDVR
  - Game Mode

- 服务
  - 服务状态调整

- 启动配置
  - BCD 参数

## 完成标准

每个 tweakbyjie 项目必须拥有：

1. 原理说明
2. 修改原因
3. 适用环境
4. 潜在影响
5. 恢复方法

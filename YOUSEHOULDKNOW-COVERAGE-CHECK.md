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
  - GPU-001：HAGS（HwSchMode）
  - GPU-002：MPO / Overlay（DisableMPO、OverlayTestMode、DisableOverlays、OverlayMinFPS）
  - DirectX：当前仅作为图形管线背景说明，未发现脚本直接修改项

- 内存
  - MEMORY-001：EnablePrefetcher
  - MEMORY-002：Memory Compression
  - MEMORY-003：虚拟内存/页面文件（当前脚本未执行）

- 存储
  - STORAGE-001：NTFS 8.3
  - STORAGE-002：TRIM
  - STORAGE-003：BITS 启动类型
  - STORAGE-004：Native NVMe Driver
  - STORAGE-005：写入缓存（当前脚本未执行）

- 系统安全
  - SECURITY-001：FeatureSettingsOverride / FeatureSettingsOverrideMask
  - SECURITY-002：VBS / HVCI / Credential Guard / Hyper-V
  - SECURITY-003：Device Guard EFI 锁定清除

- 游戏功能
  - GameDVR
  - Game Mode

- 服务
  - SERVICE-001：Part 6 服务启动类型（37 个目标）
  - SERVICE-002：Part 5 Defender/Security Center 停用

- 启动配置
  - BOOT-001：高级 BCD 计时器
  - BOOT-002：启动安全 BCD
  - BOOT-003：开启测试模式
  - BOOT-004：关闭测试模式
  - BOOT-005：Device Guard EFI 锁定清除
  - BOOT-006：VBS/Hyper-V 启动项

- 注册表
  - Part 1 独立注册表执行项
  - Part 5 Defender/SmartScreen/Security Center 策略
  - defender-removal.ps1 高风险删除项

## 完成标准

每个 tweakbyjie 项目必须拥有：

1. 原理说明
2. 修改原因
3. 适用环境
4. 潜在影响
5. 恢复方法

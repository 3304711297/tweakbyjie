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

以下条目与 youshouldknow 的 `docs/项目导航/tweakbyjie-coverage-manifest.json` 44 个清单项一一对应，编号即清单 ID。

- Core（主注册表执行项）
  - CORE-001：GameDVR AppCaptureEnabled
  - CORE-002：GameDVR_Enabled
  - CORE-003：GameBar Presence ActivationType
  - CORE-004：UseNexusForGameBarEnabled
  - CORE-005：NetworkThrottlingIndex
  - CORE-006：SystemResponsiveness
  - CORE-007：Win32PrioritySeparation
  - CORE-008：HAGS（HwSchMode）
  - CORE-009：Tasks\Games
  - CORE-010：Game Mode
  - CORE-011：Search / Bing / Cortana
  - CORE-012：EnablePrefetcher
  - CORE-013：NtfsDisable8dot3NameCreation
  - CORE-014：Memory Compression
  - CORE-015：TRIM
  - CORE-016：Visual Effects

- CPU 调度
  - CPU-001：Win32PrioritySeparation
  - CPU-002：Multimedia SystemProfile
  - CPU-003：SystemResponsiveness
  - CPU-004：NetworkThrottlingIndex
  - CPU-005：Games Task（Tasks\Games）

- GPU
  - GPU-001：HAGS（HwSchMode）
  - GPU-002：MPO / Overlay（DisableMPO、OverlayTestMode、DisableOverlays、OverlayMinFPS）
  - （非清单项）DirectX：当前仅作为图形管线背景说明，未发现脚本直接修改项

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
  - GameDVR、Game Bar、Game Mode、Games Task 对应 Core 与 CPU 分类中的同名条目，不单独设编号

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

- 电源计划
  - POWER-001：卓越性能电源计划（Ultimate Performance）

- 注册表
  - REGISTRY-001：Defender/安全注册表高风险删除项
  - Part 1 独立注册表执行项（已逐项登记为 CORE 编号）
  - Part 5 Defender/SmartScreen/Security Center 策略
  - defender-removal.ps1 高风险删除项

## 完成标准

每个 tweakbyjie 项目必须拥有：

1. 原理说明
2. 修改原因
3. 适用环境
4. 潜在影响
5. 恢复方法

# tweakbyjie ↔ youshouldknow Coverage Tracker

目标：确保 tweakbyjie 中每一个实际优化项目，都能在 youshouldknow 找到对应说明。

## 覆盖规则

每个优化项需要对应：

- 原理说明
- 修改原因
- 适用环境
- 潜在影响
- 恢复方式

## 初始分类

| 分类 | 优化方向 | 状态 |
| --- | --- | --- |
| CPU | 调度、线程优先级、SystemProfile | ✅ CPU-001 至 CPU-005 已逐项确认；执行备份/验证缺口已标明 |
| GPU | HAGS、MPO、显示相关设置 | ✅ GPU-001/GPU-002 已逐项确认；DirectX 仅作背景说明 |
| Memory | Memory Compression、Prefetch、页面文件边界 | ✅ MEMORY-001/002 已逐项确认；页面文件未由脚本执行 |
| Storage | NVMe、NTFS、TRIM、BITS、写入缓存边界 | ✅ STORAGE-001 至 005 已核对；写入缓存未由脚本执行，部分项目恢复不完整 |
| Security | VBS、HVCI、Device Guard、CPU 安全缓解 | ⚠️ SECURITY-001 已闭环；SECURITY-002/003 有执行与验证但非精确原状态回滚 |
| Service | 服务优化 | ⚠️ 已确认 BITS 等服务项有备份/验证；全量服务逐项说明待继续 |
| Boot | BCD、测试模式、Device Guard EFI、VBS 启动项 | ⚠️ BOOT-001/002 有备份验证；BOOT-003/004/005/006 非精确原状态回滚 |
| Registry | 独立注册表优化项、Defender 删除脚本 | ⚠️ 已确认大量执行项；Part 1/5 多数无统一备份恢复，defender-removal.ps1 明确不可逆 |

## 检查结果格式

- ✅ 已有完整说明
- ⚠️ 有说明但需要补充
- ❌ 缺少说明

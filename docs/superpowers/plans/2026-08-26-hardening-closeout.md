# Hardening Closeout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 完成 tweakbyjie 与 youshouldknow 的发布、供应链、文档、可替换副作用接口与隔离验证收尾，同时不在开发机执行高权限系统修改。

**Architecture:** 先锁定 CI 输入（Action commit、PowerShell 包哈希、Python requirements hashes），再让 ysk 的 build 产物在 deploy 中复用，避免部署阶段二次构建。tweak 的适配器层提供默认真实实现和测试替身，模块通过少量稳定接口访问注册表、BCD、服务/CIM、确认和重启；现有菜单与备份语义保持不变。

**Tech Stack:** GitHub Actions YAML, PowerShell 5.1/7, Pester 6.1, Python pip-tools, MkDocs, lychee.

**Spec:** Existing project security audit memory and current repository workflows.

## Global Constraints

- 不在开发机执行真实 BCD、EFI、Defender、VBS、服务破坏或恢复操作。
- 备份恢复继续强制机器绑定；旧的无 Binding 备份必须拒绝。
- 所有新增副作用接口必须有 Pester 测试替身路径。
- 发布只由 `v*` tag 触发；main push 只做验证。
- CI Action 使用完整 commit SHA；Python/PowerShell 依赖使用版本和 SHA256 锁定。

### Task 1: Finish workflow supply-chain hardening

- Modify tweak `.github/workflows/ci.yml`: tag-only release, SHA-pinned Actions, hash-locked Pester/PSScriptAnalyzer installer.
- Modify ysk `.github/workflows/docs.yml`: SHA-pin Actions, install `requirements-docs.lock.txt` with `--require-hashes`, upload the built site as an artifact, deploy that artifact with `actions/download-artifact` and `ghp-import` rather than rebuilding.
- Modify ysk `lychee.toml`: remove global 403/429 acceptance; add only explicitly documented domains that are known anti-bot endpoints.
- Validate YAML and local lock consistency.

### Task 2: Audit and refresh ysk documentation baselines

- Enumerate every `2026-08-21` occurrence with its document and surrounding claim.
- For claims that are still verified, update the date to `2026-08-26`; for claims not reverified, state that the last verification remains `2026-08-21` instead of silently changing it.
- Re-run MkDocs strict build and front-matter/link checks.

### Task 3: Add replaceable side-effect adapters in tweak

- Add `Modules/Adapters.ps1` with default adapters for registry, BCD, service/CIM, command execution, confirmation, restart, and optional-feature operations.
- Add `Initialize-TweakAdapters` and `Set-TweakAdapters` so tests can inject scriptblock-backed substitutes without changing production defaults.
- Route the highest-risk shared helpers (`Set-Reg*`, `Remove-Reg*`, `Invoke-BcdEdit`, `Request-Restart`, `Test-ConfirmChoice`) through adapters first; preserve current output/counters.
- Add Pester coverage for default wiring and injected adapters.

### Task 4: Produce isolated Windows VM integration verification

- Add `docs/isolated-vm-verification.md` describing snapshot prerequisites, test matrix, expected observations, rollback checkpoints, and explicit prohibition on running destructive cases on the developer workstation.
- Include BCD/test mode, VBS/Hyper-V, EFI, Defender, services, and backup-binding cross-machine cases.

### Task 5: Full verification and integration

- Run tweak Pester and coverage audit; run ysk strict build/front-matter/link checks.
- Update `knowledge.lock.json` only if ysk commits changed, then verify lock consistency.
- Commit each repository with Chinese conventional messages, push, and inspect CI/release outcomes.

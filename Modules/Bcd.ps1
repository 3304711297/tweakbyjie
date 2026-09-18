# Bcd.ps1 - Part 2 高级 BCD / Part 3 开启测试模式 / Part 4 关闭测试模式
# 被 tweakbyjie.ps1 点源加载，共享 $script:ok/$fail/$skip/$rebootRequired

function Invoke-BcdAdvancedModule {
    param([string]$Action = '')

    Write-Host ""; Write-Host "============ [Part 2] 高级 BCD / Advanced BCD ============" -ForegroundColor Cyan; Write-Host ""
    Write-Host "  0. 查看当前高级 BCD 状态（只读）" -ForegroundColor White
    Write-Host "  1. 应用高级计时器配置（useplatformclock / useplatformtick / disabledynamictick / tscsyncpolicy）" -ForegroundColor White
    Write-Host "  2. 恢复高级计时器修改前状态" -ForegroundColor White
    Write-Host "  3. 应用启动安全高级项（NX AlwaysOff / TPM Boot Entropy ForceDisable / nointegritychecks）" -ForegroundColor Yellow
    Write-Host "  4. 恢复启动安全高级项到修改前状态" -ForegroundColor White
    if ([string]::IsNullOrWhiteSpace($Action)) {
        if ($script:TweakNonInteractive) {
            Write-Host '[FAIL] 非交互模式必须通过 -Action 指定高级 BCD 子操作（2=1/2/3/4）。' -ForegroundColor Red
            $script:fail++
            return $false
        }
        $Action = Read-Host "请输入 0、1、2、3 或 4 并回车"
    }

    $timerValues = @('useplatformclock','useplatformtick','disabledynamictick','tscsyncpolicy')
    $securityValues = @('nx','tpmbootentropy','nointegritychecks')
    $allAdvancedValues = @($script:bcdManagedValues)

    switch ($Action.ToLowerInvariant()) {
        '0' {
            $enumOut = (& bcdedit.exe /enum '{current}' 2>&1) -join "`n"
            if ($LASTEXITCODE -ne 0) {
                Write-Host '[FAIL] 无法读取高级 BCD 状态。' -ForegroundColor Red
                $script:fail++
                return $false
            }
            foreach ($name in $allAdvancedValues) {
                $pattern = '(?m)^\s*' + [regex]::Escape($name) + '\s+([^\r\n]+)'
                if ($enumOut -match $pattern) { Write-Host ("bcdedit {0,-22} = {1}" -f $name,$Matches[1].Trim()) }
                else { Write-Host ("bcdedit {0,-22} = <未设置（系统默认）>" -f $name) }
            }
            if (Test-Path -LiteralPath $script:bcdBackupFile -PathType Leaf) { Write-Host "BCD 备份：$script:bcdBackupFile" -ForegroundColor Yellow }
            return $true
        }
        '1' {
            if (-not (Ensure-BcdBackup $allAdvancedValues)) { return $false }
            $commands = @(
                @{ Arguments = '/set useplatformclock no'; Name = 'useplatformclock'; Expected = 'No' },
                @{ Arguments = '/set useplatformtick no'; Name = 'useplatformtick'; Expected = 'No' },
                @{ Arguments = '/set disabledynamictick yes'; Name = 'disabledynamictick'; Expected = 'Yes' },
                @{ Arguments = '/set tscsyncpolicy Enhanced'; Name = 'tscsyncpolicy'; Expected = 'Enhanced' }
            )
            $operationOk = $true
            foreach ($item in $commands) {
                if (-not (Invoke-BcdEdit $item.Arguments ("应用 BCD " + $item.Name))) { $operationOk = $false; break }
            }
            if ($operationOk) {
                foreach ($item in $commands) {
                    if (-not (Verify-BcdValue $item.Name $item.Expected $item.Name)) { $operationOk = $false }
                }
            }
            if (-not $operationOk) {
                Write-Host '[FAIL] 高级 BCD 计时器配置未完整验证，正在按原始快照回滚。' -ForegroundColor Red
                if (-not (Restore-BcdBackup $timerValues)) { Write-Host '[FAIL] 高级 BCD 自动回滚未完全成功。' -ForegroundColor Red }
                return $false
            }
            Write-Host '[提示] BCD 计时器项属于高级/调试用途，效果依硬件与 Windows 版本而异。' -ForegroundColor Yellow
        }
        '2' {
            $result = Restore-BcdBackup $timerValues
            Request-Restart
            return $result
        }
        '3' {
            Write-Host '[WARNING] 启动安全高级项会降低系统安全边界。' -ForegroundColor Yellow
            if (-not (Test-HighRiskConfirmation '确定应用 NX/TPM 熵/驱动完整性安全弱化 BCD 设置吗？')) { return $false }
            if (-not (Ensure-BcdBackup $allAdvancedValues)) { return $false }
            $commands = @(
                @{ Arguments = '/set nx AlwaysOff'; Name = 'nx'; Expected = 'AlwaysOff' },
                @{ Arguments = '/set tpmbootentropy ForceDisable'; Name = 'tpmbootentropy'; Expected = 'ForceDisable' },
                @{ Arguments = '/set nointegritychecks on'; Name = 'nointegritychecks'; Expected = 'Yes' }
            )
            $operationOk = $true
            foreach ($item in $commands) {
                if (-not (Invoke-BcdEdit $item.Arguments ("应用 BCD " + $item.Name))) { $operationOk = $false; break }
            }
            if ($operationOk) {
                foreach ($item in $commands) {
                    if (-not (Verify-BcdValue $item.Name $item.Expected $item.Name)) { $operationOk = $false }
                }
            }
            if (-not $operationOk) {
                Write-Host '[FAIL] 启动安全 BCD 配置未完整验证，正在按原始快照回滚。' -ForegroundColor Red
                if (-not (Restore-BcdBackup $securityValues)) { Write-Host '[FAIL] 启动安全 BCD 自动回滚未完全成功。' -ForegroundColor Red }
                return $false
            }
        }
        '4' {
            $result = Restore-BcdBackup $securityValues
            Request-Restart
            return $result
        }
        default {
            Write-Host "[FAIL] 无效输入：$Action 。请输入 0、1、2、3 或 4" -ForegroundColor Red
            $script:fail++
            return $false
        }
    }

    Write-Host "Finished (Part 2 - Advanced BCD)" -ForegroundColor Cyan
    Write-Host " OK : $script:ok  FAIL : $script:fail  SKIP : $script:skip"
    Request-Restart
    return ($script:fail -eq 0)
}

function Invoke-TestModeEnableModule {
    param([string]$Action = '')
    if (-not [string]::IsNullOrWhiteSpace($Action) -and $Action -notin @('1','apply','enable')) {
        Write-Host "[FAIL] 无效测试模式开启动作：$Action（可用 3=1 或 3=apply）" -ForegroundColor Red
        $script:fail++
        return $false
    }
    if ([string]::IsNullOrWhiteSpace($Action) -and $script:TweakNonInteractive) {
        Write-Host '[FAIL] 非交互模式必须通过 -Action 指定测试模式开启动作（3=1）。' -ForegroundColor Red
        $script:fail++
        return $false
    }

    # ======================= Part 3: 开启测试模式 =======================
    # 独立步骤：开启测试模式 / Enable Test Mode (bcdedit)
    Write-Host ""
    Write-Host "============ [Part 3] 开启测试模式 / Enable Test Mode ============" -ForegroundColor Cyan
    Write-Host ""

    $backupOk = (Ensure-BcdBackup -ValueNames @('testsigning','debug','nointegritychecks') -BackupFile $script:testModeBackupFile) -and
        (Ensure-BcdDebuggerBackup -BackupFile $script:testModeDebuggerBackupFile)
    $enableOk = $false
    if ($backupOk) {
        $enableOk = $true
        foreach ($command in @(
                @{ Arguments = '/set testsigning on'; Label = 'bcdedit /set testsigning on' },
                @{ Arguments = '/debug on'; Label = 'bcdedit /debug on' },
                @{ Arguments = '/dbgsettings local'; Label = 'bcdedit /dbgsettings local' },
                @{ Arguments = '/set nointegritychecks on'; Label = 'bcdedit /set nointegritychecks on' }
            )) {
            if (-not (Invoke-BcdEdit $command.Arguments $command.Label)) { $enableOk = $false; break }
        }
        if (-not $enableOk) {
            Write-Host '[FAIL] 测试模式 BCD 写入未完整完成，正在按开启前快照回滚。' -ForegroundColor Red
            $valueOk = Restore-BcdBackup -ValueNames @('testsigning','debug','nointegritychecks') -BackupFile $script:testModeBackupFile -SchemaNames @('testsigning','debug','nointegritychecks')
            $debuggerOk = Restore-BcdDebuggerBackup -BackupFile $script:testModeDebuggerBackupFile
            $enableOk = $valueOk -and $debuggerOk
        }
    } else {
        Write-Host "[FAIL] 已阻止开启测试模式：原始状态未成功备份。" -ForegroundColor Red
    }

    # Summary
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Finished (Part 3 - Enable Test Mode)" -ForegroundColor Cyan
    Write-Host " OK : $script:ok" -ForegroundColor Green
    Write-Host " FAIL : $script:fail" -ForegroundColor Red
    Write-Host " SKIP : $script:skip" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "提示：开启测试模式后桌面右下角会显示「测试模式」水印，属正常现象。" -ForegroundColor Yellow
    Write-Host "如需关闭测试模式，可运行: bcdedit /set testsigning off" -ForegroundColor Yellow

    Request-Restart
    return $enableOk
}

function Invoke-TestModeDisableModule {
    param([string]$Action = '')
    if (-not [string]::IsNullOrWhiteSpace($Action) -and $Action -notin @('1','disable','restore','off')) {
        Write-Host "[FAIL] 无效测试模式关闭动作：$Action（可用 4=1 或 4=restore）" -ForegroundColor Red
        $script:fail++
        return $false
    }
    if ([string]::IsNullOrWhiteSpace($Action) -and $script:TweakNonInteractive) {
        Write-Host '[FAIL] 非交互模式必须通过 -Action 指定测试模式关闭动作（4=restore）。' -ForegroundColor Red
        $script:fail++
        return $false
    }

    # ======================= Part 4: 关闭测试模式 =======================
    # 独立步骤：关闭测试模式 / Disable Test Mode（保留 nointegritychecks）
    Write-Host ""
    Write-Host "============ [Part 4] 关闭测试模式 / Disable Test Mode ============" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "提示：优先按开启测试模式前的快照恢复 testsigning 和 debug；无快照时退回删除这两项。nointegritychecks 始终保留。" -ForegroundColor Yellow
    Write-Host ""

    $disableOk = $true
    if (Test-Path -LiteralPath $script:testModeBackupFile -PathType Leaf) {
        # 有快照：按原值恢复（原本未设置的删除，原本开启的恢复为开启），不动 nointegritychecks
        $disableOk = Restore-BcdBackup -ValueNames @('testsigning','debug') -BackupFile $script:testModeBackupFile -SchemaNames @('testsigning','debug','nointegritychecks')
        if (Test-Path -LiteralPath $script:testModeDebuggerBackupFile -PathType Leaf) {
            $debuggerRestoreOk = Restore-BcdDebuggerBackup -BackupFile $script:testModeDebuggerBackupFile
            if (-not $debuggerRestoreOk) { $disableOk = $false }
        } else {
            Write-Host '[WARN] 测试模式快照没有 debugger settings；无法证明 dbgsettings local 已恢复。' -ForegroundColor Yellow
            $script:fail++
            $disableOk = $false
        }
    } else {
        Write-Host "[WARNING] 未找到测试模式备份文件，退回直接删除模式；这不是精确原状态恢复。" -ForegroundColor Yellow
        if (-not (Invoke-BcdEdit "/deletevalue testsigning" "bcdedit /deletevalue testsigning")) { $disableOk = $false }
        if (-not (Invoke-BcdEdit "/deletevalue debug" "bcdedit /deletevalue debug")) { $disableOk = $false }
    }

    # Summary
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Finished (Part 4 - Disable Test Mode)" -ForegroundColor Cyan
    Write-Host " OK : $script:ok" -ForegroundColor Green
    Write-Host " FAIL : $script:fail" -ForegroundColor Red
    Write-Host " SKIP : $script:skip" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host '提示：测试模式已关闭，桌面右下角的"测试模式"水印将在重启后消失。' -ForegroundColor Yellow
    Write-Host "如需重新开启测试模式，可运行选项 3。" -ForegroundColor Yellow

    Request-Restart
    return $disableOk
}

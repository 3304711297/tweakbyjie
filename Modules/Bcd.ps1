# Bcd.ps1 - Part 2 高级 BCD / Part 3 开启测试模式 / Part 4 关闭测试模式
# 被 tweakbyjie.ps1 点源加载，共享 $script:ok/$fail/$skip/$rebootRequired

function Invoke-BcdAdvancedModule {
    Write-Host ""; Write-Host "============ [Part 2] 高级 BCD / Advanced BCD ============" -ForegroundColor Cyan; Write-Host ""
    Write-Host "  0. 查看当前高级 BCD 状态（只读）" -ForegroundColor White
    Write-Host "  1. 应用高级计时器配置（useplatformclock / useplatformtick / disabledynamictick / tscsyncpolicy）" -ForegroundColor White
    Write-Host "  2. 恢复高级计时器修改前状态" -ForegroundColor White
    Write-Host "  3. 应用启动安全高级项（NX AlwaysOff / TPM Boot Entropy ForceDisable / nointegritychecks）" -ForegroundColor Yellow
    Write-Host "  4. 恢复启动安全高级项到修改前状态" -ForegroundColor White
    $bChoice=Read-Host "请输入 0、1、2、3 或 4 并回车"
    $timerValues=@('useplatformclock','useplatformtick','disabledynamictick','tscsyncpolicy'); $securityValues=@('nx','tpmbootentropy','nointegritychecks'); $allAdvancedValues=@($script:bcdManagedValues)
    if($bChoice -eq '0'){
        $enumOut=(& bcdedit.exe /enum '{current}' 2>$null)-join "`n"; foreach($name in $allAdvancedValues){$pattern='(?m)^\s*'+[regex]::Escape($name)+'\s+([^\r\n]+)';if($enumOut -match $pattern){Write-Host ("bcdedit {0,-22} = {1}"-f $name,$Matches[1].Trim())}else{Write-Host ("bcdedit {0,-22} = <未设置（系统默认）>"-f $name)}}; if(Test-Path $script:bcdBackupFile){Write-Host "BCD 备份：$script:bcdBackupFile" -ForegroundColor Yellow}
    } elseif($bChoice -eq '1'){
        if(Ensure-BcdBackup $allAdvancedValues){Invoke-BcdEdit "/set useplatformclock no" "Use Platform Clock Off";Invoke-BcdEdit "/set useplatformtick no" "Use Platform Tick Off";Invoke-BcdEdit "/set disabledynamictick yes" "Disable Dynamic Tick";Invoke-BcdEdit "/set tscsyncpolicy Enhanced" "TSC Sync Policy Enhanced";Write-Host "[提示] BCD 计时器项属于高级/调试用途，效果依硬件与 Windows 版本而异。" -ForegroundColor Yellow;Verify-BcdValue 'useplatformclock' 'No' 'useplatformclock'|Out-Null;Verify-BcdValue 'useplatformtick' 'No' 'useplatformtick'|Out-Null;Verify-BcdValue 'disabledynamictick' 'Yes' 'disabledynamictick'|Out-Null;Verify-BcdValue 'tscsyncpolicy' 'Enhanced' 'tscsyncpolicy'|Out-Null}
    } elseif($bChoice -eq '2'){Restore-BcdBackup $timerValues
    } elseif($bChoice -eq '3'){Write-Host '[WARNING] 启动安全高级项会降低系统安全边界。' -ForegroundColor Yellow;if(Ensure-BcdBackup $allAdvancedValues){Invoke-BcdEdit "/set nx AlwaysOff" "NX (DEP) AlwaysOff";Invoke-BcdEdit "/set tpmbootentropy ForceDisable" "TPM Boot Entropy Disabled";Invoke-BcdEdit "/set nointegritychecks on" "Driver Integrity Checks Disabled";Verify-BcdValue 'nx' 'AlwaysOff' 'nx'|Out-Null;Verify-BcdValue 'tpmbootentropy' 'ForceDisable' 'tpmbootentropy'|Out-Null;Verify-BcdValue 'nointegritychecks' 'Yes' 'nointegritychecks'|Out-Null}
    } elseif($bChoice -eq '4'){Restore-BcdBackup $securityValues
    } else {Write-Host "[ERROR] 无效输入：$bChoice 。请输入 0、1、2、3 或 4" -ForegroundColor Red}
    Write-Host "Finished (Part 2 - Advanced BCD)" -ForegroundColor Cyan; Write-Host " OK : $script:ok  FAIL : $script:fail  SKIP : $script:skip"; Request-Restart

}

function Invoke-TestModeEnableModule {

    # ======================= Part 3: 开启测试模式 =======================
    # 独立步骤：开启测试模式 / Enable Test Mode (bcdedit)
    Write-Host ""
    Write-Host "============ [Part 3] 开启测试模式 / Enable Test Mode ============" -ForegroundColor Cyan
    Write-Host ""

    if (Ensure-BcdBackup -ValueNames @('testsigning','debug','nointegritychecks') -BackupFile $script:testModeBackupFile) {
        Invoke-BcdEdit "/set testsigning on" "bcdedit /set testsigning on"
        Invoke-BcdEdit "/debug on" "bcdedit /debug on"
        Invoke-BcdEdit "/dbgsettings local" "bcdedit /dbgsettings local"
        Invoke-BcdEdit "/set nointegritychecks on" "bcdedit /set nointegritychecks on"
    } else {
        Write-Host "[FAIL] 已阻止开启测试模式：原始状态未成功备份。" -ForegroundColor Red
    }

    # Summary
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Finished (Part 3 - Enable Test Mode)" -ForegroundColor Cyan
    Write-Host " OK : $script:ok" -ForegroundColor Green
    Write-Host " FAIL : $script:fail" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "提示：开启测试模式后桌面右下角会显示「测试模式」水印，属正常现象。" -ForegroundColor Yellow
    Write-Host "如需关闭测试模式，可运行: bcdedit /set testsigning off" -ForegroundColor Yellow

    Request-Restart

}

function Invoke-TestModeDisableModule {

    # ======================= Part 4: 关闭测试模式 =======================
    # 独立步骤：关闭测试模式 / Disable Test Mode（保留 nointegritychecks）
    Write-Host ""
    Write-Host "============ [Part 4] 关闭测试模式 / Disable Test Mode ============" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "提示：优先按开启测试模式前的快照恢复 testsigning 和 debug；无快照时退回删除这两项。nointegritychecks 始终保留。" -ForegroundColor Yellow
    Write-Host ""

    if (Test-Path $script:testModeBackupFile) {
        # 有快照：按原值恢复（原本未设置的删除，原本开启的恢复为开启），不动 nointegritychecks
        Restore-BcdBackup -ValueNames @('testsigning','debug') -BackupFile $script:testModeBackupFile -SchemaNames @('testsigning','debug','nointegritychecks') | Out-Null
    } else {
        Write-Host "[WARNING] 未找到测试模式备份文件，退回直接删除模式。" -ForegroundColor Yellow
        Invoke-BcdEdit "/deletevalue testsigning" "bcdedit /deletevalue testsigning"
        Invoke-BcdEdit "/deletevalue debug" "bcdedit /deletevalue debug"
    }

    # Summary
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Finished (Part 4 - Disable Test Mode)" -ForegroundColor Cyan
    Write-Host " OK : $script:ok" -ForegroundColor Green
    Write-Host " FAIL : $script:fail" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host '提示：测试模式已关闭，桌面右下角的"测试模式"水印将在重启后消失。' -ForegroundColor Yellow
    Write-Host "如需重新开启测试模式，可运行选项 3。" -ForegroundColor Yellow

    Request-Restart

}

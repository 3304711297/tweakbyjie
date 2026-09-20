# Defender.ps1 - Part 5 关闭安全中心（策略写入 + 服务停用 + 可选删除类优化）
# 被 tweakbyjie.ps1 点源加载；策略值快照/恢复逻辑见 Modules/Backup.Defender.ps1

function Get-DefenderServiceRecord {
    param([Parameter(Mandatory = $true)][string]$Name)
    $filter = "Name='{0}'" -f $Name.Replace("'", "''")
    return Get-CimInstance -ClassName Win32_Service -Filter $filter -ErrorAction Stop | Select-Object -First 1
}

function Get-DefenderEnvironmentProfile {
    param(
        [object]$MockProductType = $null,
        [object]$MockWscService = 'USE_LIVE',
        [object]$MockHasSecHealthUI = 'USE_LIVE'
    )
    $sku = 'Unknown'
    $isServer = $false
    try {
        if ($null -ne $MockProductType) {
            $pt = [int]$MockProductType
        } else {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop | Select-Object -First 1
            $pt = [int]$os.ProductType
        }
        if ($pt -eq 1) {
            $sku = 'Workstation'
            $isServer = $false
        } elseif ($pt -eq 2 -or $pt -eq 3) {
            $sku = 'Server'
            $isServer = $true
        }
    } catch {
        $sku = 'Unknown'
        $isServer = $false
    }

    $wscCap = 'Unknown'
    if (-not ($MockWscService -is [string] -and $MockWscService -eq 'USE_LIVE')) {
        if ($MockWscService -is [string] -and $MockWscService -eq 'QUERY_FAILED') {
            $wscCap = 'Unknown'
        } elseif ($null -ne $MockWscService) {
            $wscCap = 'Present'
        } else {
            $wscCap = 'Absent'
        }
    } else {
        try {
            $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='wscsvc'" -ErrorAction Stop | Select-Object -First 1
            if ($svc) { $wscCap = 'Present' } else { $wscCap = 'Absent' }
        } catch {
            $wscCap = 'Unknown'
        }
    }

    $uiCap = 'Unknown'
    if (-not ($MockHasSecHealthUI -is [string] -and $MockHasSecHealthUI -eq 'USE_LIVE')) {
        if ($MockHasSecHealthUI -is [string] -and $MockHasSecHealthUI -eq 'QUERY_FAILED') {
            $uiCap = 'Unknown'
        } elseif ($MockHasSecHealthUI -eq $true) {
            $uiCap = 'Present'
        } else {
            $uiCap = 'Absent'
        }
    } else {
        if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
            $uiCap = 'Unknown'
        } else {
            try {
                $app = @(Get-AppxPackage -Name 'Microsoft.SecHealthUI' -ErrorAction Stop)
                if ($app.Count -gt 0) { $uiCap = 'Present' } else { $uiCap = 'Absent' }
            } catch {
                $uiCap = 'Unknown'
            }
        }
    }

    return [pscustomobject]@{
        Sku           = $sku
        IsServer      = $isServer
        WscCapability = $wscCap
        UiCapability  = $uiCap
    }
}

function Get-DefenderDriverResidency {
    param(
        [object]$MockDrivers = $null
    )
    $wdFilter = 'Unknown'
    $msSecCore = 'Unknown'

    if ($null -ne $MockDrivers) {
        if ($MockDrivers -eq 'QUERY_FAILED') {
            $wdFilter = 'Unknown'
            $msSecCore = 'Unknown'
        } else {
            $w = $MockDrivers['WdFilter']
            if ($null -eq $w) { $wdFilter = 'Absent' }
            elseif ($w.State -eq 'Running') { $wdFilter = 'DriverRunning' }
            else { $wdFilter = 'DriverStopped' }

            $m = $MockDrivers['MsSecCore']
            if ($null -eq $m) { $msSecCore = 'Absent' }
            elseif ($m.State -eq 'Running') { $msSecCore = 'DriverRunning' }
            else { $msSecCore = 'DriverStopped' }
        }
    } else {
        try {
            $wDrv = Get-CimInstance -ClassName Win32_SystemDriver -Filter "Name='WdFilter'" -ErrorAction Stop | Select-Object -First 1
            if ($null -eq $wDrv) { $wdFilter = 'Absent' }
            elseif ($wDrv.State -eq 'Running') { $wdFilter = 'DriverRunning' }
            else { $wdFilter = 'DriverStopped' }
        } catch {
            $wdFilter = 'Unknown'
        }

        try {
            $mDrv = Get-CimInstance -ClassName Win32_SystemDriver -Filter "Name='MsSecCore'" -ErrorAction Stop | Select-Object -First 1
            if ($null -eq $mDrv) { $msSecCore = 'Absent' }
            elseif ($mDrv.State -eq 'Running') { $msSecCore = 'DriverRunning' }
            else { $msSecCore = 'DriverStopped' }
        } catch {
            $msSecCore = 'Unknown'
        }
    }

    $isPresent = ($wdFilter -eq 'DriverRunning' -or $msSecCore -eq 'DriverRunning')
    return [pscustomobject]@{
        WdFilterState   = $wdFilter
        MsSecCoreState  = $msSecCore
        IsDriverPresent = $isPresent
    }
}

function Get-DefenderMultiDimensionalStatus {
    param(
        [string]$PolicyState = 'USE_LIVE',
        [string]$WinDefendState = 'USE_LIVE',
        [object]$DriverResidency = $null,
        [string]$TamperProtection = 'USE_LIVE'
    )

    # 1. 真实 Policy 回读
    if ($PolicyState -eq 'USE_LIVE') {
        try {
            $regKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'
            if (Test-Path -LiteralPath $regKey -ErrorAction Stop) {
                $p = Get-ItemProperty -LiteralPath $regKey -ErrorAction Stop
                if ($null -ne $p -and $p.DisableRealtimeMonitoring -eq 1) {
                    $PolicyState = 'Modified'
                } else {
                    $PolicyState = 'Original'
                }
            } else {
                $PolicyState = 'Original'
            }
        } catch {
            $PolicyState = 'Unknown'
        }
    }

    # 2. 真实 WinDefend 服务回读
    if ($WinDefendState -eq 'USE_LIVE') {
        try {
            $svc = Get-DefenderServiceRecord -Name 'WinDefend'
            if ($null -eq $svc) {
                $WinDefendState = 'Absent'
            } elseif ($svc.StartMode -eq 'Disabled' -or $svc.State -eq 'Stopped') {
                $WinDefendState = 'Disabled'
            } else {
                $WinDefendState = 'Running'
            }
        } catch {
            $WinDefendState = 'Unknown'
        }
    }

    # 3. 真实 DriverResidency 回读
    if ($null -eq $DriverResidency) {
        $DriverResidency = Get-DefenderDriverResidency
    }

    # 4. 真实 TamperProtection 回读
    if ($TamperProtection -eq 'USE_LIVE') {
        $TamperProtection = Get-DefenderTamperProtectionState
    }

    $driverPresent = $false
    if ($DriverResidency -and $DriverResidency.IsDriverPresent) {
        $driverPresent = $true
    }

    $driverUnknown = ($DriverResidency -and ($DriverResidency.WdFilterState -eq 'Unknown' -or $DriverResidency.MsSecCoreState -eq 'Unknown'))

    $overall = 'Unknown'
    $verdict = ''

    if ($PolicyState -eq 'Unknown' -or $WinDefendState -eq 'Unknown' -or $driverUnknown -or $TamperProtection -eq 'Unknown') {
        $overall = 'Unknown'
        $verdict = '部分 Defender 状态、篡改防护或驱动探针查询失败，无法得出确切收敛结论。'
    } elseif ($PolicyState -eq 'Modified' -and $TamperProtection -eq 'Enabled') {
        $overall = 'PartiallyApplied'
        $verdict = '策略已写入，但检测到篡改防护 (Tamper Protection) 处于启用状态，策略变更可能被内核旁路。'
    } elseif ($PolicyState -eq 'Modified' -or $WinDefendState -eq 'Disabled' -or $WinDefendState -eq 'Stopped') {
        if ($driverPresent) {
            $overall = 'PendingReboot'
            $verdict = '策略/服务已变更，但内核过滤驱动仍在内存驻留；需重启系统以完全生效。'
        } else {
            $overall = 'Converged'
            $verdict = '核心策略已变更且服务已停用，未检测到活跃过滤驱动。'
        }
    } elseif ($PolicyState -eq 'Original' -and $WinDefendState -eq 'Running') {
        $overall = 'Converged'
        $verdict = 'Defender 处于官方原始启用状态。'
    } else {
        $overall = 'PartiallyApplied'
        $verdict = 'Defender 状态部分应用或处于过渡态。'
    }

    return [pscustomobject]@{
        PolicyStore      = $PolicyState
        TamperProtection = $TamperProtection
        WinDefendService = $WinDefendState
        DriverResidency  = $DriverResidency
        Overall          = $overall
        EffectiveVerdict = $verdict
    }
}

function Get-DefenderTamperProtectionState {
    try {
        $regKey = 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Features'
        if (-not (Test-Path -LiteralPath $regKey)) { return 'Unknown' }
        $props = Get-ItemProperty -LiteralPath $regKey -ErrorAction SilentlyContinue
        if ($null -eq $props -or $null -eq $props.TamperProtection) { return 'Unknown' }
        $val = [int]$props.TamperProtection
        if ($val -eq 5 -or $val -eq 1) { return 'Enabled' }
        if ($val -eq 0 -or $val -eq 4) { return 'Disabled' }
        return "Custom($val)"
    } catch {
        return 'Unknown'
    }
}

function Invoke-DefenderModule {
    param([string]$Action = '')

    Write-Host ""
    Write-Host "============ [Part 5] 关闭安全中心 / Disable Security Center ============" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " [WARNING] 此操作将禁用 Windows Defender 实时保护及相关安全服务！" -ForegroundColor Yellow
    Write-Host " [WARNING] This will disable Windows Defender realtime protection and related services!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1. 应用 Defender/SmartScreen 禁用策略并停用 WinDefend（高风险确认）"
    Write-Host "  1-delete. 在 1 的基础上执行删除类优化（计划任务/启动项/SecHealthUI；不可完整回滚）" -ForegroundColor Red
    Write-Host "  2. 按快照恢复 Defender 策略原始值（defender-policy-backup.json）"
    Write-Host "  0. 返回主菜单"

    $envProfile = Get-DefenderEnvironmentProfile
    if ($envProfile.IsServer) {
        Write-Host ""
        Write-Host " [INFO] 当前环境识别为 Windows Server SKU；WSC 安全中心及 SecHealthUI 界面可能原生不存在。" -ForegroundColor Yellow
    }

    if ([string]::IsNullOrWhiteSpace($Action)) {
        if ($script:TweakNonInteractive) {
            Write-Host '[FAIL] 非交互模式必须通过 -Action 指定 Defender 子操作（1=apply，1-delete=apply+删除，2=restore）。' -ForegroundColor Red
            $script:fail++
            return $false
        }
        $Action = Read-Host "请输入选择并回车"
    }

    $deleteRequested = $false
    switch -Regex ($Action.ToLowerInvariant()) {
        '^(1|apply)$' { $pChoice = '1' }
        '^(1-delete|apply-delete)$' { $pChoice = '1'; $deleteRequested = $true }
        '^(2|restore|reset)$' { $pChoice = '2' }
        '^(0|status)$' { $pChoice = '0' }
        default {
            Write-Host "[FAIL] 无效 Defender 子操作：$Action（可用 0、1、1-delete、2）" -ForegroundColor Red
            $script:fail++
            return $false
        }
    }

    if ($pChoice -eq '0') { Write-Host '[SKIP] 已取消，返回主菜单。' -ForegroundColor Yellow; $script:skip++; return $true }
    if ($pChoice -eq '2') {
        Write-Host ""
        Write-Host " [NOTICE] 本恢复仅执行策略与启动项快照还原（Policy Restore Only）。" -ForegroundColor Yellow
        Write-Host "          若曾执行删除类优化（1-delete），已被停用的驱动服务、删除的计划任务与 SecHealthUI" -ForegroundColor Yellow
        Write-Host "          不在本快照范围内，无法自动闭环复原，需人工干预。" -ForegroundColor Yellow
        $result = Restore-DefenderPolicyBackup
        Request-Restart
        return $result
    }

    # 主禁用路径本身就是高风险操作；过去只有删除分支确认，导致普通 apply 可直接停用 Defender。
    if (-not (Test-HighRiskConfirmation '确定禁用 Defender 实时保护、相关策略和 WinDefend 服务吗？')) {
        Write-Host '[SKIP] Defender 主禁用已取消，未执行策略或服务修改。' -ForegroundColor Yellow
        return $false
    }
    if ($deleteRequested -and -not (Test-HighRiskConfirmation '确定继续执行 Defender 删除类优化吗？该部分没有完整自动回滚。')) {
        Write-Host '[SKIP] 删除类优化已取消；未执行删除类操作。' -ForegroundColor Yellow
        return $false
    }

    # 备份失败则阻止修改；快照一旦存在就保护首次原始状态，不允许覆盖。
    if (-not (Ensure-DefenderPolicyBackup)) { return $false }

    $tamperState = Get-DefenderTamperProtectionState
    if ($tamperState -eq 'Enabled') {
        Write-Host '[WARN] 检测到 Windows Defender 篡改防护 (Tamper Protection) 处于启用状态。' -ForegroundColor Yellow
        Write-Host '       根据 Microsoft 官方规范，篡改防护开启时某些注册表策略变更可能不会生效。' -ForegroundColor Yellow
        Write-Host '       注册表策略写入成功 ≠ Defender 有效状态已经关闭；如需彻底停用，建议先在安全中心手动关闭篡改防护。' -ForegroundColor Yellow
    }

    # --- 策略写入：任一写入失败就不继续停服务，并按原始快照回滚已写入的策略。 ---
    if (-not (Invoke-DefenderPolicyWrites)) {
        Write-Host '[FAIL] Defender 策略未完整写入，已阻止停用服务并尝试回滚策略。' -ForegroundColor Red
        if (-not (Restore-DefenderPolicyBackup)) {
            Write-Host '[FAIL] Defender 策略自动回滚未完全成功，请立即人工检查。' -ForegroundColor Red
        }
        return $false
    }

    # --- Stop Windows Defender Service ---
    Write-Host ""
    Write-Host "[Windows Defender Service]" -ForegroundColor Cyan
    try {
        $defenderSvc = Get-DefenderServiceRecord -Name 'WinDefend'
    } catch {
        Write-Host "[FAIL] 无法查询 Windows Defender Service：$($_.Exception.Message)；正在回滚策略" -ForegroundColor Red
        $script:fail++
        Restore-DefenderPolicyBackup | Out-Null
        return $false
    }
    if ($defenderSvc) {
        try {
            Stop-Service -Name "WinDefend" -Force -ErrorAction Stop
            Set-Service -Name "WinDefend" -StartupType Disabled -ErrorAction Stop
            if (-not (Verify-ServiceStartupType 'WinDefend' 'Disabled' 'Windows Defender Service')) {
                throw 'Windows Defender Service 启动类型回读未达到 Disabled'
            }
            Write-Host "[OK] Windows Defender Service stopped and disabled"
            $script:ok++
            $script:rebootRequired = $true
        } catch {
            Write-Host "[FAIL] Windows Defender Service : $($_.Exception.Message)；正在回滚策略" -ForegroundColor Red
            $script:fail++
            Restore-DefenderPolicyBackup | Out-Null
            return $false
        }
    } else {
        Write-Host "[SKIP] Windows Defender Service not found (already removed or not installed)" -ForegroundColor Yellow
        $script:skip++
    }

    # --- Optional deletion-type optimizations ---
    # 交互模式仍保留二次选择；非交互模式只有显式 1-delete 才能到达这里。
    $runDeletion = $deleteRequested
    if (-not $script:TweakNonInteractive -and -not $deleteRequested) {
        $runDeletion = Test-HighRiskConfirmation "是否执行删除类优化？（停止并禁用 Defender 服务、删除计划任务、移除安全中心界面；没有完整自动回滚）"
    }
    if ($runDeletion) {
        Write-Host ""
        Write-Host "[Defender Services: stop + disable]" -ForegroundColor Cyan
        $defenderServices = @(
            "WinDefend","WdNisSvc","WdNisDrv","WdBoot","WdFilter","wscsvc",
            "SgrmAgent","SgrmBroker","MsSecCore","MsSecFlt","MsSecWfp","whesvc",
            "webthreatdefsvc","webthreatdefusersvc","PlutonHsp2","PlutonHeci","Hsp"
        )
        $deletionStartFail = $script:fail
        $deletionOk = $true
        foreach ($svc in $defenderServices) {
            try {
                $svcObj = Get-DefenderServiceRecord -Name $svc
            } catch {
                Write-Host "[FAIL] 无法查询 Defender 服务 $svc：$($_.Exception.Message)" -ForegroundColor Red
                $script:fail++
                $deletionOk = $false
                break
            }
            if ($svcObj) {
                try {
                    Stop-Service -Name $svc -Force -ErrorAction Stop
                    Set-Service -Name $svc -StartupType Disabled -ErrorAction Stop
                    if (-not (Verify-ServiceStartupType $svc 'Disabled' "Service $svc")) {
                        throw "Service $svc 启动类型回读未达到 Disabled"
                    }
                    Write-Host "[OK] Service $svc stopped and disabled"
                    $script:ok++
                    $script:rebootRequired = $true
                } catch {
                    Write-Host "[FAIL] Service $svc : $($_.Exception.Message)" -ForegroundColor Red
                    $script:fail++
                }
            } else {
                Write-Host "[SKIP] Service $svc not found" -ForegroundColor Yellow
                $script:skip++
            }
            if ($script:fail -gt $deletionStartFail) { $deletionOk = $false; break }
        }

        if ($deletionOk) {
            Write-Host ""
            Write-Host "[Defender Scheduled Tasks]" -ForegroundColor Cyan
            try {
                $defenderTasks = @(Get-ScheduledTask -TaskPath "\Microsoft\Windows\Windows Defender\*" -ErrorAction Stop)
            } catch {
                Write-Host "[FAIL] 无法查询 Defender 计划任务：$($_.Exception.Message)" -ForegroundColor Red
                $script:fail++
                $deletionOk = $false
                $defenderTasks = @()
            }
            if ($deletionOk -and $defenderTasks.Count -gt 0) {
                foreach ($task in $defenderTasks) {
                    try {
                        Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction Stop
                        Write-Host ("[OK] Task deleted: {0}{1}" -f $task.TaskPath, $task.TaskName)
                        $script:ok++
                        $script:rebootRequired = $true
                    } catch {
                        Write-Host ("[FAIL] Task {0}{1} : {2}" -f $task.TaskPath, $task.TaskName, $_.Exception.Message) -ForegroundColor Red
                        $script:fail++
                        $deletionOk = $false
                        break
                    }
                }
            } elseif ($deletionOk) {
                Write-Host "[SKIP] No Defender scheduled tasks found" -ForegroundColor Yellow
                $script:skip++
            }
        }
        if ($deletionOk) {
            Write-Host ""
            Write-Host "[Startup Entries]" -ForegroundColor Cyan
            foreach ($item in $script:defenderStartupValues) {
                try {
                    if (-not (Test-Path -LiteralPath $item.Path -PathType Container -ErrorAction Stop)) {
                        Write-Host ("[SKIP] Startup key not found: {0}" -f $item.Path) -ForegroundColor Yellow
                        $script:skip++
                        continue
                    }
                    $key = Get-Item -LiteralPath $item.Path -ErrorAction Stop
                    if ($key.GetValueNames() -contains $item.Name) {
                        Remove-ItemProperty -LiteralPath $item.Path -Name $item.Name -Force -ErrorAction Stop
                        Write-Host ("[OK] Startup entry removed: {0} -> {1}" -f $item.Path, $item.Name)
                        $script:ok++
                        $script:rebootRequired = $true
                    } else {
                        Write-Host ("[SKIP] Startup entry not found: {0} -> {1}" -f $item.Path, $item.Name) -ForegroundColor Yellow
                        $script:skip++
                    }
                } catch {
                    Write-Host ("[FAIL] Startup entry {0} -> {1} : {2}" -f $item.Path, $item.Name, $_.Exception.Message) -ForegroundColor Red
                    $script:fail++
                    $deletionOk = $false
                    break
                }
            }
        }

        if ($deletionOk) {
            Write-Host ""
            Write-Host "[Security Center UI (SecHealthUI)]" -ForegroundColor Cyan
            if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
                Write-Host "[FAIL] Appx 模块不可用，无法确认 SecHealthUI 状态；已停止删除类优化。" -ForegroundColor Red
                $script:fail++
                $deletionOk = $false
            } else {
                try {
                    $secApp = @()
                    try {
                        $secApp = @(Get-AppxPackage -Name "Microsoft.SecHealthUI" -AllUsers -ErrorAction Stop)
                    } catch {
                        throw "SecHealthUI pre-removal Get-AppxPackage failed: $($_.Exception.Message)"
                    }
                    $provApp = @()
                    if (Get-Command Get-AppxProvisionedPackage -ErrorAction SilentlyContinue) {
                        try {
                            $provApp = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq 'Microsoft.SecHealthUI' -or $_.PackageName -like '*SecHealthUI*' })
                        } catch {
                            throw "SecHealthUI pre-removal Get-AppxProvisionedPackage failed: $($_.Exception.Message)"
                        }
                    }
                    if ($secApp.Count -gt 0 -or $provApp.Count -gt 0) {
                        # 尝试通过 DISM 解除不可移除策略锁定（显式判断退出码）
                        $family = if ($secApp.Count -gt 0) { $secApp[0].PackageFamilyName } else { $null }
                        if (-not $family -and $provApp.Count -gt 0) {
                            $family = "Microsoft.SecHealthUI_8wekyb3d8bbwe"
                        }
                        if ($family) {
                            & dism.exe /online /set-nonremovableapppolicy /packagefamily:$family /nonremovable:0 *> $null
                            if ($LASTEXITCODE -ne 0) {
                                throw "DISM set-nonremovableapppolicy failed with exit code $LASTEXITCODE"
                            }
                            Write-Host "[OK] DISM set-nonremovableapppolicy cleared: $family"
                        }
                        # 卸载 Provisioned 包
                        foreach ($pPkg in $provApp) {
                            Remove-AppxProvisionedPackage -Online -PackageName $pPkg.PackageName -ErrorAction Stop | Out-Null
                        }
                        # 卸载已安装的 AppX
                        if ($secApp.Count -gt 0) {
                            $secApp | Remove-AppxPackage -AllUsers -ErrorAction Stop
                        }
                        # Live readback verification: 确认组件已彻底从系统中消失
                        $remainInstalled = @()
                        try {
                            $remainInstalled = @(Get-AppxPackage -Name "Microsoft.SecHealthUI" -AllUsers -ErrorAction Stop)
                        } catch {
                            throw "SecHealthUI live-readback Get-AppxPackage failed: $($_.Exception.Message)"
                        }
                        $remainProv = @()
                        if (Get-Command Get-AppxProvisionedPackage -ErrorAction SilentlyContinue) {
                            try {
                                $remainProv = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq 'Microsoft.SecHealthUI' -or $_.PackageName -like '*SecHealthUI*' })
                            } catch {
                                throw "SecHealthUI live-readback Get-AppxProvisionedPackage failed: $($_.Exception.Message)"
                            }
                        }
                        if ($remainInstalled.Count -gt 0 -or $remainProv.Count -gt 0) {
                            throw "SecHealthUI live-readback verification failed: package still present after removal"
                        }
                        # 标记 Deprovisioned，防止后续 Windows Update 幽灵复活
                        if ($family) {
                            $deprovStore = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\$family"
                            if (-not (Test-Path -LiteralPath $deprovStore)) {
                                New-Item -Path $deprovStore -Force -ErrorAction Stop | Out-Null
                                if (-not (Test-Path -LiteralPath $deprovStore)) {
                                    throw "Deprovisioned marker creation verification failed: $deprovStore"
                                }
                            }
                        }
                        Write-Host "[OK] SecHealthUI (Windows Security app) removed"
                        $script:ok++
                        $script:rebootRequired = $true
                    } else {
                        Write-Host "[SKIP] SecHealthUI not found" -ForegroundColor Yellow
                        $script:skip++
                    }
                } catch {
                    Write-Host "[FAIL] SecHealthUI 查询或删除失败：$($_.Exception.Message)" -ForegroundColor Red
                    $script:fail++
                    $deletionOk = $false
                }
            }
        }
        if (-not $deletionOk) {
            Write-Host '[FAIL] Defender 删除类优化未完整完成；已停止后续删除，且该分支不提供完整自动回滚。' -ForegroundColor Red
        }
    } else {
        Write-Host "[SKIP] 删除类优化已取消/跳过。" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Finished (Part 5 - Disable Security Center)" -ForegroundColor Cyan
    Write-Host " OK : $($script:ok)" -ForegroundColor Green
    Write-Host " FAIL : $($script:fail)" -ForegroundColor Red
    Write-Host " SKIP : $($script:skip)" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "提示：Windows Defender 已被禁用，重启后生效。" -ForegroundColor Yellow
    Write-Host "策略值和删除类启动项可经 5 -> 2 按 defender-policy-backup.json 快照恢复；" -ForegroundColor Yellow
    Write-Host "计划任务、服务和 SecHealthUI 不在该 JSON 快照内，删除类操作仍需人工复核。" -ForegroundColor Yellow

    $multiStatus = Get-DefenderMultiDimensionalStatus
    Write-Host ""
    Write-Host "--- [Defender 多维运行态诊断] ---" -ForegroundColor Cyan
    Write-Host ("  策略配置层   : {0}" -f $multiStatus.PolicyStore) -ForegroundColor Gray
    Write-Host ("  篡改防护     : {0}" -f $multiStatus.TamperProtection) -ForegroundColor Gray
    Write-Host ("  服务运行态   : {0}" -f $multiStatus.WinDefendService) -ForegroundColor Gray
    Write-Host ("  驱动内存驻留 : {0} (WdFilter={1}, MsSecCore={2})" -f $(if ($multiStatus.DriverResidency.IsDriverPresent) { '驻留中' } else { '已释放/未挂载' }), $multiStatus.DriverResidency.WdFilterState, $multiStatus.DriverResidency.MsSecCoreState) -ForegroundColor Gray
    Write-Host ("  综合运行状态 : {0} -> {1}" -f $multiStatus.Overall, $multiStatus.EffectiveVerdict) -ForegroundColor Yellow
    Request-Restart
    return ($script:fail -eq 0 -and (-not $runDeletion -or $deletionOk))
}

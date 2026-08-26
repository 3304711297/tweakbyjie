# Service.ps1 - Part 6 服务优化（交互编排）
# 备份/恢复逻辑见 Modules/Backup.Service.ps1

function Invoke-ServiceModule {

    # ======================= Part 6: 优化服务项 =======================
    # 独立步骤：禁用可安全禁用的服务 + 将 Xbox / 蓝牙 / 嵌入模式服务恢复为手动
    Write-Host ""
    Write-Host "============ [Part 6] 优化服务项继续工作 / Service Optimization ============" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1. 执行服务优化（A+B 两组共 30 个服务全部处理，另将 7 个服务改为 Manual）" -ForegroundColor White
    Write-Host "  2. 按 service-backup.json 恢复目标服务原始启动类型" -ForegroundColor White
    $serviceChoice = Read-Host "请输入 1 或 2 并回车"
    if ($serviceChoice -eq '2') {
        Restore-ServiceBackup | Out-Null
        Write-Host "[提示] 服务运行状态不强制恢复；如需立即应用启动类型，请重启。" -ForegroundColor Yellow
        Request-Restart
    } elseif ($serviceChoice -eq '1') {

    # 1) Disable service groups
    # A：通常可在不需要对应功能时禁用
    Write-Host "[Service Group A: 通常可禁用 / stop + disable]" -ForegroundColor Cyan
    $groupAServices = @(
        "DialogBlockingService","TrkWks","AppVClient","MsKeyboardFilter",
        "NetTcpPortSharing","CscService","ssh-agent","RemoteRegistry",
        "RemoteAccess","SensorDataService","SensrSvc","shpamsvc",
        "UevAgentService","WalletService","wisvc","WSAIFabricSvc",
        "dmwappushservice","DusmSvc","tzautoupdate","edgeupdate","edgeupdatem"
    )

    # B：按需禁用，可能影响诊断、兼容性、打印、搜索或预读功能
    Write-Host "[Service Group B: 按需禁用 / stop + disable]" -ForegroundColor Cyan
    $groupBServices = @(
        "DPS","WdiServiceHost","WdiSystemHost","diagsvc",
        "PhoneSvc","PcaSvc","Spooler","WSearch","SysMain"
    )

    $disableServices = @($groupAServices + $groupBServices)
    $manualServices = @(
        "XboxGipSvc","XblAuthManager","XboxNetApiSvc","XblGameSave","bthserv","embeddedmode","BITS"
    )
    $allServiceNames = @($disableServices + $manualServices)
    if (-not (Ensure-ServiceBackup $allServiceNames)) {
        Write-Host "[ABORTED] 服务备份不可用，未修改服务" -ForegroundColor Red
    } else {
    foreach ($svc in $disableServices) {
        $svcObj = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($svcObj) {
            try {
                Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                Set-Service -Name $svc -StartupType Disabled -ErrorAction Stop
                $statusAfter = (Get-Service -Name $svc -ErrorAction SilentlyContinue).Status
                if ($statusAfter -eq 'Running') {
                    Write-Host "[OK] Service $svc disabled (still running; will stop after restart)"
                } else {
                    Write-Host "[OK] Service $svc stopped and disabled"
                }
                $script:ok++
                $script:rebootRequired = $true
            } catch {
                & sc.exe config $svc start= disabled *> $null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "[OK] Service $svc disabled (stop rejected: protected service)"
                    $script:ok++
                    $script:rebootRequired = $true
                } else {
                    Write-Host "[FAIL] Service $svc : $($_.Exception.Message)" -ForegroundColor Red
                    $script:fail++
                }
            }
        } else {
            Write-Host "[SKIP] Service $svc not found" -ForegroundColor Yellow
            $script:skip++
        }
    }

    # 2) Set Xbox / Bluetooth / Embedded / BITS services to Manual
    Write-Host ""
    Write-Host "[Manual Services: Xbox / Bluetooth / Embedded / BITS]" -ForegroundColor Cyan
    foreach ($svc in $manualServices) {
        $svcObj = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($svcObj) {
            try {
                Set-Service -Name $svc -StartupType Manual -ErrorAction Stop
                Write-Host "[OK] Service $svc StartupType = Manual"
                $script:ok++
                $script:rebootRequired = $true
            } catch {
                & sc.exe config $svc start= demand *> $null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "[OK] Service $svc StartupType = Manual (sc.exe)"
                    $script:ok++
                    $script:rebootRequired = $true
                } else {
                    Write-Host "[FAIL] Service $svc : $($_.Exception.Message)" -ForegroundColor Red
                    $script:fail++
                }
            }
        } else {
            Write-Host "[SKIP] Service $svc not found" -ForegroundColor Yellow
            $script:skip++
        }
    }

    Write-Host ""
    Write-Host "[Post-Apply Verification / 服务启动类型验证]" -ForegroundColor Cyan
    foreach ($svc in $groupAServices) {
        Verify-ServiceStartupType $svc "Disabled" "Group A / $svc" | Out-Null
    }
    foreach ($svc in $groupBServices) {
        Verify-ServiceStartupType $svc "Disabled" "Group B / $svc" | Out-Null
    }
    foreach ($svc in $manualServices) {
        Verify-ServiceStartupType $svc "Manual" $svc | Out-Null
    }

    # Summary
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Finished (Part 6 - Service Optimization)" -ForegroundColor Cyan
    Write-Host " OK : $script:ok" -ForegroundColor Green
    Write-Host " FAIL : $script:fail" -ForegroundColor Red
    Write-Host " SKIP : $script:skip" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan

    Request-Restart
    }
    } else {
        Write-Host "[ERROR] 无效输入：$serviceChoice 。请输入 1 或 2" -ForegroundColor Red
    }

}

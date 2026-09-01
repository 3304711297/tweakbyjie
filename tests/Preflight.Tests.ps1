# P1-10/P1-11 回归测试：启动预检灰掉 + 高风险短语确认 + -AcceptDefaults 语义
# 运行：Invoke-Pester（CI 自动发现 ./tests/*.Tests.ps1）
BeforeAll {
    . "$PSScriptRoot/../tweakbyjie.ps1" 2>$null
}

Describe "P1-10 模块前置条件映射（Get-TweakModuleAvailability）" {
    It "Secure Boot 开启时仅灰掉模块 3/4，其余可用" {
        $p = [pscustomobject]@{ WindowsBuild = 26100; VbsEnabled = $null; BitLockerOn = $null
            SecureBoot = $true; ThirdPartyAv = $false; ViVeTool = $true }
        $a = Get-TweakModuleAvailability $p
        $a['3'].Available | Should -BeFalse
        $a['4'].Available | Should -BeFalse
        foreach ($n in @('1','2','5','6','7','8','9','10','11')) {
            $a[$n].Available | Should -BeTrue "模块 $n 不应被 Secure Boot 连带灰掉"
        }
    }
    It "第三方杀软仅灰掉模块 5（明确冲突模块），不产生全局阻断" {
        $p = [pscustomobject]@{ WindowsBuild = 26100; VbsEnabled = $null; BitLockerOn = $null
            SecureBoot = $false; ThirdPartyAv = $true; ThirdPartyAvNames = @('某第三方杀软'); ViVeTool = $true }
        $a = Get-TweakModuleAvailability $p
        $a['5'].Available | Should -BeFalse
        $a['5'].Reason | Should -Match '第三方杀软'
        foreach ($n in @('1','2','3','4','6','7','8','9','10','11')) {
            $a[$n].Available | Should -BeTrue "模块 $n 不应被杀软检测连带灰掉"
        }
    }
    It "ViVeTool 缺失仅灰掉模块 8；BitLocker 开启仅灰掉模块 9" {
        $p1 = [pscustomobject]@{ WindowsBuild = 26100; VbsEnabled = $null; BitLockerOn = $null
            SecureBoot = $false; ThirdPartyAv = $false; ViVeTool = $false }
        $a1 = Get-TweakModuleAvailability $p1
        $a1['8'].Available | Should -BeFalse
        foreach ($n in @('1','2','3','4','5','6','7','9','10','11')) { $a1[$n].Available | Should -BeTrue }

        $p2 = [pscustomobject]@{ WindowsBuild = 26100; VbsEnabled = $null; BitLockerOn = $true
            SecureBoot = $false; ThirdPartyAv = $false; ViVeTool = $true }
        $a2 = Get-TweakModuleAvailability $p2
        $a2['9'].Available | Should -BeFalse
        foreach ($n in @('1','2','3','4','5','6','7','8','10','11')) { $a2[$n].Available | Should -BeTrue }
    }
    It "检测项未知（$null）时一律不灰掉（fail-open），全部模块可用" {
        $p = [pscustomobject]@{ WindowsBuild = $null; VbsEnabled = $null; BitLockerOn = $null
            SecureBoot = $null; ThirdPartyAv = $null; ViVeTool = $null }
        $a = Get-TweakModuleAvailability $p
        foreach ($n in @('1','2','3','4','5','6','7','8','9','10','11')) {
            $a[$n].Available | Should -BeTrue "检测未知时模块 $n 应保持可用"
        }
    }
    It "预检结果会缓存到会话（二次调用不重复检测）" {
        $script:TweakPreflight = [pscustomobject]@{ WindowsBuild = 26100; VbsEnabled = $false; BitLockerOn = $false
            SecureBoot = $false; ThirdPartyAv = $false; ViVeTool = $true }
        try {
            Get-TweakPreflight | Should -Be $script:TweakPreflight
        } finally {
            Remove-Variable TweakPreflight -Scope Script -ErrorAction SilentlyContinue
        }
    }
}

Describe "P1-11 高风险短语确认（Test-HighRiskConfirmation）" {
    BeforeAll {
        $script:TweakAcceptDefaults = $false
        $script:ok = 0; $script:fail = 0; $script:skip = 0; $script:rebootRequired = $false
    }
    AfterAll {
        Remove-Variable TweakAcceptDefaults -Scope Script -ErrorAction SilentlyContinue
    }

    It "错误短语不触发执行（返回 false 并计入 skip）" {
        Mock Read-Host { return 'i-understand-risk' }  # 小写也不行（区分大小写）
        $before = $script:skip
        Test-HighRiskConfirmation "确定执行吗？" | Should -BeFalse
        $script:skip | Should -Be ($before + 1)
        Should -Invoke Read-Host -Times 1
    }
    It "空输入/其他内容不触发执行" {
        Mock Read-Host { return '' }
        Test-HighRiskConfirmation "确定执行吗？" | Should -BeFalse
    }
    It "完整短语（区分大小写、完全一致）才放行" {
        Mock Read-Host { return 'I-UNDERSTAND-RISK' }
        Test-HighRiskConfirmation "确定执行吗？" | Should -BeTrue
    }
    It "-AcceptDefaults 无人值守模式自动接受高风险确认，不再询问" {
        $script:TweakAcceptDefaults = $true
        Mock Read-Host { throw '不应发生交互询问' }
        try {
            Test-HighRiskConfirmation "确定执行吗？" | Should -BeTrue
            Should -Invoke Read-Host -Times 0 -Exactly
        } finally {
            $script:TweakAcceptDefaults = $false
        }
    }
}

Describe "P1-10 菜单灰掉（不满足前置条件的模块仅自身被拒，其余正常分发）" {
    BeforeAll {
        $script:TweakAcceptDefaults = $false
    }
    It "队列模式下不可用模块被跳过且不进入执行函数" {
        # 构造 Secure Boot 开启的环境：仅模块 3/4 不适用,模块 11 正常分发
        $script:TweakPreflight = [pscustomobject]@{ WindowsBuild = 26100; VbsEnabled = $null
            BitLockerOn = $null; SecureBoot = $true; ThirdPartyAv = $false; ViVeTool = $true }
        Mock Invoke-TestModeEnableModule { throw '模块 3 已被灰掉,不应进入执行函数' }
        Mock Invoke-MpoModule { }
        try {
            { Show-TweakMenu -RunModules '3,11,0' } | Should -Not -Throw
            Should -Invoke Invoke-TestModeEnableModule -Times 0 -Exactly
            Should -Invoke Invoke-MpoModule -Times 1 -Exactly
        } finally {
            Remove-Variable TweakPreflight -Scope Script -ErrorAction SilentlyContinue
        }
    }
}

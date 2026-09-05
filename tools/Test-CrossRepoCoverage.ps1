[CmdletBinding()]
param(
    [string]$KnowledgeRepo = '3304711297/youshouldknow',
    [string]$KnowledgeRef = ''
)

$ErrorActionPreference = 'Stop'

function Get-RawFile {
    param(
        [Parameter(Mandatory)] [string]$Path
    )
    $encodedPath = ($Path -split '/') | ForEach-Object { [Uri]::EscapeDataString($_) }
    $url = "https://raw.githubusercontent.com/$KnowledgeRepo/$KnowledgeRef/$($encodedPath -join '/')"
    Write-Host "[INFO] Fetch $url"
    return (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30).Content
}

function Get-LocalFile {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$RepoRoot
    )
    $localPath = Join-Path $RepoRoot ($Path -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
        throw "本地覆盖检查文件不存在：$localPath"
    }
    Write-Host "[INFO] Read local file $localPath"
    return Get-Content -LiteralPath $localPath -Raw
}

function Get-Ids {
    param([string]$Text)
    $pattern = '(?<![A-Z0-9])(?:CORE|CPU|GPU|MEMORY|STORAGE|SECURITY|SERVICE|BOOT|POWER|REGISTRY|GAMEQOS)-\d{3}(?![A-Z0-9])'
    return @([regex]::Matches($Text, $pattern) | ForEach-Object Value | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
}

function Get-ModuleSourceRefs {
    # 解析文档中的 Modules/X.ps1 源码引用。
    # 支持 /函数名、#函数名 与 :行号 三种后缀；通配符（如 Backup.*.ps1）不匹配，避免把泛指当成具体文件校验。
    param([string]$Text)
    $refs = @()
    foreach ($match in [regex]::Matches($Text, 'Modules/[A-Za-z0-9_.-]+\.ps1(?:[/#]([A-Za-z][A-Za-z0-9_-]*))?(?::(\d+))?')) {
        $path = $match.Value -replace '([/#][A-Za-z][A-Za-z0-9_-]*)?(:\d+)?$', ''
        $refs += [pscustomobject]@{
            Text = $match.Value
            Path = $path
            Function = $match.Groups[1].Value
        }
    }
    return @($refs | Sort-Object -Property Text -Unique)
}

function Test-ModuleSourceRef {
    # 校验单个源码引用：文件必须存在；带函数名时用 AST 确认函数已在该文件中定义。
    param([object]$Ref, [string]$RepoRoot)
    $path = Join-Path $RepoRoot ($Ref.Path -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return "引用的源码文件不存在：$($Ref.Path)"
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Ref.Function)) {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) {
            return "引用的源码文件无法解析：$($Ref.Path)"
        }
        $defined = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object Name)
        if ($defined -notcontains $Ref.Function) {
            return "引用的函数不存在：$($Ref.Path)/$($Ref.Function)"
        }
    }
    return $null
}

function Compare-IdSet {
    param(
        [string]$Name,
        [string[]]$Expected,
        [string[]]$Actual
    )
    $missing = @($Expected | Where-Object { $_ -notin $Actual })
    $extra = @($Actual | Where-Object { $_ -notin $Expected })
    foreach ($id in $missing) { $script:failures.Add("$Name 缺少清单内项目 $id") }
    foreach ($id in $extra) { $script:failures.Add("$Name 存在未登记项目 $id") }
    if ($missing.Count -eq 0 -and $extra.Count -eq 0) {
        Write-Host "[PASS] $Name 与 Manifest 完全一致 ($($Expected.Count) ids)" -ForegroundColor Green
    }
}

# 点源加载（Pester 测试复用解析函数）只定义函数，不执行审计主流程。
if ($MyInvocation.InvocationName -eq '.') { return }

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$manifestPath = 'docs/项目导航/tweakbyjie-coverage-manifest.json'
$mappingPath = 'docs/项目导航/tweakbyjie-optimization-mapping.md'
$referencePath = 'docs/项目导航/tweakbyjie全量执行参考.md'

# 知识库版本解析:显式 -KnowledgeRef > tools/knowledge.lock.json > main。
# 默认走锁定,使审计结果由 tweakbyjie commit 与知识库 ref 共同决定、可复现,
# 不随 youshouldknow/main 推进而漂移;对最新 main 试跑用 -KnowledgeRef main。
if (-not $KnowledgeRef) {
    $lockPath = Join-Path $PSScriptRoot 'knowledge.lock.json'
    if (Test-Path -LiteralPath $lockPath -PathType Leaf) {
        # -Encoding UTF8 必须显式指定:Windows PowerShell 5.1 默认按系统码页读无 BOM 文件
        $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$lock.repository -ne $KnowledgeRepo) {
            throw "knowledge.lock.json 的 repository 与参数不一致：$($lock.repository) / $KnowledgeRepo"
        }
        if ([string]::IsNullOrWhiteSpace([string]$lock.ref)) {
            throw 'knowledge.lock.json 缺少有效 ref'
        }
        $KnowledgeRef = [string]$lock.ref
        Write-Host "[INFO] Knowledge ref locked: $KnowledgeRef"
    } else {
        $KnowledgeRef = 'main'
        Write-Host '[WARN] 未找到 knowledge.lock.json，回退到 main（结果不可复现）' -ForegroundColor Yellow
    }
}

$failures = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

try {
    $manifest = Get-RawFile $manifestPath | ConvertFrom-Json
    $mapping = Get-RawFile $mappingPath
    $reference = Get-RawFile $referencePath
    $coverageRepository = [string]$manifest.sourceRepository
    if ($manifest.coverageRepository) {
        $coverageRepository = [string]$manifest.coverageRepository
    }
    $coverageBranch = [string]$manifest.sourceBranch
    if ($manifest.coverageBranch) {
        $coverageBranch = [string]$manifest.coverageBranch
    }
    $coveragePath = [string]$manifest.coverageCheck
    if ($coverageRepository -ne '3304711297/tweakbyjie') {
        throw "Manifest coverageRepository 不指向源仓库：$coverageRepository"
    }
    if ($coverageBranch -ne 'main') {
        throw "Manifest coverageBranch 不是 main：$coverageBranch"
    }
    if ([string]::IsNullOrWhiteSpace($coveragePath) -or $coveragePath.StartsWith('../') -or $coveragePath.StartsWith('..\\')) {
        throw "Manifest coverageCheck 必须是源仓库内的相对路径：$coveragePath"
    }
    $coverage = Get-LocalFile $coveragePath $repoRoot
} catch {
    Write-Host "[FAIL] 无法读取跨仓库覆盖审计资料：$($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

$manifestIds = @($manifest.items | ForEach-Object id | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
$mappingIds = Get-Ids $mapping
$referenceIds = Get-Ids $reference
$coverageIds = Get-Ids $coverage

Write-Host ''
Write-Host '=== Cross-Repository Coverage Audit ===' -ForegroundColor Cyan
Write-Host ("Manifest : {0} items" -f $manifestIds.Count)
Write-Host ("Mapping  : {0} ids" -f $mappingIds.Count)
Write-Host ("Reference: {0} ids" -f $referenceIds.Count)
Write-Host ("Coverage : {0} ids" -f $coverageIds.Count)
Write-Host ''

# 每份资料都必须独立做到与 manifest 完全一致:
# 缺少已登记 ID(missing)与出现未登记 ID(extra)都算失败。
# 不允许"另一份资料补上了"的宽松口径——否则单份文档漏项时 CI 仍然绿。
Compare-IdSet -Name 'Mapping vs Manifest' -Expected $manifestIds -Actual $mappingIds
Compare-IdSet -Name 'Execution Reference vs Manifest' -Expected $manifestIds -Actual $referenceIds
Compare-IdSet -Name 'Coverage Check vs Manifest' -Expected $manifestIds -Actual $coverageIds

# Detect stale source-location style that was intentionally removed by module refactor.
if ($mapping -match '(?m)tweakbyjie\.ps1:\d+') {
    $failures.Add('Mapping 仍包含旧式 tweakbyjie.ps1:行号定位；应改用 Modules/文件/函数名')
} else {
    Write-Host -Object '[PASS] Mapping 未发现旧式源码行号定位' -ForegroundColor Green
}

# 校验映射与执行参考中的全部 Modules/*.ps1 源码引用（文件存在 + 函数已定义）。
$sourceRefs = @(Get-ModuleSourceRefs $mapping) + @(Get-ModuleSourceRefs $reference)
$sourceRefs = @($sourceRefs | Sort-Object -Property Text -Unique)
foreach ($ref in $sourceRefs) {
    $problem = Test-ModuleSourceRef $ref $repoRoot
    if ($problem) { $failures.Add($problem) }
}
if ($sourceRefs.Count -gt 0 -and $failures.Count -eq 0) {
    Write-Host "[PASS] $($sourceRefs.Count) 个源码引用（映射+执行参考）均可解析" -ForegroundColor Green
}

# 菜单契约：Menu.ps1 必须仍调度全部 11 个模块入口函数，防止菜单编号与实现脱钩。
$expectedMenuFunctions = @(
    'Invoke-RegistryModule','Invoke-BcdAdvancedModule','Invoke-TestModeEnableModule','Invoke-TestModeDisableModule',
    'Invoke-DefenderModule','Invoke-ServiceModule','Invoke-PowerModule','Invoke-NvmeModule',
    'Invoke-DeviceGuardModule','Invoke-VbsModule','Invoke-MpoModule'
)
$menuPath = Join-Path $repoRoot 'Modules/Menu.ps1'
if (Test-Path -LiteralPath $menuPath -PathType Leaf) {
    $menuSource = Get-Content -LiteralPath $menuPath -Raw
    $missingMenu = @($expectedMenuFunctions | Where-Object { $menuSource -notmatch [regex]::Escape($_) })
    if ($missingMenu.Count -gt 0) {
        $failures.Add("Menu.ps1 缺少模块调度函数：$($missingMenu -join ',')")
    }
} else {
    $failures.Add('Menu.ps1 不存在，无法校验菜单调度契约')
}

# Loader 契约：Modules/ 下每个 .ps1 都必须被主入口点源，防止新增模块被静默遗漏。
$loaderPath = Join-Path $repoRoot 'tweakbyjie.ps1'
$modulesDir = Join-Path $repoRoot 'Modules'
if ((Test-Path -LiteralPath $loaderPath -PathType Leaf) -and (Test-Path -LiteralPath $modulesDir -PathType Container)) {
    $loaderSource = Get-Content -LiteralPath $loaderPath -Raw
    $orphanModules = @(Get-ChildItem -LiteralPath $modulesDir -Filter *.ps1 | ForEach-Object Name | Where-Object { $loaderSource -notmatch [regex]::Escape($_) })
    if ($orphanModules.Count -gt 0) {
        $failures.Add("Loader 未点源模块：$($orphanModules -join ',')")
    }
} else {
    $failures.Add('主 Loader 或 Modules/ 目录缺失，无法校验点源契约')
}

# Report unmapped IDs explicitly before failing, making drift actionable in CI logs.
if ($failures.Count -gt 0) {
    Write-Host ''
    Write-Host '=== FAILURES ===' -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "- $_" -ForegroundColor Red }
}
if ($warnings.Count -gt 0) {
    Write-Host ''
    Write-Host '=== WARNINGS ===' -ForegroundColor Yellow
    $warnings | ForEach-Object { Write-Host "- $_" -ForegroundColor Yellow }
}

Write-Host ''
$resultColor = 'Green'
if ($failures.Count -gt 0) {
    $resultColor = 'Red'
}
$resultText = "Result: {0} failure(s), {1} warning(s)" -f $failures.Count, $warnings.Count
Write-Host -Object $resultText -ForegroundColor $resultColor

if ($failures.Count -gt 0) { exit 1 }
exit 0

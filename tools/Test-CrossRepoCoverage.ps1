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

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Get-LocalFile {
    param(
        [Parameter(Mandatory)] [string]$Path
    )
    $localPath = Join-Path $repoRoot ($Path -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
        throw "本地覆盖检查文件不存在：$localPath"
    }
    Write-Host "[INFO] Read local file $localPath"
    return Get-Content -LiteralPath $localPath -Raw
}

function Get-Ids {
    param([string]$Text)
    $pattern = '(?<![A-Z0-9])(?:CORE|CPU|GPU|MEMORY|STORAGE|SECURITY|SERVICE|BOOT|POWER|REGISTRY)-\d{3}(?![A-Z0-9])'
    return @([regex]::Matches($Text, $pattern) | ForEach-Object Value | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
}

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
    $coverage = Get-LocalFile $coveragePath
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

Compare-IdSet -Name 'Mapping vs Manifest' -Expected $manifestIds -Actual $mappingIds
Compare-IdSet -Name 'Execution Reference vs Manifest' -Expected $manifestIds -Actual $referenceIds
Compare-IdSet -Name 'Coverage Check vs Manifest' -Expected $manifestIds -Actual $coverageIds

# Detect stale source-location style that was intentionally removed by module refactor.
if ($mapping -match '(?m)tweakbyjie\.ps1:\d+') {
    $failures.Add('Mapping 仍包含旧式 tweakbyjie.ps1:行号定位；应改用 Modules/文件/函数名')
} else {
    Write-Host -Object '[PASS] Mapping 未发现旧式源码行号定位' -ForegroundColor Green
}

# Validate every referenced Modules/*.ps1 path and function name against the current checkout.
$moduleRefs = @([regex]::Matches($mapping, 'Modules/[A-Za-z0-9_.-]+\.ps1(?:[:/]\d+)?(?:\s+)?(?:([A-Za-z_][A-Za-z0-9_-]*))?') | ForEach-Object Value | Sort-Object -Unique)
foreach ($ref in $moduleRefs) {
    $match = [regex]::Match($ref, '^(Modules/[A-Za-z0-9_.-]+\.ps1)(?:[:/]\d+)?(?:\s+([A-Za-z_][A-Za-z0-9_-]*))?')
    if (-not $match.Success) { continue }
    $path = Join-Path $repoRoot ($match.Groups[1].Value -replace '/', [IO.Path]::DirectorySeparatorChar)
    $function = $match.Groups[2].Value
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $failures.Add("Mapping 引用的源码文件不存在：$path")
        continue
    }
    if ($function) {
        $source = Get-Content -LiteralPath $path -Raw
        $functionPattern = '(?m)^\s*function\s+' + [regex]::Escape($function) + '\b'
        if ($source -notmatch $functionPattern) {
            $failures.Add("Mapping 引用的函数不存在：$path/$function")
        }
    }
}
if ($moduleRefs.Count -gt 0 -and $failures.Count -eq 0) {
    Write-Host "[PASS] $($moduleRefs.Count) 个源码引用均可解析" -ForegroundColor Green
}

# Basic repository/source drift guard: the mapped modules must be present locally and the loader must still point to them.
$requiredModules = @('Modules/Common.ps1','Modules/Menu.ps1','Modules/Backup.Bcd.ps1','Modules/Backup.Mpo.ps1','Modules/Backup.Nvme.ps1','Modules/Backup.SecurityMitigation.ps1','Modules/Backup.Service.ps1')
foreach ($module in $requiredModules) {
    $modulePath = Join-Path $repoRoot ($module -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
        $failures.Add("必需模块缺失：$module")
    }
}
$loaderPath = Join-Path $repoRoot 'tweakbyjie.ps1'
if (Test-Path -LiteralPath $loaderPath -PathType Leaf) {
    $loaderSource = Get-Content -LiteralPath $loaderPath -Raw
    if ($loaderSource -notmatch 'Modules[/\\]Menu\.ps1') {
        $warnings.Add('主 Loader 未检测到 Modules/Menu.ps1 点源字符串；如入口重构需同步更新审计规则。')
    }
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

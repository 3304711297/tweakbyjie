[CmdletBinding()]
param(
    [string]$KnowledgeRepo = '3304711297/youshouldknow',
    [string]$KnowledgeRef = 'main'
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

function Get-Ids {
    param([string]$Text)
    return @([regex]::Matches($Text, '\b(?:CORE|CPU|GPU|MEMORY|STORAGE|SECURITY|SERVICE|BOOT|POWER|REGISTRY)-\d{3}\b') | ForEach-Object Value | Sort-Object -Unique)
}

$manifestPath = '项目导航/tweakbyjie-coverage-manifest.json'
$mappingPath = '项目导航/tweakbyjie-optimization-mapping.md'
$referencePath = '项目导航/tweakbyjie全量执行参考.md'
$coveragePath = 'docs/coverage/YOUSEHOULDKNOW-COVERAGE-CHECK.md'

$failures = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

try {
    $manifest = Get-RawFile $manifestPath | ConvertFrom-Json
    $mapping = Get-RawFile $mappingPath
    $reference = Get-RawFile $referencePath
    $coverage = Get-RawFile $coveragePath
} catch {
    Write-Host "[FAIL] 无法读取 youshouldknow 覆盖审计资料：$($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

$manifestIds = @($manifest.items | ForEach-Object id | Sort-Object -Unique)
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

function Compare-IdSet {
    param(
        [string]$Name,
        [string[]]$Expected,
        [string[]]$Actual
    )
    $missing = @($Expected | Where-Object { $_ -notin $Actual })
    $extra = @($Actual | Where-Object { $_ -notin $Expected })
    foreach ($id in $missing) { $script:failures.Add("$Name 缺少 $id") }
    foreach ($id in $extra) { $script:failures.Add("$Name 存在未登记项目 $id") }
    if ($missing.Count -eq 0 -and $extra.Count -eq 0) {
        Write-Host "[PASS] $Name ID 集合一致" -ForegroundColor Green
    }
}

Compare-IdSet -Name 'Mapping vs Manifest' -Expected $manifestIds -Actual $mappingIds
Compare-IdSet -Name 'Execution Reference vs Manifest' -Expected $manifestIds -Actual $referenceIds
Compare-IdSet -Name 'Coverage Check vs Manifest' -Expected $manifestIds -Actual $coverageIds

# Detect stale source-location style that was intentionally removed by module refactor.
if ($mapping -match '(?m)tweakbyjie\.ps1:\d+') {
    $failures.Add('Mapping 仍包含旧式 tweakbyjie.ps1:行号定位；应改用 Modules/文件/函数名')
} else {
    Write-Host '[PASS] Mapping 未发现旧式源码行号定位' -ForegroundColor Green
}

# Validate every referenced Modules/*.ps1 path and function name against the current checkout.
$moduleRefs = @([regex]::Matches($mapping, 'Modules/[A-Za-z0-9_.-]+\.ps1(?:[:/]\d+)?(?:\s+)?(?:([A-Za-z_][A-Za-z0-9_-]*))?') | ForEach-Object Value | Sort-Object -Unique)
foreach ($ref in $moduleRefs) {
    $match = [regex]::Match($ref, '^(Modules/[A-Za-z0-9_.-]+\.ps1)(?:[:/]\d+)?(?:\s+([A-Za-z_][A-Za-z0-9_-]*))?')
    if (-not $match.Success) { continue }
    $path = $match.Groups[1].Value -replace '/', [IO.Path]::DirectorySeparatorChar
    $function = $match.Groups[2].Value
    if (-not (Test-Path $path)) {
        $failures.Add("Mapping 引用的源码文件不存在：$path")
        continue
    }
    if ($function) {
        $source = Get-Content -LiteralPath $path -Raw
        if ($source -notmatch "(?m)^\s*function\s+$([regex]::Escape($function))\b") {
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
    if (-not (Test-Path ($module -replace '/', [IO.Path]::DirectorySeparatorChar))) {
        $failures.Add("必需模块缺失：$module")
    }
}
if ((Test-Path 'tweakbyjie.ps1') -and ((Get-Content 'tweakbyjie.ps1' -Raw) -notmatch 'Modules\\Menu\.ps1')) {
    $warnings.Add('主 Loader 未检测到 Modules/Menu.ps1 点源字符串；如入口重构需同步更新审计规则。')
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
Write-Host ("Result: {0} failure(s), {1} warning(s)" -f $failures.Count, $warnings.Count) -ForegroundColor $(if ($failures.Count -eq 0) { 'Green' } else { 'Red' })

if ($failures.Count -gt 0) { exit 1 }
exit 0

# Install-HashLockedModule.ps1 - CI 专用：从 PSGallery 下载 nupkg、校验 SHA256 后解包安装。
# 供应链要求：模块版本与包哈希双双锁定，安装源被投毒或版本被篡改时直接失败。

param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$RequiredVersion,
    [Parameter(Mandatory)][string]$ExpectedSha256
)

$ErrorActionPreference = 'Stop'

$url = "https://www.powershellgallery.com/api/v2/package/$Name/$RequiredVersion"
$pkg = Join-Path $env:RUNNER_TEMP "$Name.$RequiredVersion.nupkg"
Invoke-WebRequest -Uri $url -OutFile $pkg -UseBasicParsing

$actual = (Get-FileHash $pkg -Algorithm SHA256).Hash.ToLower()
if ($actual -ne $ExpectedSha256.ToLower()) {
    throw "$Name.$RequiredVersion 哈希不匹配：expected=$($ExpectedSha256.ToLower()) actual=$actual"
}

$modsRoot = Join-Path $env:RUNNER_TEMP 'psmodules'
$modDir = Join-Path $modsRoot $Name
New-Item -ItemType Directory -Force -Path $modDir | Out-Null
$zip = "$pkg.zip"
Copy-Item $pkg $zip -Force
Expand-Archive -Path $zip -DestinationPath $modDir -Force
Remove-Item $zip -Force

# 锁定版本置于 PSModulePath 首位，优先于 runner 预装版本；同时更新当前步骤和后续步骤环境。
$env:PSModulePath = "$modsRoot;$env:PSModulePath"
if ($env:GITHUB_ENV) {
    "PSModulePath=$env:PSModulePath" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
}
Import-Module $Name -RequiredVersion $RequiredVersion -Force

$loaded = (Get-Module $Name).Version.ToString()
if ($loaded -ne $RequiredVersion) { throw "$Name 实际加载版本 $loaded 与锁定版本不一致" }
Write-Host "[OK] $Name $RequiredVersion 已通过哈希校验安装（SHA256 $actual）"

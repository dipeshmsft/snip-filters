<#
.SYNOPSIS
  Updates C:\configs\tools\snip.exe to a snip release from GitHub.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File C:\configs\tools\update-snip.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File C:\configs\tools\update-snip.ps1 -Version v0.25.2

.NOTES
  - Verifies the zip against the release checksums.txt (SHA-256).
  - Backs up the current binary as snip.v<old-version>.exe next to it.
  - Regenerates user filter aliases (~\.config\snip\gen-aliases.ps1) and runs `snip verify`.
  - Rollback: Copy-Item C:\configs\tools\snip.v<old>.exe C:\configs\tools\snip.exe -Force
#>
param(
    [string]$Version = 'latest',
    [string]$InstallDir = 'C:\configs\tools',
    # Allow replacing a locally built snip (version with a '-suffix', e.g. v0.25.2-gitglobals).
    [switch]$Force,
    # Used by install.ps1, which regenerates aliases and verifies itself.
    [switch]$SkipPostInstall
)

$ErrorActionPreference = 'Stop'
$repo = 'edouard-claude/snip'
$target = Join-Path $InstallDir 'snip.exe'

$api = if ($Version -eq 'latest') { "https://api.github.com/repos/$repo/releases/latest" }
       else { "https://api.github.com/repos/$repo/releases/tags/$Version" }
$headers = @{}
$token = if ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } else { $env:GH_TOKEN }
if ($token) { $headers.Authorization = "Bearer $token" }
try {
    $release = Invoke-RestMethod $api -Headers $headers
} catch {
    throw "Cannot query $api ($($_.Exception.Message)). Check network/proxy access to api.github.com; if rate-limited, set `$env:GITHUB_TOKEN. Or download snip.exe manually (README Troubleshooting)."
}
$tag = $release.tag_name
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
$zipName = "snip_$($tag.TrimStart('v'))_windows_$arch.zip"

$zipAsset = $release.assets | Where-Object name -eq $zipName
$sumAsset = $release.assets | Where-Object name -eq 'checksums.txt'
if (-not $zipAsset -or -not $sumAsset) { throw "Release $tag has no $zipName or checksums.txt" }

$current = if (Test-Path $target) { ((& $target --version) -split '\s+')[1] } else { $null }
if ($current -eq $tag) { Write-Output "snip already at $tag"; return }
if ($current -match '-' -and -not $Force) {
    throw "Installed snip $current is a custom build (source: ~\repos\snip). Upstream $tag may lack its fixes; rebase the branch and rebuild, or rerun with -Force."
}

$tmp = Join-Path $env:TEMP "snip-update-$tag"
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
New-Item -ItemType Directory $tmp | Out-Null
try {
    $zip = Join-Path $tmp $zipName
    Invoke-WebRequest $zipAsset.browser_download_url -OutFile $zip -UseBasicParsing
    $sumFile = Join-Path $tmp 'checksums.txt'
    Invoke-WebRequest $sumAsset.browser_download_url -OutFile $sumFile -UseBasicParsing

    $line = Get-Content $sumFile | Where-Object { ($_ -split '\s+')[-1] -eq $zipName } | Select-Object -First 1
    $expected = if ($line) { ($line -split '\s+')[0] } else { $null }
    $actual = (Get-FileHash $zip -Algorithm SHA256).Hash
    if (-not $expected -or $actual -ne $expected.ToUpper()) { throw "Checksum mismatch for $zipName (expected $expected, got $actual)" }

    Expand-Archive $zip -DestinationPath $tmp -Force
    $newExe = Get-ChildItem $tmp -Recurse -Filter 'snip.exe' | Select-Object -First 1
    if (-not $newExe) { throw "snip.exe not found in $zipName" }

    if ($current) { Copy-Item $target (Join-Path $InstallDir "snip.$current.exe") -Force }
    # A running snip.exe cannot be overwritten, but can be renamed.
    $stale = Join-Path $InstallDir 'snip.locked.exe'
    Remove-Item $stale -Force -ErrorAction SilentlyContinue
    if (Test-Path $target) { Move-Item $target $stale -Force }
    Copy-Item $newExe.FullName $target -Force
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-Output "snip: $current -> $(& $target --version)"

if ($SkipPostInstall) { return }

$gen = Join-Path $HOME '.config\snip\gen-aliases.ps1'
if (Test-Path $gen) { & $gen }
& $target verify | Select-Object -Last 1

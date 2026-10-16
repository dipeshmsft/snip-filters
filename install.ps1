<#
.SYNOPSIS
  Sets up snip for GitHub Copilot CLI on Windows: binary, filters, aliases, agent instructions.

.DESCRIPTION
  1. Installs snip from the upstream GitHub release if it is missing (or -UpdateSnip).
     A custom build (version with a '-suffix') is left alone.
     -AddToPath adds -InstallDir to the user PATH.
  2. Installs ripgrep with winget if rg is not on PATH (skip with -SkipRipgrep).
  3. Copies filters\*.yaml and gen-aliases.ps1 to ~\.config\snip and generates alias filters.
     Installed files are recorded in ~\.config\snip\snip-filters.manifest.json for uninstall.ps1.
  4. Handles the Copilot instructions (-Instructions):
       Write  add/refresh a marked block in ~\.copilot\copilot-instructions.md (default)
       Print  print the rendered block to stdout for manual copy
       Skip   do nothing
  5. Runs `snip verify`.

  Safe to re-run. Undo with uninstall.ps1.

.EXAMPLE
  .\install.ps1
  .\install.ps1 -Instructions Print
  .\install.ps1 -InstallDir 'C:\Program Files\snip' -AddToPath
#>
param(
    [string]$InstallDir = 'C:\configs\tools',
    [ValidateSet('Write', 'Print', 'Skip')]
    [string]$Instructions = 'Write',
    [string]$InstructionsFile = (Join-Path $HOME '.copilot\copilot-instructions.md'),
    [switch]$UpdateSnip,
    [switch]$SkipRipgrep,
    [switch]$AddToPath
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$InstallDir = [IO.Path]::GetFullPath($InstallDir)
$snip = Join-Path $InstallDir 'snip.exe'
$configDir = Join-Path $HOME '.config\snip'
$filterDir = Join-Path $configDir 'filters'
$manifestPath = Join-Path $configDir 'snip-filters.manifest.json'
$beginMarker = '<!-- snip-filters:begin (managed by snip-filters\install.ps1; edits are overwritten) -->'
$endMarker = '<!-- snip-filters:end -->'
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

$manifest = [ordered]@{ installDir = $InstallDir; addedToPath = $false; installedRipgrep = $false; filters = @{} }
if (Test-Path $manifestPath) {
    $old = Get-Content $manifestPath -Raw | ConvertFrom-Json
    $manifest.addedToPath = [bool]$old.addedToPath
    $manifest.installedRipgrep = [bool]$old.installedRipgrep
}

# 1. snip binary
Step "snip binary -> $snip"
New-Item -ItemType Directory $InstallDir -Force | Out-Null
$current = if (Test-Path $snip) { ((& $snip --version) -split '\s+')[1] } else { $null }
if (-not $current -or $UpdateSnip) {
    if ($current -match '-') {
        Write-Host "    $current is a custom build; not replacing it (run scripts\update-snip.ps1 -Force to override)."
    } else {
        & (Join-Path $root 'scripts\update-snip.ps1') -InstallDir $InstallDir -SkipPostInstall
    }
} else {
    Write-Host "    snip $current present (use -UpdateSnip to update)."
}

if ($AddToPath) {
    . (Join-Path $root 'scripts\UserPath.ps1')
    $entries = Get-UserPathEntries
    if ($entries | Where-Object { Test-SamePath $_ $InstallDir }) {
        Write-Host '    Already on user PATH.'
    } else {
        $entries = @($entries)
        # Avoid "a;;dir" when PATH ends with ';'.
        if ($entries.Count -gt 0 -and $entries[-1] -eq '') { $entries = @($entries | Select-Object -SkipLast 1) }
        Set-UserPathEntries ($entries + $InstallDir)
        $manifest.addedToPath = $true
        Write-Host '    Added to user PATH. Open a new terminal to use `snip` directly.'
    }
}

# 2. ripgrep
Step 'ripgrep'
if (Get-Command rg -ErrorAction SilentlyContinue) {
    Write-Host '    rg already on PATH.'
} elseif ($SkipRipgrep) {
    Write-Host '    rg missing; skipped (-SkipRipgrep).'
} elseif (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Warning 'winget not found; rg not installed. Install ripgrep manually (see README Troubleshooting).'
} else {
    winget install --id BurntSushi.ripgrep.MSVC -e --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -eq 0) {
        $manifest.installedRipgrep = $true
        Write-Host '    Installed. Open a new terminal so rg is on PATH.'
    } else {
        Write-Warning "winget install ripgrep failed (exit $LASTEXITCODE). Install it manually (see README Troubleshooting)."
    }
}

# 3. filters + aliases
Step "filters -> $filterDir"
New-Item -ItemType Directory $filterDir -Force | Out-Null
foreach ($f in Get-ChildItem (Join-Path $root 'filters') -Filter '*.yaml') {
    Copy-Item $f.FullName $filterDir -Force
    $manifest.filters[$f.Name] = (Get-FileHash $f.FullName -Algorithm SHA256).Hash
}
Copy-Item (Join-Path $root 'scripts\gen-aliases.ps1') $configDir -Force
& (Join-Path $configDir 'gen-aliases.ps1') -Dir $filterDir
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json), $utf8)

# 4. Copilot instructions
Step "instructions ($Instructions)"
if ($Instructions -ne 'Skip') {
    & $snip check -- git -C x diff *> $null
    $gitFile = if ($LASTEXITCODE -eq 0) { 'git-globals-supported.md' } else { 'git-globals-unsupported.md' }
    $snipPath = $snip -replace '\\', '/'
    # Paths with spaces must be quoted and invoked with the call operator in PowerShell.
    $snipCall = if ($snipPath -match '\s') { "& '$snipPath'" } else { $snipPath }
    $snipCallAmp = if ($snipPath -match '\s') { "& '$snipPath'" } else { "& $snipPath" }
    $text = [IO.File]::ReadAllText((Join-Path $root 'instructions\snip.md'))
    $text = $text.Replace('{{GIT}}', [IO.File]::ReadAllText((Join-Path $root "instructions\$gitFile")).TrimEnd())
    $text = $text.Replace('{{SNIP_AMP}}', $snipCallAmp).Replace('{{SNIP}}', $snipCall).TrimEnd()
    $block = "$beginMarker`n$text`n$endMarker"

    if ($Instructions -eq 'Print') {
        Write-Output $block
    } else {
        New-Item -ItemType Directory (Split-Path $InstructionsFile) -Force | Out-Null
        $existing = if (Test-Path $InstructionsFile) { [IO.File]::ReadAllText($InstructionsFile) } else { '' }
        $pattern = '(?s)' + [regex]::Escape('<!-- snip-filters:begin') + '.*?' + [regex]::Escape($endMarker)
        if ($existing -match $pattern) {
            $new = [regex]::Replace($existing, $pattern, { $block })
            Write-Host "    Refreshed managed block in $InstructionsFile"
        } elseif ($existing -match '(?m)^# Snip - CLI Token Optimizer') {
            Write-Warning "$InstructionsFile has an unmanaged snip section. Remove it, then re-run (or use -Instructions Print)."
            $new = $existing
        } else {
            $sep = if ($existing -and -not $existing.EndsWith("`n")) { "`n`n" } elseif ($existing) { "`n" } else { '' }
            $new = $existing + $sep + $block + "`n"
            Write-Host "    Appended managed block to $InstructionsFile"
        }
        if ($new -ne $existing) {
            [IO.File]::WriteAllText($InstructionsFile, $new, $utf8)
        }
        Write-Host '    Instructions apply to new Copilot sessions.'
    }
}

# 5. verify
Step 'snip verify'
& $snip verify | Select-Object -Last 1
$code = $LASTEXITCODE
Write-Host "snip: $snip" -ForegroundColor Green
exit $code

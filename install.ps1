<#
.SYNOPSIS
  Sets up snip for GitHub Copilot CLI on Windows: binary, filters, aliases, agent instructions.

.DESCRIPTION
  1. Installs snip from the upstream GitHub release if it is missing (or -UpdateSnip).
     A custom build (version with a '-suffix') is left alone.
  2. Installs ripgrep with winget if rg is not on PATH (skip with -SkipRipgrep).
  3. Copies filters\*.yaml and gen-aliases.ps1 to ~\.config\snip and generates alias filters.
  4. Handles the Copilot instructions (-Instructions):
       Write  add/refresh a marked block in ~\.copilot\copilot-instructions.md (default)
       Print  print the rendered block to stdout for manual copy
       Skip   do nothing
  5. Runs `snip verify`.

  Safe to re-run.

.EXAMPLE
  .\install.ps1
  .\install.ps1 -Instructions Print
  .\install.ps1 -InstallDir C:\tools -UpdateSnip
#>
param(
    [string]$InstallDir = 'C:\configs\tools',
    [ValidateSet('Write', 'Print', 'Skip')]
    [string]$Instructions = 'Write',
    [string]$InstructionsFile = (Join-Path $HOME '.copilot\copilot-instructions.md'),
    [switch]$UpdateSnip,
    [switch]$SkipRipgrep
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$snip = Join-Path $InstallDir 'snip.exe'
$configDir = Join-Path $HOME '.config\snip'
$filterDir = Join-Path $configDir 'filters'
$beginMarker = '<!-- snip-filters:begin (managed by snip-filters\install.ps1; edits are overwritten) -->'
$endMarker = '<!-- snip-filters:end -->'

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

# 1. snip binary
Step 'snip binary'
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

# 2. ripgrep
Step 'ripgrep'
if (Get-Command rg -ErrorAction SilentlyContinue) {
    Write-Host '    rg already on PATH.'
} elseif ($SkipRipgrep) {
    Write-Host '    rg missing; skipped (-SkipRipgrep).'
} else {
    winget install --id BurntSushi.ripgrep.MSVC -e --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
    Write-Host '    Installed. Open a new terminal so rg is on PATH.'
}

# 3. filters + aliases
Step "filters -> $filterDir"
New-Item -ItemType Directory $filterDir -Force | Out-Null
Copy-Item (Join-Path $root 'filters\*.yaml') $filterDir -Force
Copy-Item (Join-Path $root 'scripts\gen-aliases.ps1') $configDir -Force
& (Join-Path $configDir 'gen-aliases.ps1') -Dir $filterDir

# 4. Copilot instructions
Step "instructions ($Instructions)"
if ($Instructions -ne 'Skip') {
    & $snip check -- git -C x diff *> $null
    $gitFile = if ($LASTEXITCODE -eq 0) { 'git-globals-supported.md' } else { 'git-globals-unsupported.md' }
    $snipPath = $snip -replace '\\', '/'
    $text = [IO.File]::ReadAllText((Join-Path $root 'instructions\snip.md'))
    $text = $text.Replace('{{GIT}}', [IO.File]::ReadAllText((Join-Path $root "instructions\$gitFile")).TrimEnd())
    $text = $text.Replace('{{SNIP}}', $snipPath).TrimEnd()
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
            [IO.File]::WriteAllText($InstructionsFile, $new, (New-Object System.Text.UTF8Encoding($false)))
        }
        Write-Host '    Instructions apply to new Copilot sessions.'
    }
}

# 5. verify
Step 'snip verify'
& $snip verify | Select-Object -Last 1
exit $LASTEXITCODE

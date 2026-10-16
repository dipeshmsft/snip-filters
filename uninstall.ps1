<#
.SYNOPSIS
  Removes what install.ps1 set up.

.DESCRIPTION
  Default (per-user configuration only):
    - Removes the marked snip-filters block from the Copilot instructions file
      (the rest of the file is untouched; the file is deleted if left empty).
    - Removes the filters installed by install.ps1 from ~\.config\snip\filters, using
      ~\.config\snip\snip-filters.manifest.json. Filters you edited after install are kept
      (warning) unless -Force. Your own filters are never touched; their aliases are regenerated.
    - Removes gen-aliases.ps1 and the manifest.
  Optional:
    -RemoveBinary   delete snip.exe and its snip.*.exe backups from the install dir, and the
                    user PATH entry if install.ps1 -AddToPath added it.
    -RemoveRipgrep  winget uninstall ripgrep.
  snip's own data (~\.local\share\snip: tracking DB, saved logs) is kept unless -RemoveData.

.EXAMPLE
  .\uninstall.ps1
  .\uninstall.ps1 -RemoveBinary -RemoveRipgrep -RemoveData
#>
param(
    [string]$InstructionsFile = (Join-Path $HOME '.copilot\copilot-instructions.md'),
    [string]$InstallDir,
    [switch]$RemoveBinary,
    [switch]$RemoveRipgrep,
    [switch]$RemoveData,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$configDir = Join-Path $HOME '.config\snip'
$filterDir = Join-Path $configDir 'filters'
$manifestPath = Join-Path $configDir 'snip-filters.manifest.json'
$endMarker = '<!-- snip-filters:end -->'
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

$manifest = if (Test-Path $manifestPath) { Get-Content $manifestPath -Raw | ConvertFrom-Json } else { $null }
if (-not $InstallDir) { $InstallDir = if ($manifest) { $manifest.installDir } else { 'C:\configs\tools' } }

# 1. Copilot instructions
Step "instructions: $InstructionsFile"
if (Test-Path $InstructionsFile) {
    $existing = [IO.File]::ReadAllText($InstructionsFile)
    $pattern = '(?s)\r?\n?' + [regex]::Escape('<!-- snip-filters:begin') + '.*?' + [regex]::Escape($endMarker) + '\r?\n?'
    if ($existing -match $pattern) {
        $new = [regex]::Replace($existing, $pattern, "`n").Trim()
        if ($new) {
            [IO.File]::WriteAllText($InstructionsFile, $new + "`n", $utf8)
            Write-Host '    Removed managed block.'
        } else {
            Remove-Item $InstructionsFile
            Write-Host '    Removed managed block; file was otherwise empty and was deleted.'
        }
    } else {
        Write-Host '    No managed block found.'
    }
} else {
    Write-Host '    File not found.'
}

# 2. filters
Step "filters: $filterDir"
if (-not $manifest) {
    Write-Warning "No manifest at $manifestPath; cannot tell which filters install.ps1 added. Remove them manually (README Uninstall)."
} else {
    foreach ($entry in $manifest.filters.PSObject.Properties) {
        $path = Join-Path $filterDir $entry.Name
        if (-not (Test-Path $path)) { continue }
        if (-not $Force -and (Get-FileHash $path -Algorithm SHA256).Hash -ne $entry.Value) {
            Write-Warning "Kept $($entry.Name): modified since install (use -Force to remove)."
            continue
        }
        Remove-Item $path
        Write-Host "    Removed $($entry.Name)"
    }
    $gen = Join-Path $configDir 'gen-aliases.ps1'
    if (Test-Path $gen) {
        & $gen -Dir $filterDir
        Remove-Item $gen
    }
    Remove-Item $manifestPath
}

# 3. binary + PATH
if ($RemoveBinary) {
    Step "binary: $InstallDir"
    Get-ChildItem $InstallDir -Filter 'snip*.exe' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^snip(\..+)?\.exe$' } |
        ForEach-Object {
            try { Remove-Item $_.FullName; Write-Host "    Removed $($_.Name)" }
            catch { Write-Warning "Cannot remove $($_.Name) (in use? close Copilot sessions and retry)." }
        }
    if ($manifest -and $manifest.addedToPath) {
        . (Join-Path $PSScriptRoot 'scripts\UserPath.ps1')
        Set-UserPathEntries @(Get-UserPathEntries | Where-Object { -not (Test-SamePath $_ $InstallDir) })
        Write-Host '    Removed install dir from user PATH.'
    }
}

# 4. ripgrep
if ($RemoveRipgrep) {
    Step 'ripgrep'
    winget uninstall --id BurntSushi.ripgrep.MSVC -e --silent --disable-interactivity
}

# 5. snip data
if ($RemoveData) {
    $data = Join-Path $HOME '.local\share\snip'
    Step "data: $data"
    Remove-Item -Recurse -Force $data -ErrorAction SilentlyContinue
}

Write-Host 'Done. Start a new Copilot session to drop the old instructions.' -ForegroundColor Green

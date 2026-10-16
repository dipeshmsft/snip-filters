# snip-filters

[snip](https://github.com/edouard-claude/snip) filters and setup scripts for the Windows C#/C++ toolchain
(MSBuild, dotnet, TAEF, VSTest, NuGet, TFVC, cdb, CMake/Ninja), tuned for GitHub Copilot CLI agents.

snip is a CLI proxy: `snip -- msbuild App.sln` runs the real command and filters its output before the
agent reads it, keeping errors, warnings, failures and results and dropping progress noise.

## Prerequisites

| Requirement | Notes |
|---|---|
| Windows 10/11, x64 or ARM64 | |
| Windows PowerShell 5.1 or PowerShell 7+ | Both tested |
| Script execution allowed | Run with `-ExecutionPolicy Bypass` as below, or `Unblock-File .\*.ps1, .\scripts\*.ps1` if downloaded as a zip |
| No admin rights | Everything is per-user, as long as you can create `-InstallDir` (default `C:\configs\tools`) |
| Network access | `api.github.com` and `github.com` (snip release download); winget source (ripgrep only) |
| winget | Optional; only used to install ripgrep. Use `-SkipRipgrep` if unavailable |
| GitHub Copilot CLI | Reads `~\.copilot\copilot-instructions.md` |

## Setup

```powershell
git clone https://github.com/dipeshmsft/snip-filters
cd snip-filters
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

`install.ps1` is safe to re-run. It:

1. Installs `snip.exe` to `-InstallDir` from the upstream release if missing (SHA-256 verified).
   `-UpdateSnip` updates it; a custom build (version like `v0.25.2-gitglobals`) is never replaced.
2. Installs ripgrep via winget if `rg` is not on PATH (`-SkipRipgrep` to skip).
3. Copies `filters\*.yaml` to `~\.config\snip\filters`, generates alias filters, and records what it
   installed in `~\.config\snip\snip-filters.manifest.json` (used by `uninstall.ps1`).
4. Agent instructions, via `-Instructions`:
   - `Write` (default): adds/refreshes a marked block in `~\.copilot\copilot-instructions.md`.
     Content outside the markers is untouched. An existing unmarked snip section is reported, not duplicated.
   - `Print`: prints the block for manual copy into any instructions file.
   - `Skip`: no change.
5. Runs `snip verify` and prints the full snip path.

Options:

| Option | Default | Purpose |
|---|---|---|
| `-InstallDir <dir>` | `C:\configs\tools` | Where `snip.exe` goes |
| `-AddToPath` | off | Add `-InstallDir` to the user PATH so `snip` works by name in new terminals |
| `-Instructions Write\|Print\|Skip` | `Write` | See above |
| `-InstructionsFile <file>` | `~\.copilot\copilot-instructions.md` | Target for `Write` |
| `-UpdateSnip` | off | Update an existing upstream snip |
| `-SkipRipgrep` | off | Do not install ripgrep |

Custom install path (quote paths with spaces):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -InstallDir 'C:\Program Files\snip' -AddToPath
```

Generated instructions always use the absolute snip path, quoted with `&` when it has spaces
(`& 'C:/Program Files/snip/snip.exe' -- git status`), so agents do not depend on PATH.

When changes apply: filters and the binary immediately (snip runs per command);
instructions in new Copilot sessions; `-AddToPath` and a fresh ripgrep install in new terminals.

## What goes where

| Item | Location | Scope |
|---|---|---|
| `snip.exe` (+ `snip.<ver>.exe` backups) | `-InstallDir`, default `C:\configs\tools` | Folder you choose; not added to PATH unless `-AddToPath` |
| PATH entry (`-AddToPath`) | `HKCU\Environment\PATH` | Current user |
| Filters, aliases, `gen-aliases.ps1`, manifest | `~\.config\snip\` | Current user |
| Copilot instructions block | `~\.copilot\copilot-instructions.md` | Current user |
| ripgrep | winget (per-user install) | Current user |
| snip data: token tracking DB, saved raw logs | `~\.local\share\snip\` | Current user; created by snip itself |

## Using snip

Commands below assume `$snip` holds the full path (or use `snip` after `-AddToPath` in a new terminal):

```powershell
$snip = 'C:\configs\tools\snip.exe'
& $snip -- dotnet build App.csproj          # filtered run
& $snip proxy -- dotnet build App.csproj    # raw output, no filter
& $snip check -- git -C repo diff           # which filter would apply
& $snip gain                                # tokens saved so far
```

## Filters

| Filter | Commands | Effect |
|---|---|---|
| `msbuild` | msbuild, MSBuild.exe, build.cmd | Keeps errors, warnings, outputs and result; groups repeated warning codes; drops the end-of-build summary repeat |
| `dotnet-build` | dotnet build | Same pipeline; injects `-tl:off` (agent shells are PTYs, so the terminal logger would turn on) |
| `te` | te.exe (TAEF) | Keeps failures, errors and summary |
| `vstest-console` | vstest.console.exe | Drops banner and Passed lines |
| `nuget-restore` | nuget restore | Keeps diagnostics and Restored lines; message when clean |
| `tf-status` | tf status | Drops user/date/lock/workspace columns |
| `cdb` | cdb.exe | Drops ModLoad, banner and symbol-path noise |
| `ninja`, `cmake-build` | ninja, cmake --build | Keeps diagnostics and FAILED lines |
| `git-grep` | git grep | Truncates long lines, caps results |
| `git-show` | git show | Overrides built-in: `git show rev:path` content is not truncated |
| `git-status` | git status | Overrides built-in: says "working tree clean" instead of printing nothing |
| `rg` | rg | Overrides built-in: cap 80 lines with a `+N more lines` count |

Filters with the same `name` as a built-in snip filter override it.

### Aliases

snip matches command names case-sensitively and does not strip `.exe`. A filter lists extra names in a header comment:

```yaml
# aliases: msbuild.exe, MSBuild.exe
```

`scripts\gen-aliases.ps1` writes one `alias--<name>@<alias>.yaml` copy per alias. Re-run it (or `install.ps1`) after editing a filter.

## Editing filters

1. Edit `filters\<name>.yaml`; add a case under `tests:`.
2. `.\install.ps1 -Instructions Skip` to deploy and run `snip verify`.
3. Check a command with `& $snip check -- <cmd> <args>`; see raw output with `& $snip proxy -- <cmd>`.

## Scripts

| Script | Purpose |
|---|---|
| `install.ps1` | Full setup (above) |
| `uninstall.ps1` | Undo setup (below) |
| `scripts\update-snip.ps1` | Install/update snip from a release with SHA-256 check; backs up the old exe as `snip.<ver>.exe`; refuses to replace a custom build without `-Force` |
| `scripts\gen-aliases.ps1` | Regenerate alias filters |
| `scripts\UserPath.ps1` | User PATH helpers (preserve `%VAR%` entries) |

## Troubleshooting

| Symptom | Fix |
|---|---|
| `running scripts is disabled on this system` | Use `powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1`, or `Unblock-File` the scripts |
| `Cannot query https://api.github.com/...` | Check proxy/network access to `api.github.com`. Rate-limited (60 requests/hour without sign-in): set `$env:GITHUB_TOKEN` and retry |
| Release download blocked | Download `snip_<ver>_windows_amd64.zip` from the [releases page](https://github.com/edouard-claude/snip/releases), put `snip.exe` in `-InstallDir`, re-run `install.ps1` (it skips the download when snip exists) |
| `winget not found` / winget install failed | Re-run with `-SkipRipgrep`; install ripgrep from its [releases](https://github.com/BurntSushi/ripgrep/releases) and put `rg.exe` on PATH |
| `rg` or `snip` not found right after install | Open a new terminal (PATH changes apply to new processes) |
| `snip.exe` in use during update | Close Copilot sessions and retry; the updater also renames a locked exe to `snip.locked.exe` |
| Warning: unmanaged snip section | Delete the old `# Snip - CLI Token Optimizer` section from the instructions file and re-run, or use `-Instructions Print` |
| Copilot does not use snip | Start a new session; check the block exists in `~\.copilot\copilot-instructions.md` |
| Output looks wrong or incomplete | `& $snip proxy -- <cmd>` for raw output; `& $snip check -- <cmd>` to see the filter; failed commands print a `[full output: <path>]` log |
| `snip verify` fails | A filter test broke; run `& $snip verify` to see which, fix the YAML, re-run install |
| Roll back snip | `Copy-Item <InstallDir>\snip.<ver>.exe <InstallDir>\snip.exe -Force` |
| Restore instructions | Remove the block between the `snip-filters:begin`/`end` markers, or run `uninstall.ps1` |

## Uninstall

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1                 # config only
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1 -RemoveBinary -RemoveRipgrep -RemoveData   # everything
```

Default removes the instructions block (deleting the file if nothing else is left) and the filters this
repo installed. Filters edited after install are kept with a warning (`-Force` removes them); your own
filters are never touched.

| Option | Removes |
|---|---|
| `-RemoveBinary` | `snip.exe` and `snip.*.exe` backups in the install dir; the PATH entry if `-AddToPath` added it |
| `-RemoveRipgrep` | ripgrep (winget) |
| `-RemoveData` | `~\.local\share\snip` (token tracking DB, saved logs) |
| `-InstallDir <dir>` | Override the install dir recorded in the manifest |

Manual removal (no manifest): delete the marked block from `~\.copilot\copilot-instructions.md`, delete
this repo's `filters\*.yaml` names and `alias--*.yaml` from `~\.config\snip\filters`, and delete `snip.exe`.

## git global options

Upstream snip treats `git -C <path> diff` / `git --no-pager log` options as the subcommand, so no filter matches.
The fix lives on branch `feat/git-global-options` of [dipeshmsft/snip](https://github.com/dipeshmsft/snip).
To use it (requires Go), build and install it:

```powershell
cd <snip clone>; git switch feat/git-global-options
$env:CGO_ENABLED = '0'
go build -o C:\configs\tools\snip.exe -ldflags "-s -w -X 'github.com/edouard-claude/snip/internal/cli.version=0.25.2-gitglobals'" ./cmd/snip
```

Then re-run `install.ps1`; it detects support (`snip check -- git -C x diff`) and writes the matching git guidance.

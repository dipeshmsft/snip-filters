# snip-filters

[snip](https://github.com/edouard-claude/snip) filters and setup scripts for the Windows C#/C++ toolchain
(MSBuild, dotnet, TAEF, VSTest, NuGet, TFVC, cdb, CMake/Ninja), tuned for GitHub Copilot CLI agents.

## Setup

```powershell
git clone https://github.com/dipeshmsft/snip-filters
cd snip-filters
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

`install.ps1` is idempotent. It:

1. Installs `snip.exe` to `-InstallDir` (default `C:\configs\tools`) from the upstream release if missing.
   `-UpdateSnip` updates it; a custom build (version like `v0.25.2-gitglobals`) is never replaced.
2. Installs ripgrep via winget if `rg` is not on PATH (`-SkipRipgrep` to skip).
3. Copies `filters\*.yaml` to `~\.config\snip\filters` and generates alias filters.
4. Agent instructions, via `-Instructions`:
   - `Write` (default): adds/refreshes a marked block in `~\.copilot\copilot-instructions.md`.
     Content outside the markers is untouched. An existing unmarked snip section is reported, not duplicated.
   - `Print`: prints the block for manual copy into any instructions file.
   - `Skip`: no change.
5. Runs `snip verify`.

New Copilot sessions pick up instruction changes. Filters and the binary apply immediately (snip runs per command).

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
3. Check a command: `snip check -- <cmd> <args>`; see raw output with `snip proxy -- <cmd>`.

CI (`.github/workflows/verify.yml`) runs the install and `snip verify` on Windows.

## Scripts

| Script | Purpose |
|---|---|
| `install.ps1` | Full setup (above) |
| `scripts\update-snip.ps1` | Install/update snip from a release with SHA-256 check; backs up the old exe as `snip.<ver>.exe`; refuses to replace a custom build without `-Force` |
| `scripts\gen-aliases.ps1` | Regenerate alias filters |

## git global options

Upstream snip treats `git -C <path> diff` / `git --no-pager log` options as the subcommand, so no filter matches.
The fix lives on branch `feat/git-global-options` of [dipeshmsft/snip](https://github.com/dipeshmsft/snip).
To use it, build and install it:

```powershell
cd <snip clone>; git switch feat/git-global-options
$env:CGO_ENABLED = '0'
go build -o C:\configs\tools\snip.exe -ldflags "-s -w -X 'github.com/edouard-claude/snip/internal/cli.version=0.25.2-gitglobals'" ./cmd/snip
```

Then re-run `install.ps1`; it detects support (`snip check -- git -C x diff`) and writes the matching git guidance.

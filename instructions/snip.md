# Snip - CLI Token Optimizer

Prefix **external executables** with snip to reduce token usage: `{{SNIP}} -- <exe> <args>`
(git, dotnet, msbuild/MSBuild.exe, build.cmd, rg, te.exe, vstest.console.exe, nuget, tf, cdb, cmake, ninja, go).

```
{{SNIP}} -- git status
{{SNIP}} -- dotnet build App.csproj
{{SNIP_AMP}} -- 'C:\Program Files\...\MSBuild.exe' App.sln
```

Do NOT use snip for PowerShell cmdlets (Get-ChildItem, Get-Content, Select-String, ...),
script blocks, `$var = ...` assignments, or pipelines: snip cannot execute them and fails.

## Searching, listing and reading files

PowerShell cmdlets are the largest unfiltered token source. Avoid them for file work:
- Search contents: use the built-in **grep** tool; in shell, `{{SNIP}} -- rg <pattern> <path>`. Never `Select-String`/`findstr` over source trees or logs.
- List files: use the built-in **glob** tool; in shell, `{{SNIP}} -- rg --files -g '<glob>' <path>`. Never recursive `Get-ChildItem`.
- Read files: use the built-in **view** tool with `view_range` for large files. Never `Get-Content` a whole file.
- Build/test logs: search with `rg -n 'error|FAILED' <log>` or view a range; never print the whole log.
- If a cmdlet is unavoidable, bound it: `| Select-Object -First 50`, `-Tail 50`, `| Measure-Object`, or select only needed properties.

{{GIT}}

rg through snip caps at 80 lines and prints `+N more lines`; narrow the pattern/path or use `-l`/`-c` rather than raising limits.

Need unfiltered output? `{{SNIP}} proxy -- <cmd>`, or read the log path snip prints after a failed command.

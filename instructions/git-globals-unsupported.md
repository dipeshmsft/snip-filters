git: snip cannot match commands with options placed before the subcommand.
- Not `git -C <path> diff` → `Set-Location <path>; {{SNIP}} -- git diff`
- Never pass `--no-pager` (not needed; agent output is not a terminal).

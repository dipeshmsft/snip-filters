# Helpers to add/remove a directory on the user PATH without expanding %VAR% entries
# or changing the registry value kind. Dot-source: . .\scripts\UserPath.ps1

function Get-UserPathEntries {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
    try {
        $raw = $key.GetValue('PATH', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    } finally { $key.Close() }
    # Keep empty entries so a remove round-trips the value exactly.
    @($raw -split ';')
}

function Set-UserPathEntries([string[]]$Entries) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    try {
        $key.SetValue('PATH', ($Entries -join ';'), [Microsoft.Win32.RegistryValueKind]::ExpandString)
    } finally { $key.Close() }

    # Tell Explorer/new terminals that the environment changed.
    if (-not ('SnipFilters.NativeMethods' -as [type])) {
        Add-Type -Namespace SnipFilters -Name NativeMethods -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    }
    $result = [UIntPtr]::Zero
    [void][SnipFilters.NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result)
}

function Test-SamePath([string]$A, [string]$B) {
    if (-not $A -or -not $B) { return $false }
    [Environment]::ExpandEnvironmentVariables($A).TrimEnd('\') -ieq [Environment]::ExpandEnvironmentVariables($B).TrimEnd('\')
}

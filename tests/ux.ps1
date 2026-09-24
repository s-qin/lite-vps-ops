$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$launcher = Join-Path $root 'lite-vps-ops.ps1'
$controller = Join-Path $root 'controller/lite-vps-ops.ps1'

foreach ($file in @($launcher, $controller)) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count) { throw "PowerShell parse failed: $file`n$($errors -join "`n")" }
}

$command = Get-Command $launcher
if ('Host' -notin $command.Parameters['HostAlias'].Aliases) { throw 'Launcher does not expose -Host.' }
$source = Get-Content -Raw $launcher
if ($source -notmatch 'if \(\$Check\) \{ ''check'' \} else \{ ''deploy'' \}') { throw 'Launcher does not map Deploy/Check.' }
$controllerSource = Get-Content -Raw $controller
foreach ($mode in @('deploy', 'check', 'audit', 'apply', 'validate', 'repair', 'health')) {
    if ($controllerSource -notmatch "'$mode'") { throw "Controller mode missing: $mode" }
}
if ($controllerSource -notmatch '\[string\]\$Version = ''v1\.1\.1''') { throw 'Controller default version mismatch.' }
foreach ($obsolete in @('ssh-blackbox-token', 'ssh-confirm-timeout', 'Start-Job', 'ready gate')) {
    if ($controllerSource -match [regex]::Escape($obsolete)) { throw "Obsolete SSH confirmation surface remains: $obsolete" }
}
if ((Get-Content -Raw $launcher) -match 'TimeoutSeconds') { throw 'Root launcher retains obsolete confirmation timeout.' }
Write-Output 'PASS UX: root -Host Deploy/Check and synchronous advanced controller modes parse correctly'

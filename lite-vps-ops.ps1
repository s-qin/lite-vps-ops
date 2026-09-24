[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [Alias('Host')]
    [string]$HostAlias,
    [switch]$Check,
    [ValidateSet('tiny', 'standard', 'auto')]
    [string]$Profile = 'auto',
    [ValidateSet('preserve', 'on', 'off')]
    [string]$HealthTimer = 'preserve'
)

$ErrorActionPreference = 'Stop'
$command = if ($Check) { 'check' } else { 'deploy' }
$controller = Join-Path $PSScriptRoot 'controller/lite-vps-ops.ps1'
& $controller -HostAlias $HostAlias -Profile $Profile -Command $command -Version 'v1.1.1' -HealthTimer $HealthTimer
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

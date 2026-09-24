[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$HostAlias,
    [ValidateSet('tiny', 'standard', 'auto')]
    [string]$Profile = 'auto',
    [ValidateSet('audit', 'apply', 'validate', 'repair', 'health')]
    [string]$Command = 'apply',
    [string]$Version = 'v1.1.0',
    [ValidateSet('preserve', 'on', 'off')]
    [string]$HealthTimer = 'preserve',
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+$') { throw 'Invalid version.' }
& ssh -o BatchMode=yes -o ConnectTimeout=10 $HostAlias 'true'
if ($LASTEXITCODE -ne 0) { throw 'Initial SSH connection failed.' }

$bootstrap = "https://github.com/s-qin/lite-vps-ops/releases/download/$Version/bootstrap.sh"
$timerArgument = if ($HealthTimer -eq 'preserve') { '' } else { " --health-timer $HealthTimer" }
$remoteBase = "set -eu; if ! command -v curl >/dev/null 2>&1; then sudo -n apt-get update; sudo -n apt-get install -y --no-install-recommends ca-certificates curl; fi; d=`$(mktemp -d); trap 'rm -rf -- `"`$d`"' EXIT; curl -fL --proto '=https' --tlsv1.2 -o `"`$d/bootstrap.sh`" '$bootstrap'; sudo -n bash `"`$d/bootstrap.sh`" $Command --profile $Profile$timerArgument"

if ($Command -notin @('apply', 'repair')) {
    & ssh -o BatchMode=yes -o ConnectTimeout=10 $HostAlias $remoteBase
    if ($LASTEXITCODE -ne 0) { throw "Remote $Command exited $LASTEXITCODE" }
    exit 0
}

$token = ([guid]::NewGuid().ToString('N'))
$ready = "/run/lite-vps-ops/ssh-$token.ready"
$proof = "/run/lite-vps-ops/ssh-$token.passed"
$remote = "$remoteBase --ssh-blackbox-token $token"

$job = Start-Job -ScriptBlock {
    param($Alias, $RemoteCommand)
    & ssh -o BatchMode=yes -o ConnectTimeout=10 $Alias $RemoteCommand 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Remote apply exited $LASTEXITCODE" }
} -ArgumentList $HostAlias, $remote

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$proved = $false
try {
    while ((Get-Date) -lt $deadline) {
        $job = Get-Job -Id $job.Id
        if ($job.State -ne 'Running') { break }
        & ssh -o BatchMode=yes -o ConnectTimeout=10 $HostAlias "sudo -n test -f '$ready' && printf '%s\n' '$token' | sudo -n tee '$proof' >/dev/null"
        if ($LASTEXITCODE -eq 0) { $proved = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $proved -and $job.State -eq 'Running') { throw 'Timed out before the remote operation completed or reached the SSH ready gate.' }
    Receive-Job -Job $job -Wait
    if ($job.State -ne 'Completed') { throw "Remote job state: $($job.State)" }
    & ssh -o BatchMode=yes -o ConnectTimeout=10 $HostAlias 'true'
    if ($LASTEXITCODE -ne 0) { throw 'Post-commit SSH continuity check failed.' }
}
finally {
    if ($job.State -eq 'Running') { Stop-Job -Job $job }
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
}

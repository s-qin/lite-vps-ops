[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$HostAlias,
    [ValidateSet('tiny', 'standard', 'auto')]
    [string]$Profile = 'auto',
    [ValidateSet('deploy', 'check', 'audit', 'apply', 'validate', 'repair', 'health')]
    [string]$Command = 'apply',
    [string]$Version = 'v1.1.1',
    [ValidateSet('preserve', 'on', 'off')]
    [string]$HealthTimer = 'preserve'
)

$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+$') { throw 'Invalid version.' }
& ssh -o BatchMode=yes -o ConnectTimeout=10 $HostAlias 'true'
if ($LASTEXITCODE -ne 0) { throw 'Initial SSH connection failed.' }

$bootstrap = "https://github.com/s-qin/lite-vps-ops/releases/download/$Version/bootstrap.sh"
$timerArgument = if ($HealthTimer -eq 'preserve') { '' } else { " --health-timer $HealthTimer" }
$remoteBase = "set -eu; if ! command -v curl >/dev/null 2>&1; then sudo -n apt-get update; sudo -n apt-get install -y --no-install-recommends ca-certificates curl; fi; d=`$(mktemp -d); trap 'rm -rf -- `"`$d`"' EXIT; curl -fL --proto '=https' --tlsv1.2 -o `"`$d/bootstrap.sh`" '$bootstrap'; sudo -n bash `"`$d/bootstrap.sh`" $Command --profile $Profile$timerArgument"

& ssh -o BatchMode=yes -o ConnectTimeout=10 $HostAlias $remoteBase
if ($LASTEXITCODE -ne 0) { throw "Remote $Command exited $LASTEXITCODE" }

if ($Command -in @('deploy', 'apply', 'repair')) {
    & ssh -o BatchMode=yes -o ConnectTimeout=10 $HostAlias 'true'
    if ($LASTEXITCODE -ne 0) { throw 'Post-commit SSH continuity check failed.' }
}
